#!/usr/bin/env bash
set -e

BUILD_MODE="${1:-stable}"
PATCHES_VER="${PATCH_TAG##*-}"

cat << 'EOF' > options.json
[
  {
    "patchName": "GmsCore support",
    "options": {
      "packageName": "com.google.tdc.android.youtube"
    }
  }
]
EOF

if [ "$BUILD_MODE" == "dev" ]; then
  MODULE_ID="youtube-morphe-dev-mount-root"
  MODULE_NAME="YouTube Morphe Dev (Mount Root)"
  APK_OUT="youtube_dev_${YT_VERSION}.apk"
  ROOT_APK_OUT="youtube_dev_root_${YT_VERSION}.apk"
  ZIP_OUT="youtube_dev_root_mount_${YT_VERSION}_Magisk.zip"
else
  MODULE_ID="youtube-morphe-mount-root"
  MODULE_NAME="YouTube Morphe (Mount Root)"
  APK_OUT="youtube_${YT_VERSION}.apk"
  ROOT_APK_OUT="youtube_root_${YT_VERSION}.apk"
  ZIP_OUT="youtube_root_mount_${YT_VERSION}_Magisk.zip"
fi

java -jar morphe-cli.jar patch -p patches.mpp \
  --options options.json \
  -O "GmsCore support:packageName=com.google.tdc.android.youtube" \
  -d "Custom branding" \
  -e "" \
  --out "$APK_OUT" youtube.apk

java -jar morphe-cli.jar patch -p patches.mpp --mount -d "GmsCore support" -d "Custom branding" -e "" --out "unaligned_base.apk" youtube.apk
zip -d unaligned_base.apk "lib/*" || true

zipalign -v -f 4 unaligned_base.apk aligned_base.apk
apksigner sign --ks "$KS_PATH" --ks-pass pass:"$KS_PASS" --ks-key-alias "$KS_ALIAS" --key-pass pass:"$KS_KEY_PASS" --out base.apk aligned_base.apk

BASE_TEMPLATE=$(mktemp -d -p "/tmp")
mkdir -p "$BASE_TEMPLATE/META-INF/com/google/android" "$BASE_TEMPLATE/stock"

cp -f base.apk "$BASE_TEMPLATE/base.apk"
cp -f youtube.apk "$BASE_TEMPLATE/stock/base.apk"

if [ -d "bin_temp/bin" ]; then
  cp -r bin_temp/bin "$BASE_TEMPLATE/"
fi

cat << EOF > "$BASE_TEMPLATE/module.prop"
id=${MODULE_ID}
name=${MODULE_NAME}
version=${YT_VERSION} (patches ${PATCHES_VER})
versionCode=$(date +%Y%m%d)
author=j-hc & Morphe Builder
description=${MODULE_NAME} Module with Stock APK & j-hc binaries.
EOF

cat << 'EOF' > "$BASE_TEMPLATE/customize.sh"
#!/system/bin/sh
ARCH=$(getprop ro.product.cpu.abi)
ui_print "- Device Architecture: $ARCH"

case "$ARCH" in
  arm64-v8a*) BIN_DIR="$MODPATH/bin/arm64" ;;
  armeabi*) BIN_DIR="$MODPATH/bin/arm" ;;
  x86_64*) BIN_DIR="$MODPATH/bin/x64" ;;
  x86*) BIN_DIR="$MODPATH/bin/x86" ;;
  *) BIN_DIR="$MODPATH/bin/arm64" ;;
esac

if [ -d "$BIN_DIR" ]; then
  ui_print "- Setting up j-hc binaries from $BIN_DIR..."
  chmod -R +x "$BIN_DIR"
  if [ -f "$BIN_DIR/ksu_profile" ]; then
    "$BIN_DIR/ksu_profile" setup com.google.android.youtube >/dev/null 2>&1 || true
  fi
fi

PKG_NAME="com.google.android.youtube"
TARGET_APK=$(pm path $PKG_NAME | head -n 1 | cut -d':' -f2)

if [ -z "$TARGET_APK" ]; then
  if [ -f "$MODPATH/stock/base.apk" ]; then
    ui_print "- Installing stock YouTube APK..."
    pm install -r "$MODPATH/stock/base.apk" >/dev/null 2>&1
  fi
else
  ui_print "- Stock YouTube found at: $TARGET_APK"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
chmod -R +x "$MODPATH/bin" 2>/dev/null || true
EOF

cat << 'EOF' > "$BASE_TEMPLATE/service.sh"
#!/system/bin/sh
MODDIR=${0%/*}

while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 3
done

PKG_NAME="com.google.android.youtube"
TARGET_APK=$(pm path $PKG_NAME | head -n 1 | cut -d':' -f2)

if [ -n "$TARGET_APK" ] && [ -f "$MODDIR/base.apk" ]; then
  mount -o bind "$MODDIR/base.apk" "$TARGET_APK"
  am force-stop $PKG_NAME >/dev/null 2>&1
fi
EOF
chmod +x "$BASE_TEMPLATE/service.sh"

cat << EOF > "$BASE_TEMPLATE/META-INF/com/google/android/update-binary"
#!/sbin/sh
UMASK=022
ZIPFILE="\$3"
MODPATH="/data/adb/modules/${MODULE_ID}"
mkdir -p "\$MODPATH"
unzip -o "\$ZIPFILE" -x "META-INF/*" -d "\$MODPATH"
set_perm_recursive "\$MODPATH" 0 0 0755 0644
EOF

echo "# MAGISK INSTALLER" > "$BASE_TEMPLATE/META-INF/com/google/android/updater-script"

cd "$BASE_TEMPLATE"
7z a -tzip -mx=9 -mm=Deflate -mfb=258 "$OLDPWD/$ZIP_OUT" ./*
cd "$OLDPWD"

rm -rf "$BASE_TEMPLATE" bin_temp *.jks unaligned_base.apk aligned_base.apk base.apk options.json
