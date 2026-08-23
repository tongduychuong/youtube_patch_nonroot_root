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

    MODULE_ID="youtube-morphe-dev-mount-root"
    MODULE_NAME="YouTube Morphe Dev Mount Root"
    ZIP_OUT="youtube_dev_root_mount_${VERSION}_Magisk.zip"

else

    MODULE_ID="youtube-morphe-mount-root"
    MODULE_NAME="YouTube Morphe Mount Root"
    ZIP_OUT="youtube_root_mount_${VERSION}_Magisk.zip"

fi

echo "======================================"
echo "Morphe Root"
echo "======================================"
echo "Version: $VERSION"
echo "Mode: $MODE"
echo "Input: $INPUT"
echo "Mount: ENABLED"
echo "GmsCore support: DISABLED"
echo "Custom branding: DISABLED"
echo "======================================"

rm -f \
    unaligned_base.apk \
    aligned_base.apk \
    base.apk

# ======================================================
# PATCH ROOT
# ======================================================

if [ "$MODE" = "dev" ]; then

    java -jar morphe-cli.jar \
        patch \
        --patches \
        https://github.com/MorpheApp/morphe-patches \
        --prerelease \
        --mount \
        --disable "GmsCore support" \
        --disable "Custom branding" \
        -o unaligned_base.apk \
        "$INPUT"

else

    java -jar morphe-cli.jar \
        patch \
        --patches \
        https://github.com/MorpheApp/morphe-patches \
        --mount \
        --disable "GmsCore support" \
        --disable "Custom branding" \
        -o unaligned_base.apk \
        "$INPUT"

fi

test -f unaligned_base.apk

# ======================================================
# REMOVE LIB
# ======================================================

echo "Removing lib/*..."

zip -d \
    unaligned_base.apk \
    "lib/*" \
    || true

# ======================================================
# ZIPALIGN
# ======================================================

echo "Zipalign..."

zipalign \
    -v \
    -f \
    4 \
    unaligned_base.apk \
    aligned_base.apk

test -f aligned_base.apk

# ======================================================
# SIGN
# ======================================================

echo "Signing..."

if [ -n "${KS_PATH:-}" ] && \
   [ -n "${KS_PASS:-}" ] && \
   [ -n "${KS_ALIAS:-}" ] && \
   [ -n "${KS_KEY_PASS:-}" ]; then

    apksigner sign \
        --ks "$KS_PATH" \
        --ks-pass "pass:${KS_PASS}" \
        --ks-key-alias "$KS_ALIAS" \
        --key-pass "pass:${KS_KEY_PASS}" \
        --out base.apk \
        aligned_base.apk

else

    echo "WARNING: Keystore secrets are not configured."

    cp -f \
        aligned_base.apk \
        base.apk

fi

test -f base.apk

# ======================================================
# CREATE MODULE
# ======================================================

rm -rf BASE_TEMPLATE

mkdir -p \
    BASE_TEMPLATE/META-INF/com/google/android \
    BASE_TEMPLATE/stock

# Patched APK
cp -f \
    base.apk \
    BASE_TEMPLATE/base.apk

# Stock APK
cp -f \
    "$INPUT" \
    BASE_TEMPLATE/stock/base.apk

# ======================================================
# BIN
# ======================================================

if [ -d "bin_temp/bin" ]; then

    echo "Copying bin_temp/bin..."

    cp -r \
        bin_temp/bin \
        BASE_TEMPLATE/

else

    echo "WARNING: bin_temp/bin not found"

fi

# ======================================================
# module.prop
# ======================================================

cat > BASE_TEMPLATE/module.prop <<EOF
id=${MODULE_ID}
name=${MODULE_NAME}
version=${VERSION}
versionCode=$(date +%Y%m%d)
author=Chuong
description=${MODULE_NAME} with Stock APK and Morphe mount.
EOF

# ======================================================
# customize.sh
# ======================================================

cat > BASE_TEMPLATE/customize.sh <<'EOF'
#!/system/bin/sh

ARCH=$(getprop ro.product.cpu.abi)

ui_print "======================================"
ui_print " YouTube Morphe Mount Root"
ui_print "======================================"
ui_print "- Architecture: $ARCH"
ui_print "- Mount: ENABLED"
ui_print "- GmsCore support: DISABLED"
ui_print "- Custom branding: DISABLED"

case "$ARCH" in

    arm64-v8a*)
        BIN_DIR="$MODPATH/bin/arm64"
        ;;

    armeabi*)
        BIN_DIR="$MODPATH/bin/arm"
        ;;

    x86_64*)
        BIN_DIR="$MODPATH/bin/x64"
        ;;

    x86*)
        BIN_DIR="$MODPATH/bin/x86"
        ;;

    *)
        BIN_DIR="$MODPATH/bin/arm64"
        ;;

esac

if [ -d "$BIN_DIR" ]; then

    ui_print "- Binary directory: $BIN_DIR"

    chmod -R +x "$BIN_DIR"

    if [ -f "$BIN_DIR/ksu_profile" ]; then

        "$BIN_DIR/ksu_profile" \
            setup \
            com.google.android.youtube \
            >/dev/null 2>&1 || true

    fi

fi

PKG_NAME="com.google.android.youtube"

TARGET_APK="$(
    pm path "$PKG_NAME" 2>/dev/null |
    head -n 1 |
    cut -d':' -f2
)"

if [ -z "$TARGET_APK" ]; then

    if [ -f "$MODPATH/stock/base.apk" ]; then

        ui_print "- YouTube not installed"
        ui_print "- Installing stock YouTube..."

        pm install -r \
            "$MODPATH/stock/base.apk" \
            >/dev/null 2>&1 || true

    fi

else

    ui_print "- YouTube found:"
    ui_print "  $TARGET_APK"

fi

set_perm_recursive \
    "$MODPATH" \
    0 \
    0 \
    0755 \
    0644

chmod -R +x \
    "$MODPATH/bin" \
    2>/dev/null || true

ui_print "======================================"
EOF

# ======================================================
# service.sh
# ======================================================

cat > BASE_TEMPLATE/service.sh <<'EOF'
#!/system/bin/sh

MODDIR="${0%/*}"

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3
done

sleep 3

PKG_NAME="com.google.android.youtube"

TARGET_APK="$(
    pm path "$PKG_NAME" 2>/dev/null |
    head -n 1 |
    cut -d':' -f2
)"

if [ -n "$TARGET_APK" ] && \
   [ -f "$MODDIR/base.apk" ]; then

    echo "Mounting YouTube Morphe..."

    mount -o bind \
        "$MODDIR/base.apk" \
        "$TARGET_APK"

    am force-stop \
        "$PKG_NAME" \
        >/dev/null 2>&1 || true

fi
EOF

chmod +x \
    BASE_TEMPLATE/customize.sh \
    BASE_TEMPLATE/service.sh

# ======================================================
# META-INF
# ======================================================

cat > BASE_TEMPLATE/META-INF/com/google/android/update-binary <<EOF
#!/sbin/sh

UMASK=022

ZIPFILE="\$3"

MODPATH="/data/adb/modules/${MODULE_ID}"

mkdir -p "\$MODPATH"

unzip -o \
    "\$ZIPFILE" \
    -x "META-INF/*" \
    -d "\$MODPATH"

set_perm_recursive \
    "\$MODPATH" \
    0 \
    0 \
    0755 \
    0644
EOF

chmod +x \
    BASE_TEMPLATE/META-INF/com/google/android/update-binary

echo "# MAGISK INSTALLER" \
    > BASE_TEMPLATE/META-INF/com/google/android/updater-script

# ======================================================
# ZIP
# Same compression method
# ======================================================

cd BASE_TEMPLATE

7z a \
    -tzip \
    -mx=9 \
    -mm=Deflate \
    -mfb=258 \
    "../${ZIP_OUT}" \
    ./*

cd ..

test -f "${ZIP_OUT}"

echo "======================================"
echo "ROOT SUCCESS"
echo "======================================"

ls -lh "${ZIP_OUT}"

7z l "${ZIP_OUT}"
