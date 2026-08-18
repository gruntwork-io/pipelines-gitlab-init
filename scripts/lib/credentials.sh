#!/usr/bin/env bash

# Exchanges APERTURE_OIDC_TOKEN for a Gruntwork read token and echoes the token.
# Exchange output is written to the log file given as $1.
# Usage: token=$(mint_gruntwork_read_token "$log_file")
mint_gruntwork_read_token() {
    local -r credentials_log="$1"
    local -r script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
    local -r credentials_file=$(mktemp -t pipelines-credentials-XXXXXXXX.token)
    local token=""

    trap "rm -f '$credentials_file'" EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if PIPELINES_TOKEN_PATH="pipelines-read/gruntwork-io" \
        PIPELINES_CREDENTIALS_OUTPUT_FILE="$credentials_file" \
        node "$script_dir/pipelines-credentials.mjs" >"$credentials_log" 2>&1; then
        token=$(<"$credentials_file")
    fi
    rm -f "$credentials_file"
    trap - EXIT INT TERM

    if [[ -z "$token" ]]; then
        return 1
    fi
    printf "%s\n" "$token"
}

# Exports the token for the rest of the current job and records it in $GITLAB_ENV
# and build.env for downstream jobs. The source is "aperture" (minted from the
# job's OIDC identity, refreshable) or "ci_variable" (customer supplied, never
# refreshed).
# Usage: publish_gruntwork_read_token "$token" aperture
publish_gruntwork_read_token() {
    local -r token="$1"
    local -r token_source="$2"

    export PIPELINES_GRUNTWORK_READ_TOKEN="$token"
    export PIPELINES_GRUNTWORK_READ_TOKEN_SOURCE="$token_source"

    local env_file
    for env_file in "${GITLAB_ENV:-}" build.env; do
        if [[ -n "$env_file" ]]; then
            printf "PIPELINES_GRUNTWORK_READ_TOKEN=%s\nPIPELINES_GRUNTWORK_READ_TOKEN_SOURCE=%s\n" \
                "$token" "$token_source" >>"$env_file"
        fi
    done
}
