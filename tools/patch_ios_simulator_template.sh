#!/usr/bin/env bash
# Add the missing arm64 simulator slice to Godot's iOS export template.
#
# Godot's official iOS template ships a simulator library that is x86_64 only, while its
# own xcframework metadata claims arm64 and x86_64 (godotengine/godot#118161). Apple
# silicon simulators are arm64 and Xcode 26 dropped Rosetta for simulator apps, so a
# stock template cannot produce an app that installs on a modern simulator.
#
# Upstream's answer is to delete simulator support (PR #122365) because the simulator
# cannot do Metal. That reasoning does not apply to an OpenGL project: Godot's own
# platform/ios/detect.py disables Metal and Vulkan for simulator builds and keeps
# GLES3, and this project runs the Compatibility renderer. So the slice is simply
# missing, and building it is enough.
#
# Builds the arm64 simulator library from the matching engine source, fuses it with the
# shipped x86_64 one, and repacks ios.zip in place. The original is kept as
# ios.zip.orig.
#
# Takes about 4 minutes per target on an 18-core machine.

set -euo pipefail

VERSION="${GODOT_VERSION:-4.6.1}"
SRC="${GODOT_SRC:-/tmp/godotsrc/godot}"
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/${VERSION}.stable"
ZIP="$TEMPLATES/ios.zip"

command -v xcodebuild >/dev/null || { echo "Xcode is required"; exit 1; }
python3 -c "import SCons" 2>/dev/null || { echo "SCons is required: python3 -m pip install scons"; exit 1; }
[ -f "$ZIP" ] || { echo "No iOS template at $ZIP — install export templates for $VERSION first."; exit 1; }

if [ ! -d "$SRC" ]; then
  echo "==> Cloning Godot ${VERSION}-stable into $SRC"
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 --branch "${VERSION}-stable" https://github.com/godotengine/godot.git "$SRC"
fi

for TARGET in template_debug template_release; do
  LIB="$SRC/bin/libgodot.ios.${TARGET}.arm64.simulator.a"
  if [ ! -f "$LIB" ]; then
    echo "==> Building $TARGET (arm64, simulator)"
    ( cd "$SRC" && python3 -m SCons platform=ios "target=$TARGET" arch=arm64 simulator=yes \
        -j"$(sysctl -n hw.ncpu)" )
  fi
  [ "$(lipo -archs "$LIB")" = "arm64" ] || { echo "Built library is not arm64"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$ZIP" -d "$WORK"

[ -f "$ZIP.orig" ] || cp "$ZIP" "$ZIP.orig"

for PAIR in "debug:template_debug" "release:template_release"; do
  NAME="${PAIR%%:*}"; TARGET="${PAIR##*:}"
  SLICE="$WORK/libgodot.ios.${NAME}.xcframework/ios-arm64_x86_64-simulator/libgodot.a"
  [ -f "$SLICE" ] || { echo "No simulator slice at $SLICE"; exit 1; }
  if lipo -archs "$SLICE" | grep -q arm64; then
    echo "==> $NAME simulator slice already has arm64, skipping"
    continue
  fi
  echo "==> Fusing arm64 into the $NAME simulator slice"
  lipo -create "$SLICE" "$SRC/bin/libgodot.ios.${TARGET}.arm64.simulator.a" -output "$SLICE.fat"
  mv "$SLICE.fat" "$SLICE"
  echo "    now: $(lipo -archs "$SLICE")"
done

echo "==> Repacking $ZIP"
( cd "$WORK" && zip -q -r -X "$ZIP" . )
echo "Done. Original template preserved at $ZIP.orig"
