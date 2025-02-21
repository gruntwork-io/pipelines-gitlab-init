#!/usr/bin/env bash

set -euo pipefail

set -x

: "${APERTURE_OIDC_TOKEN:?"APERTURE_OIDC_TOKEN must be set"}"
: "${API_BASE_URL:?"API_BASE_URL must be set"}"
: "${CI_COMMIT_SHA:?"Need to set CI_COMMIT_SHA"}"
: "${CI_JOB_ID:?"Need to set CI_JOB_ID"}"
: "${CI_PROJECT_ID:?"Need to set CI_PROJECT_ID"}"
: "${CI_PROJECT_URL:?"Need to set CI_PROJECT_URL"}"
: "${GRUNTWORK_PIPELINES_ACTIONS_REF:?"Need to set GRUNTWORK_PIPELINES_ACTIONS_REF"}"
: "${PIPELINES_CLI_VERSION:?"Need to set PIPELINES_CLI_VERSION"}"
: "${PIPELINES_GITLAB_TOKEN:?"Need to set PIPELINES_GITLAB_TOKEN"}"

CI_MERGE_REQUEST_IID="${CI_MERGE_REQUEST_IID:-}"

GITLAB_TOKEN=$PIPELINES_GITLAB_TOKEN
export GITLAB_TOKEN

get_merge_request_id() {
    if [[ -n "$CI_MERGE_REQUEST_IID" ]]; then
        echo "$CI_MERGE_REQUEST_IID"
    else
        # Look for the merge request ID for the current commit
        local -r merge_requests=$(
            GITLAB_TOKEN=$PIPELINES_GITLAB_TOKEN \
                glab api "projects/$CI_PROJECT_ID/repository/commits/$CI_COMMIT_SHA/merge_requests" \
                --paginate
        )
        # Find the first merge request with "state": "merged"
        local -r merge_request_id="$(echo "$merge_requests" | jq -r 'map(select( .state=="merged" )) | sort_by(.updated_at) | .[-1] | .iid')"
        if [[ -z "$merge_request_id" ]]; then
            echo "Could not find a merged merge request for commit $CI_COMMIT_SHA" >&2
        fi
        echo "$merge_request_id"
    fi
}

merge_request_id=$(get_merge_request_id)
merge_request_notes="$(glab api "projects/$CI_PROJECT_ID/merge_requests/$merge_request_id/notes" --paginate)"

collapse_older_pipelines_notes() {
    # get all notes authored by @gruntwork-ci BUT do not contain the sticky header
    local -r notes_to_collapse=$(echo "$merge_request_notes" | jq -r '. | map(select(.body | contains("<!-- $CI_COMMIT_SHA -->") | not)) | map(select(.author.username == "gruntwork-ci")) | .[].id')

    # Read each note ID line by line
    while IFS= read -r note_id; do
        if [[ -n "$note_id" ]]; then
            # wrap the note in a details tag
            local -r note_body=$(jq -r --arg id "$note_id" '. | map(select(.id == ($id|tonumber))) | .[].body' <<<"$merge_request_notes")

            # if note_body has not already been wrapped in a details tag, wrap it in a details tag
            if [[ ! "$note_body" =~ ^[[:space:]]*"<details>" ]]; then
                local -r collapsed_body="<details><summary>Previous Pipeline Run</summary>$note_body</details>"
                glab api "projects/$CI_PROJECT_ID/merge_requests/$merge_request_id/notes/$note_id" --method PUT --raw-field "body=$collapsed_body"
            fi
        fi
    done <<<"$notes_to_collapse"
}

sticky_comment() {
    local -r body=$1
    local -r sticky_header="<!-- $CI_COMMIT_SHA -->"
    local -r sticky_body="$sticky_header
$body"

    local -r existing_note_id=$(echo "$merge_request_notes" | jq -r --arg sticky_header "$sticky_header" '. | map(select(.body | startswith($sticky_header))) | .[].id')

    if [[ -n "$existing_note_id" ]]; then
        glab api "projects/$CI_PROJECT_ID/merge_requests/$merge_request_id/notes/$existing_note_id" --method PUT --raw-field "body=$sticky_body"
    else
        glab api "projects/$CI_PROJECT_ID/merge_requests/$merge_request_id/notes" --raw-field "body=$sticky_body"
    fi
}

report_error() {
    local message=$1

    if [[ -n "$merge_request_id" ]]; then
        sticky_comment "<h2>❌ Gruntwork Pipelines is unable to run</h2>❌ $message<br><br><a href=\"$CI_PROJECT_URL/-/jobs/$CI_JOB_ID\">View full logs</a>"
        collapse_older_pipelines_notes
    fi
    echo "$message"
}

get_gruntwork_read_token() {
    export PIPELINES_TOKEN_PATH="pipelines-read/gruntwork-io"
    SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
    node "$SCRIPT_DIR/pipelines-credentials.mjs" >&2
    # The node script writes the token to a file, so we need to source it to make it available
    set -a
    source credentials.sh
    set +a
    echo "$PIPELINES_GRUNTWORK_READ_TOKEN"
}

# Exchange the APERTURE_OIDC_TOKEN for a Gruntwork Read token
set +e
PIPELINES_GRUNTWORK_READ_TOKEN=$(get_gruntwork_read_token)
get_gruntwork_read_token_exit_code=$?
set -e

if [[ $get_gruntwork_read_token_exit_code -ne 0 ]]; then
    report_error "Failed to authenticate with the Gruntwork API"
    exit 1
fi

# Make the token available to other sections in the rest of the current job
export PIPELINES_GRUNTWORK_READ_TOKEN
echo "PIPELINES_GRUNTWORK_READ_TOKEN=$PIPELINES_GRUNTWORK_READ_TOKEN" >>"$GITLAB_ENV"
echo "PIPELINES_GRUNTWORK_READ_TOKEN=$PIPELINES_GRUNTWORK_READ_TOKEN" >>build.env

# Clone the pipelines-actions repository
set +e
git clone -b "$GRUNTWORK_PIPELINES_ACTIONS_REF" "https://oauth2:$PIPELINES_GRUNTWORK_READ_TOKEN@github.com:/gruntwork-io/pipelines-gitlab-actions.git" /tmp/pipelines-actions
clone_exit_code=$?
set -e

if [[ $clone_exit_code -ne 0 ]]; then
    report_error "Failed to clone the pipelines-actions repository"
    exit 1
fi

# Install the Pipelines CLI
set +e
/tmp/pipelines-actions/scripts/install-pipelines.sh
install_exit_code=$?
set -e

if [[ $install_exit_code -ne 0 ]]; then
    report_error "Failed to install the Pipelines CLI"
    exit 1
fi

if [[ -n "$merge_request_id" ]]; then
    collapse_older_pipelines_notes
fi
