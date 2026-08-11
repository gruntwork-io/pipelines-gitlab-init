#!/usr/bin/env bash
#
# Mints a fresh Gruntwork read token for the current job.
#
# The read token is a GitHub App installation token that expires one hour after it is minted.
# It is minted once in the orchestrate job and handed to downstream jobs through the build.env
# dotenv artifact, so a job that starts more than an hour into a pipeline inherits an expired
# token. Source this script before cloning a Gruntwork repository:
#
#   source /tmp/pipelines-gitlab-init/scripts/refresh-credentials.sh
#
# Requires an APERTURE_OIDC_TOKEN id token and API_BASE_URL; without them the inherited token
# is kept. Because it is sourced, this script avoids set -e, set -u and exec, which would leak
# into the calling job shell.

# Token handling runs untraced so PIPELINES_LOG_LEVEL=debug|trace does not print the token
case $- in
*x*) refresh_credentials_trace="on" ;;
*) refresh_credentials_trace="off" ;;
esac
set +x

refresh_credentials_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=scripts/lib/credentials.sh
source "$refresh_credentials_dir/lib/credentials.sh"

refresh_credentials() {
    if [[ "${PIPELINES_GRUNTWORK_READ_TOKEN_SOURCE:-}" == "ci_variable" ]]; then
        printf "PIPELINES_GRUNTWORK_READ_TOKEN was configured as a CI variable, skipping refresh.\n"
        return 0
    fi

    if [[ -z "${APERTURE_OIDC_TOKEN:-}" || -z "${API_BASE_URL:-}" ]]; then
        printf "WARNING: APERTURE_OIDC_TOKEN or API_BASE_URL is not set, keeping the inherited PIPELINES_GRUNTWORK_READ_TOKEN.\n" >&2
        return 0
    fi

    printf "Refreshing the Gruntwork read token... "
    local credentials_log token
    credentials_log=$(mktemp -t pipelines-credentials-XXXXXXXX.log)

    if ! token=$(mint_gruntwork_read_token "$credentials_log"); then
        printf "failed.\n"
        cat "$credentials_log" >&2

        # A transient API failure should not break a job that already holds a working token;
        # let the clone report the problem if the token really has expired.
        if [[ -n "${PIPELINES_GRUNTWORK_READ_TOKEN:-}" ]]; then
            printf "WARNING: keeping the inherited PIPELINES_GRUNTWORK_READ_TOKEN.\n" >&2
            return 0
        fi
        printf "ERROR: failed to authenticate with the Gruntwork API and no PIPELINES_GRUNTWORK_READ_TOKEN is available.\n" >&2
        return 1
    fi

    publish_gruntwork_read_token "$token" "aperture"
    printf "done.\n"
}

refresh_credentials
refresh_credentials_exit_code=$?

if [[ "$refresh_credentials_trace" == "on" ]]; then
    set -x
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit "$refresh_credentials_exit_code"
fi

return "$refresh_credentials_exit_code"
