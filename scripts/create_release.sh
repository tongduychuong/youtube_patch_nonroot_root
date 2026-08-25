#!/usr/bin/env bash
set -e
TYPE="$1"
VERSION="$2"
MORPHE_REPO="${MORPHE_REPO:-MorpheApp/morphe-patches}"
MICROG_URL="${MICROG_URL:-https://github.com/MorpheApp/MicroG-RE/releases}"
test -n "$MORPHE_VERSION"

if [ "$TYPE" = "stable" ]; then
  RELEASE_TAG="youtube-morphe-${MORPHE_VERSION}-${VERSION}"
  TITLE="YouTube Morphe Stable ${VERSION}"
else
  RELEASE_TAG="youtube-morphe-${MORPHE_VERSION}-${VERSION}-dev"
  TITLE="YouTube Morphe Dev ${VERSION}"
fi

MORPHE_URL="https://github.com/${MORPHE_REPO}/releases/tag/${MORPHE_VERSION}"

cat > release_notes.md <<EOF
# YouTube Morphe

## Morphe Patch

**${MORPHE_VERSION}**

[Morphe Patch ${MORPHE_VERSION} Changelog](${MORPHE_URL})

## MicroG

MicroG is required for **YouTube Non-root**.

[Download MicroG for YouTube Non-root](${MICROG_URL})

## YouTube

- Version: ${VERSION}
- Type: ${TYPE}

## Build

- Non-root
- Root Magisk
EOF

gh release create "$RELEASE_TAG" --title "$TITLE" --notes-file release_notes.md --target "${GITHUB_SHA}"

find . -type f \( -name "*.apk" -o -name "*.zip" \) ! -path "./.git/*" -print0 |
while IFS= read -r -d '' FILE; do
  gh release upload "$RELEASE_TAG" "$FILE"
done
