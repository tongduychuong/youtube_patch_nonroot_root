#!/usr/bin/env bash
set -e

TYPE="$1"

REPO="${GITHUB_REPOSITORY}"
MORPHE_REPO="${MORPHE_REPO:-MorpheApp/morphe-patches}"

if [ "$TYPE" = "stable" ]; then

    VERSION="$(tr -d '\r\n' < version.txt | xargs)"

    MORPHE_VERSION="$(
        curl -fsSL \
          "https://api.github.com/repos/${MORPHE_REPO}/releases/latest" |
        jq -r '.tag_name'
    )

else

    VERSION="$(tr -d '\r\n' < version_dev.txt | xargs)"

    MORPHE_VERSION="$(
        curl -fsSL \
          "https://api.github.com/repos/${MORPHE_REPO}/releases?per_page=100" |
        jq -r '
          [
            .[]
            | select(.prerelease == true)
          ]
          | sort_by(.published_at // .created_at)
          | reverse
          | .[0]
          | .tag_name
        '
    )

fi

echo "YouTube : $VERSION"
echo "Morphe  : $MORPHE_VERSION"

if [ "${GITHUB_EVENT_NAME}" = "workflow_dispatch" ]; then

    echo "Manual run → FORCE BUILD"

    echo "BUILD=true" >> "$GITHUB_ENV"
    export BUILD=true

    exit 0

fi

RELEASES="$(
    gh api \
      --paginate \
      "/repos/${REPO}/releases?per_page=100"
)"

FOUND="$(
    echo "$RELEASES" |
    jq -r '
      .[]
      | .body // ""
    ' |
    grep -F \
      "Morphe Patch ${MORPHE_VERSION} Changelog" |
    head -n 1 || true
)"

if [ -n "$FOUND" ]; then

    echo "Patch already built."
    echo "BUILD=false" >> "$GITHUB_ENV"

else

    echo "New patch."
    echo "BUILD=true" >> "$GITHUB_ENV"

fi

echo "MORPHE_VERSION=$MORPHE_VERSION" >> "$GITHUB_ENV"
echo "VERSION=$VERSION" >> "$GITHUB_ENV"
