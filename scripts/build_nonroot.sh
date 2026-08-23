#!/usr/bin/env bash

set -e

VERSION="$1"
INPUT="$2"
MODE="$3"

if [ -z "$VERSION" ]; then
    echo "ERROR: VERSION is missing"
    exit 1
fi

if [ -z "$INPUT" ]; then
    echo "ERROR: INPUT is missing"
    exit 1
fi

if [ ! -f "$INPUT" ]; then
    echo "ERROR: APK not found:"
    echo "$INPUT"
    exit 1
fi

if [ "$MODE" = "dev" ]; then

    OUTPUT="youtube-morphe-dev-${VERSION}.apk"

else

    OUTPUT="youtube-morphe-${VERSION}.apk"

fi

echo "======================================"
echo "Morphe Non Root"
echo "======================================"
echo "Version: $VERSION"
echo "Mode: $MODE"
echo "Input: $INPUT"
echo "Output: $OUTPUT"
echo "Mount: DISABLED"
echo "GmsCore support: ENABLED"
echo "Custom branding: DISABLED"
echo "======================================"

if [ "$MODE" = "dev" ]; then

    java -jar morphe-cli.jar \
        patch \
        --patches \
        https://github.com/MorpheApp/morphe-patches \
        --prerelease \
        --disable "Custom branding" \
        -o "$OUTPUT" \
        "$INPUT"

else

    java -jar morphe-cli.jar \
        patch \
        --patches \
        https://github.com/MorpheApp/morphe-patches \
        --disable "Custom branding" \
        -o "$OUTPUT" \
        "$INPUT"

fi

if [ ! -f "$OUTPUT" ]; then
    echo "ERROR: Non-root APK was not created"
    exit 1
fi

echo "======================================"
echo "NON ROOT SUCCESS"
echo "======================================"

ls -lh "$OUTPUT"
