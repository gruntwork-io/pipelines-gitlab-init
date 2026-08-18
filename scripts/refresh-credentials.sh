#!/usr/bin/env bash
#
# Mints a fresh Gruntwork read token for the current job.
#
# The read token is a GitHub App installation token that expires one hour after it is minted.
# It is minted once in the orchestrate job and handed to downstream jobs through the build.env
# dotenv artifact, so a job that starts more than an hour into a pipeline inherits an expired
# token. Run this before cloning a Gruntwork repository, then re-read build.env to pick the
# refreshed token up in the job shell:
#
#   /tmp/pipelines-gitlab-init/scripts/refresh-credentials.sh
#   set -a && source build.env && set +a
#
# The job must declare an APERTURE_OIDC_TOKEN id token and set API_BASE_URL, unless the token
# was supplied as a CI variable, in which case there is nothing to refresh.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=scripts/lib/credentials.sh
source "$SCRIPT_DIR/lib/credentials.sh"

if [[ "${PIPELINES_GRUNTWORK_READ_TOKEN_SOURCE:-}" == "ci_variable" ]]; then
    printf "PIPELINES_GRUNTWORK_READ_TOKEN was configured as a CI variable, skipping refresh.\n"
    exit 0
fi

: "${APERTURE_OIDC_TOKEN:?"APERTURE_OIDC_TOKEN must be set"}"
: "${API_BASE_URL:?"API_BASE_URL must be set"}"

printf "Refreshing the Gruntwork read token... "
credentials_log=$(mktemp -t pipelines-credentials-XXXXXXXX.log)

if ! token=$(mint_gruntwork_read_token "$credentials_log"); then
    printf "failed.\n"
    cat "$credentials_log" >&2

    # A transient API failure should not break a job that already holds a working token;
    # let the clone report the problem if the token really has expired.
    if [[ -n "${PIPELINES_GRUNTWORK_READ_TOKEN:-}" ]]; then
        printf "WARNING: keeping the inherited PIPELINES_GRUNTWORK_READ_TOKEN.\n" >&2
        exit 0
    fi
    printf "ERROR: failed to authenticate with the Gruntwork API and no PIPELINES_GRUNTWORK_READ_TOKEN is available.\n" >&2
    exit 1
fi

publish_gruntwork_read_token "$token" "aperture"
printf "done.\n"
