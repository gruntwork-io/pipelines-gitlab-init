#!/usr/bin/env bash

set -euo pipefail

: "${CI_COMMIT_SHA:?"Need to set CI_COMMIT_SHA"}"
: "${CI_JOB_ID:?"Need to set CI_JOB_ID"}"
: "${CI_PROJECT_ID:?"Need to set CI_PROJECT_ID"}"
: "${CI_PROJECT_URL:?"Need to set CI_PROJECT_URL"}"
: "${PIPELINES_GITLAB_TOKEN:?"Need to set PIPELINES_GITLAB_TOKEN"}"

CI_MERGE_REQUEST_IID="${CI_MERGE_REQUEST_IID:-}"

GITLAB_TOKEN=$PIPELINES_GITLAB_TOKEN
export GITLAB_TOKEN

get_merge_request_id() {
    if [[ -n "$CI_MERGE_REQUEST_IID" ]]; then
        echo "$CI_MERGE_REQUEST_IID"
    else
        # Look for the merge request ID for the current commit
        merge_requests=$(GITLAB_TOKEN=$PIPELINES_GITLAB_TOKEN \
            glab api "projects/$CI_PROJECT_ID/repository/commits/$CI_COMMIT_SHA/merge_requests" \
            --paginate
        )
        # Find the first merge request with "state": "merged"
        merge_request_id="$(echo "$merge_requests" | jq -r 'map(select( .state=="merged" )) | sort_by(.updated_at) | .[-1] | .iid')"
        if [[ -z "$merge_request_id" ]]; then
            echo "Could not find a merged merge request for commit $CI_COMMIT_SHA" >&2
            exit 1
        fi
        echo "$merge_request_id"
    fi
}

sticky_comment() {
    local body=$1
    sticky_header="<!-- $CI_COMMIT_SHA -->\n"

    merge_request_id="$(get_merge_request_id)"

    existing_note_id="$(glab api "projects/$CI_PROJECT_ID/merge_requests/$merge_request_id/notes" \
        --paginate \
        | jq -r --arg sticky_header "$sticky_header" '. | map(select(.body | startswith($sticky_header))) | .[].id')"

    if [[ -n "$existing_note_id" ]]; then
            glab api "projects/$CI_PROJECT_ID/merge_requests/$merge_request_id/notes/$existing_note_id" --raw-field "body=$body"
    else
            glab api "projects/$CI_PROJECT_ID/merge_requests/$merge_request_id/notes" --raw-field "body=$body"
    fi
}

report_error() {
    local message=$1

    merge_request_id=$(get_merge_request_id)
    
    sticky_comment "<h2>❌ Gruntwork Pipelines is unable to run</h2>❌ $message<br><br><a href=\"$CI_PROJECT_URL/-/jobs/$CI_JOB_ID\">View full logs</a>"
}

report_error "This is a test error message"
