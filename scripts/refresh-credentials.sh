#!/usr/bin/env bash
#
# Mint a fresh Gruntwork read token for the current job.
#
# The Gruntwork read token is a GitHub App installation token that expires one hour after it
# is minted. Because the token is minted once in the orchestrate job and handed to every
# downstream job through the build.env dotenv artifact, any job that starts more than an
# hour into a pipeline inherits an expired token and fails to clone Gruntwork repositories.
# Running this script at the start of a job replaces the inherited token with a fresh one
# minted from that job's own OIDC identity.
#
# This script is designed to be sourced so the refreshed token lands in the calling job
# shell, ahead of any clone that needs it:
#
#   git clone --depth 1 -b "$PIPELINES_GITLAB_INIT_REF" https://github.com/gruntwork-io/pipelines-gitlab-init.git /tmp/pipelines-gitlab-init
#   source /tmp/pipelines-gitlab-init/scripts/refresh-credentials.sh
#
# It can also be executed directly, in which case the refreshed token is only available via
# $GITLAB_ENV, and via build.env when that file already exists.
#
# Unlike init.sh this script has no merge request side effects: it does not fetch or collapse
# notes, clone pipelines-gitlab-actions, or install the Pipelines CLI. It also deliberately
# avoids `set -e`, `set -u` and `exec`, all of which would leak into or break the calling
# job shell when sourced.

pipelines_refresh_credentials_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=scripts/lib/credentials.sh
source "$pipelines_refresh_credentials_dir/lib/credentials.sh"

# pipelines_refresh_credentials runs the refresh with shell tracing disabled, so a job
# running with PIPELINES_LOG_LEVEL=debug|trace never prints token material into its log.
pipelines_refresh_credentials() {
    local trace_state
    trace_state=$(pipelines_credentials_trace_state)
    set +x

    local exit_code=0
    pipelines_refresh_credentials_untraced || exit_code=$?

    if [[ "$trace_state" == "on" ]]; then
        set -x
    fi

    return $exit_code
}

pipelines_refresh_credentials_untraced() {
    if [[ "${PIPELINES_GRUNTWORK_READ_TOKEN_SOURCE:-}" == "ci_variable" ]]; then
        printf "PIPELINES_GRUNTWORK_READ_TOKEN was configured as a CI variable, skipping refresh.\n"
        return 0
    fi

    if [[ -z "${APERTURE_OIDC_TOKEN:-}" ]]; then
        printf "WARNING: APERTURE_OIDC_TOKEN is not available, keeping the inherited PIPELINES_GRUNTWORK_READ_TOKEN.\n" >&2
        return 0
    fi

    if [[ -z "${API_BASE_URL:-}" ]]; then
        printf "WARNING: API_BASE_URL is not available, keeping the inherited PIPELINES_GRUNTWORK_READ_TOKEN.\n" >&2
        return 0
    fi

    printf "Refreshing the Gruntwork read token... "

    local credentials_log
    credentials_log=$(mktemp -t pipelines-credentials-XXXXXXXX.log)

    local token
    if ! token=$(pipelines_mint_gruntwork_read_token "$credentials_log"); then
        printf "failed.\n"
        cat "$credentials_log" >&2

        # A transient Gruntwork API failure should not break a job that already holds a
        # working token, so fall back to the inherited value and let the clone report the
        # problem if the token really has expired.
        if [[ -n "${PIPELINES_GRUNTWORK_READ_TOKEN:-}" ]]; then
            printf "WARNING: keeping the inherited PIPELINES_GRUNTWORK_READ_TOKEN.\n" >&2
            return 0
        fi

        printf "ERROR: failed to authenticate with the Gruntwork API and no PIPELINES_GRUNTWORK_READ_TOKEN is available.\n" >&2
        return 1
    fi

    pipelines_publish_gruntwork_read_token "$token" "aperture"
    printf "done.\n"
}

pipelines_refresh_credentials
pipelines_refresh_credentials_exit_code=$?

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit "$pipelines_refresh_credentials_exit_code"
fi

return "$pipelines_refresh_credentials_exit_code"
