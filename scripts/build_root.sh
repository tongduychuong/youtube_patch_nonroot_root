#!/usr/bin/env bash
set -e

VERSION="$1"
INPUT="$2"
MODE="$3"

# ============================================================
# CHECK ARGUMENTS
# ============================================================

if [ -z "$VERSION" ]; then
    echo "ERROR: VERSION is missing"
    exit 1
fi

if [ -z "$INPUT" ]; then
    echo "ERROR: INPUT is missing"
    exit 1
fi

if [ ! -f "$INPUT" ]; then
    echo "ERROR: YouTube APK not found:"
    echo "$INPUT"
    exit 1
fi

# ============================================================
# CONFIG
# ============================================================

MORPHE_PATCHES="${MORPHE_PATCHES:-https://github.com/MorpheApp/morphe-patches}"

KEY_DIR="${GITHUB_WORKSPACE:-$(pwd)}/keys"

KEYSTORE="${RUNNER_TEMP:-/tmp}/youtube-release.p12"

KEYSTORE_ENC="$KEY_DIR/keystore.enc"

KEY_ALIAS="${KEY_ALIAS:-youtube}"

STORE_PASSWORD="${STORE_PASSWORD:-youtube-release}"

KEY_PASSWORD="${KEY_PASSWORD:-youtube-release}"

# ============================================================
# MODE
# ============================================================

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
echo " YouTube Morphe ROOT"
echo "======================================"
echo "Version              : $VERSION"
echo "Mode                 : $MODE"
echo "Input                : $INPUT"
echo "Mount                : ENABLED"
echo "GmsCore support      : DISABLED"
echo "Custom branding      : DISABLED"
echo "Keystore             : $KEYSTORE_ENC"
echo "======================================"

# ============================================================
# CHECK ENCRYPTION KEY
# ============================================================

if [ -z "${KEYSTORE_ENCRYPTION_KEY:-}" ]; then
    echo "ERROR: KEYSTORE_ENCRYPTION_KEY is not configured"
    echo
    echo "Add this GitHub Secret:"
    echo "KEYSTORE_ENCRYPTION_KEY"
    exit 1
fi

# ============================================================
# CREATE KEY DIRECTORY
# ============================================================

mkdir -p "$KEY_DIR"

# ============================================================
# RESTORE EXISTING KEYSTORE
# ============================================================

if [ -f "$KEYSTORE_ENC" ]; then

    echo "======================================"
    echo "Restoring encrypted keystore..."
    echo "======================================"

    rm -f "$KEYSTORE"

    openssl enc \
        -d \
        -aes-256-cbc \
        -pbkdf2 \
        -iter 200000 \
        -in "$KEYSTORE_ENC" \
        -out "$KEYSTORE" \
        -pass "pass:${KEYSTORE_ENCRYPTION_KEY}"

    chmod 600 "$KEYSTORE"

    if [ ! -s "$KEYSTORE" ]; then
        echo "ERROR: Failed to restore keystore"
        exit 1
    fi

    echo "Existing keystore restored."

# ============================================================
# CREATE NEW KEYSTORE
# ============================================================

else

    echo "======================================"
    echo "Creating new keystore..."
    echo "======================================"

    rm -f "$KEYSTORE"

    keytool \
        -genkeypair \
        -v \
        -keystore "$KEYSTORE" \
        -storetype PKCS12 \
        -alias "$KEY_ALIAS" \
        -keyalg RSA \
        -keysize 4096 \
        -validity 10000 \
        -storepass "$STORE_PASSWORD" \
        -keypass "$KEY_PASSWORD" \
        -dname \
        "CN=YouTube Morphe, OU=Morphe, O=Chuong, L=Ho Chi Minh, ST=HCM, C=VN"

    chmod 600 "$KEYSTORE"

    test -s "$KEYSTORE"

    echo "Encrypting keystore..."

    openssl enc \
        -aes-256-cbc \
        -salt \
        -pbkdf2 \
        -iter 200000 \
        -in "$KEYSTORE" \
        -out "$KEYSTORE_ENC" \
        -pass "pass:${KEYSTORE_ENCRYPTION_KEY}"

    chmod 600 "$KEYSTORE_ENC"

    echo "Encrypted keystore created:"
    ls -lh "$KEYSTORE_ENC"

fi

# ============================================================
# VERIFY KEYSTORE
# ============================================================

echo "======================================"
echo "Verifying keystore..."
echo "======================================"

keytool \
    -list \
    -keystore "$KEYSTORE" \
    -storepass "$STORE_PASSWORD" \
    -alias "$KEY_ALIAS" \
    >/dev/null

echo "Keystore OK."

# ============================================================
# PATCH ROOT
# ============================================================

rm -f \
    unaligned_base.apk \
    aligned_base.apk \
    base.apk

echo "======================================"
echo "Patching Root APK..."
echo "======================================"

if [ "$MODE" = "dev" ]; then

    java -jar morphe-cli.jar \
        patch \
        --patches "$MORPHE_PATCHES" \
        --prerelease \
        --mount \
        --disable "GmsCore support" \
        --disable "Custom branding" \
        -o unaligned_base.apk \
        "$INPUT"

else

    java -jar morphe-cli.jar \
        patch \
        --patches "$MORPHE_PATCHES" \
        --mount \
        --disable "GmsCore support" \
        --disable "Custom branding" \
        -o unaligned_base.apk \
        "$INPUT"

fi

test -f unaligned_base.apk

# ============================================================
# REMOVE LIB
# ============================================================

echo "======================================"
echo "Removing lib/*..."
echo "======================================"

zip -d \
    unaligned_base.apk \
    "lib/*" \
    || true

# ============================================================
# ZIPALIGN
# ============================================================

echo "======================================"
echo "Zipalign..."
echo "======================================"

zipalign \
    -v \
    -f \
    4 \
    unaligned_base.apk \
    aligned_base.apk

test -f aligned_base.apk

# ============================================================
# SIGN
# ============================================================

echo "======================================"
echo "Signing Root APK..."
echo "======================================"

apksigner sign \
    --ks "$KEYSTORE" \
    --ks-pass "pass:${STORE_PASSWORD}" \
    --ks-key-alias "$KEY_ALIAS" \
    --key-pass "pass:${KEY_PASSWORD}" \
    --out base.apk \
    aligned_base.apk

test -f base.apk

# Verify signature

echo "Verifying APK signature..."

apksigner verify \
    --verbose \
    base.apk

echo "Root APK signed successfully."

# ============================================================
# CREATE MODULE
# ============================================================

echo "======================================"
echo "Creating Magisk module..."
echo "======================================"

rm -rf BASE_TEMPLATE

mkdir -p \
    BASE_TEMPLATE/META-INF/com/google/android \
    BASE_TEMPLATE/stock

# ============================================================
# PATCHED APK
# ============================================================

cp -f \
    base.apk \
    BASE_TEMPLATE/base.apk

# ============================================================
# STOCK APK
# ============================================================

cp -f \
    "$INPUT" \
    BASE_TEMPLATE/stock/base.apk

# ============================================================
# BIN
# Same approach as build_module(2).sh
# ============================================================

if [ -d "bin_temp/bin" ]; then

    echo "Copying bin_temp/bin..."

    cp -r \
        bin_temp/bin \
        BASE_TEMPLATE/

else

    echo "WARNING: bin_temp/bin not found"

fi

# ============================================================
# MODULE.PROP
# ============================================================

cat > BASE_TEMPLATE/module.prop <<EOF
id=${MODULE_ID}
name=${MODULE_NAME}
version=${VERSION}
versionCode=$(date +%Y%m%d%H%M)
author=Chuong
description=${MODULE_NAME} - Morphe Mount Root
EOF

# ============================================================
# CUSTOMIZE.SH
# ============================================================

cat > BASE_TEMPLATE/customize.sh <<'EOF'
#!/system/bin/sh

ui_print "======================================"
ui_print " YouTube Morphe Mount Root"
ui_print "======================================"

ui_print "- Mount: ENABLED"
ui_print "- GmsCore support: DISABLED"
ui_print "- Custom branding: DISABLED"

ARCH="$(getprop ro.product.cpu.abi)"

ui_print "- Architecture: $ARCH"

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

    ui_print "- Binary: $BIN_DIR"

    chmod -R +x "$BIN_DIR"

    if [ -f "$BIN_DIR/ksu_profile" ]; then

        "$BIN_DIR/ksu_profile" \
            setup \
            com.google.android.youtube \
            >/dev/null 2>&1 || true

    fi

else

    ui_print "- No matching binary directory"

fi

PKG_NAME="com.google.android.youtube"

TARGET_APK="$(
    pm path "$PKG_NAME" 2>/dev/null |
    head -n 1 |
    cut -d':' -f2
)"

if [ -z "$TARGET_APK" ]; then

    ui_print "- YouTube is not installed"

    if [ -f "$MODPATH/stock/base.apk" ]; then

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

if [ -d "$MODPATH/bin" ]; then

    chmod -R +x \
        "$MODPATH/bin" \
        2>/dev/null || true

fi

ui_print "======================================"
ui_print " Module prepared"
ui_print "======================================"
EOF

# ============================================================
# SERVICE.SH
# ============================================================

cat > BASE_TEMPLATE/service.sh <<'EOF'
#!/system/bin/sh

MODDIR="${0%/*}"

PKG_NAME="com.google.android.youtube"

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3
done

sleep 3

TARGET_APK="$(
    pm path "$PKG_NAME" 2>/dev/null |
    head -n 1 |
    cut -d':' -f2
)

if [ -z "$TARGET_APK" ]; then
    exit 0
fi

if [ ! -f "$MODDIR/base.apk" ]; then
    exit 0
fi

echo "YouTube Morphe: mounting patched APK"

mount -o bind \
    "$MODDIR/base.apk" \
    "$TARGET_APK"

RESULT=$?

if [ "$RESULT" -ne 0 ]; then
    echo "YouTube Morphe: mount failed"
    exit 1
fi

echo "YouTube Morphe: mount successful"

am force-stop \
    "$PKG_NAME" \
    >/dev/null 2>&1 || true
EOF

chmod +x \
    BASE_TEMPLATE/customize.sh \
    BASE_TEMPLATE/service.sh

# ============================================================
# META-INF
# ============================================================

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

exit 0
EOF

chmod +x \
    BASE_TEMPLATE/META-INF/com/google/android/update-binary

cat > BASE_TEMPLATE/META-INF/com/google/android/updater-script <<'EOF'
#MAGISK
EOF

# ============================================================
# SHOW MODULE
# ============================================================

echo "======================================"
echo "Module contents:"
echo "======================================"

find BASE_TEMPLATE \
    -type f \
    -printf "%p %s bytes\n" |
    sort

# ============================================================
# CREATE ZIP
# Same method as build_module(2).sh
# ============================================================

echo "======================================"
echo "Creating Magisk ZIP..."
echo "======================================"

cd BASE_TEMPLATE

7z a \
    -tzip \
    -mx=9 \
    -mm=Deflate \
    -mfb=258 \
    "../${ZIP_OUT}" \
    ./*

cd ..

# ============================================================
# VERIFY ZIP
# ============================================================

if [ ! -f "$ZIP_OUT" ]; then
    echo "ERROR: Magisk ZIP was not created"
    exit 1
fi

echo "======================================"
echo "ROOT BUILD SUCCESS"
echo "======================================"

ls -lh \
    "$ZIP_OUT" \
    base.apk \
    "$KEYSTORE_ENC"

echo "======================================"
echo "Magisk ZIP contents:"
echo "======================================"

7z l "$ZIP_OUT"

# ============================================================
# CLEAN PRIVATE KEY
# ============================================================

rm -f "$KEYSTORE"

echo "======================================"
echo "Encrypted keystore:"
echo "$KEYSTORE_ENC"
echo "======================================"

echo "$ZIP_OUT"
