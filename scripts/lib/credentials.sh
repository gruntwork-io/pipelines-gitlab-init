#!/usr/bin/env bash
#
# Reusable helpers for obtaining, verifying and publishing the Gruntwork read token.
#
# Sourcing this file has no side effects: it only defines functions. It is safe to source
# from a job shell (see ../refresh-credentials.sh) as well as from init.sh.
#
# The Gruntwork read token is a GitHub App installation token with a one hour lifetime, so
# every job that needs it must obtain its own rather than inherit one minted by an earlier
# job in the pipeline.

# pipelines_credentials_trace_state echoes "on" when shell tracing is currently enabled.
# Token handling runs with tracing disabled so PIPELINES_LOG_LEVEL=debug|trace never prints
# credentials into the job log.
pipelines_credentials_trace_state() {
    case $- in
    *x*) printf "on\n" ;;
    *) printf "off\n" ;;
    esac
}

# pipelines_mint_gruntwork_read_token exchanges APERTURE_OIDC_TOKEN for a Gruntwork read
# token and echoes the token on stdout. Output from the exchange is written to the log file
# passed as the first argument so callers can surface it on failure.
#
# Usage: token=$(pipelines_mint_gruntwork_read_token "$log_file")
pipelines_mint_gruntwork_read_token() {
    local -r credentials_log="$1"
    local -r trace_state=$(pipelines_credentials_trace_state)
    set +x

    # Declared local so that sourcing the credentials file below assigns to this scope
    # rather than clobbering the caller's value when the exchange fails.
    local PIPELINES_GRUNTWORK_READ_TOKEN=""
    local exit_code=0

    local -r script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
    local -r credentials_file=$(mktemp -t pipelines-credentials-XXXXXXXX.sh)

    if PIPELINES_TOKEN_PATH="pipelines-read/gruntwork-io" \
        PIPELINES_CREDENTIALS_OUTPUT_FILE="$credentials_file" \
        node "$script_dir/pipelines-credentials.mjs" >"$credentials_log" 2>&1; then
        # The node script writes the token to a file, so we need to source it to read it back
        # shellcheck source=/dev/null
        source "$credentials_file"
        if [[ -z "$PIPELINES_GRUNTWORK_READ_TOKEN" ]]; then
            printf "The Gruntwork API returned an empty read token\n" >>"$credentials_log"
            exit_code=1
        fi
    else
        exit_code=1
    fi

    rm -f "$credentials_file"

    if [[ $exit_code -eq 0 ]]; then
        printf "%s\n" "$PIPELINES_GRUNTWORK_READ_TOKEN"
    fi

    if [[ "$trace_state" == "on" ]]; then
        set -x
    fi

    return $exit_code
}

# pipelines_verify_gruntwork_read_token checks that the given token can read the
# pipelines-gitlab-actions repository. Output is written to the log file passed as the
# second argument. Returns the curl exit code so callers decide how to report failures.
#
# Usage: pipelines_verify_gruntwork_read_token "$token" "$log_file"
pipelines_verify_gruntwork_read_token() {
    local -r token="$1"
    local -r verify_log="$2"
    local -r trace_state=$(pipelines_credentials_trace_state)
    set +x

    local exit_code=0
    curl -sS -f -H "Authorization: token $token" \
        "https://api.github.com/repos/gruntwork-io/pipelines-gitlab-actions" \
        >"$verify_log" 2>&1 || exit_code=$?

    if [[ "$trace_state" == "on" ]]; then
        set -x
    fi

    return $exit_code
}

# pipelines_publish_gruntwork_read_token exports the token for the rest of the current job
# and records it, along with where it came from, in $GITLAB_ENV and build.env so downstream
# jobs inherit it via the dotenv artifact.
#
# build.env is only updated when it already exists. Jobs that publish a dotenv artifact
# create it in their before_script, while jobs that merely refresh their own credentials
# have no downstream consumers and should not leave a file behind in the checked out
# repository.
#
# The token source is either "aperture" (minted from the job's OIDC identity, refreshable)
# or "ci_variable" (supplied by the customer as a CI variable, never refreshed).
#
# Usage: pipelines_publish_gruntwork_read_token "$token" aperture
pipelines_publish_gruntwork_read_token() {
    local -r token="$1"
    local -r token_source="$2"
    local -r trace_state=$(pipelines_credentials_trace_state)
    set +x

    export PIPELINES_GRUNTWORK_READ_TOKEN="$token"
    export PIPELINES_GRUNTWORK_READ_TOKEN_SOURCE="$token_source"

    if [[ -n "${GITLAB_ENV:-}" ]]; then
        pipelines_set_env_file_var "$GITLAB_ENV" "PIPELINES_GRUNTWORK_READ_TOKEN" "$token"
        pipelines_set_env_file_var "$GITLAB_ENV" "PIPELINES_GRUNTWORK_READ_TOKEN_SOURCE" "$token_source"
    fi

    if [[ -f build.env ]]; then
        pipelines_set_env_file_var "build.env" "PIPELINES_GRUNTWORK_READ_TOKEN" "$token"
        pipelines_set_env_file_var "build.env" "PIPELINES_GRUNTWORK_READ_TOKEN_SOURCE" "$token_source"
    fi

    if [[ "$trace_state" == "on" ]]; then
        set -x
    fi
}

# pipelines_set_env_file_var writes KEY=VALUE to an env file, replacing any existing entry
# for that key. Replacing rather than appending matters because consumers re-export every
# line of the file, so a stale token line surviving alongside a fresh one is a live hazard.
#
# Usage: pipelines_set_env_file_var "$file" KEY value
pipelines_set_env_file_var() {
    local -r file="$1"
    local -r key="$2"
    local -r value="$3"

    if [[ -f "$file" ]]; then
        local -r tmp_file=$(mktemp "${file}.XXXXXXXX")
        grep -v "^${key}=" "$file" >"$tmp_file" || true
        mv "$tmp_file" "$file"
    fi

    printf "%s=%s\n" "$key" "$value" >>"$file"
}
