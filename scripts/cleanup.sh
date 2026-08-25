#!/usr/bin/env bash
set -e

REPO="${GITHUB_REPOSITORY}"
TOKEN="${GH_TOKEN}"

API="https://api.github.com/repos/${REPO}"

echo "======================================"
echo "Cleanup Releases"
echo "Keep newest 3"
echo "======================================"

curl -fsSL \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${API}/releases?per_page=100" |
jq '
    sort_by(.published_at // .created_at)
    | reverse
' > releases.json

jq -r '
    .[3:]
    | .[]
    | "\(.id)|\(.tag_name)"
' releases.json |
while IFS='|' read -r ID TAG; do

    [ -z "$ID" ] && continue

    echo "Delete Release: $TAG"

    curl -fsSL \
        -X DELETE \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API}/releases/${ID}"

    echo "Delete Tag: $TAG"

    curl -s \
        -X DELETE \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API}/git/refs/tags/${TAG}" \
        || true

done

echo "======================================"
echo "Cleanup Workflow Runs"
echo "Keep newest 3"
echo "======================================"

WORKFLOW_ID="$(
    curl -fsSL \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API}/actions/workflows?per_page=100" |
    jq -r '
        .workflows[]
        | select(.path == ".github/workflows/patch.yml")
        | .id
    ' |
    head -n 1
)"

curl -fsSL \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${API}/actions/workflows/${WORKFLOW_ID}/runs?per_page=100" |
jq '
    .workflow_runs
    | sort_by(.created_at)
    | reverse
    | .[3:]
    | .[].id
' |
while read -r RUN_ID; do

    [ -z "$RUN_ID" ] && continue

    echo "Delete workflow run: $RUN_ID"

    curl -fsSL \
        -X DELETE \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API}/actions/runs/${RUN_ID}"

done

echo "======================================"
echo "Cleanup completed"
echo "======================================"
