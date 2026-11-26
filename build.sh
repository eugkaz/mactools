#!/bin/bash
# Build and install Shifty, NotchDeck, Awake, Orbit and Reel into /Applications
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/build"
swiftc -O "$ROOT/make_icon.swift" -o "$ROOT/build/make_icon" 2>/dev/null

build() {
  local name=$1 icon=$2
  local app="$ROOT/build/$name.app"
  echo "▶ $name"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  swiftc -O -swift-version 5 -target arm64-apple-macos15.0 "$ROOT/$name"/Sources/*.swift "$ROOT"/Shared/*.swift -o "$app/Contents/MacOS/$name"
  cp "$ROOT/$name/Info.plist" "$app/Contents/Info.plist"
  # Мост к системному «Сейчас играет» (грузится в /usr/bin/perl)
  if [ -d "$ROOT/$name/Bridge" ]; then
    clang -dynamiclib -fobjc-arc -O2 -arch arm64 -mmacosx-version-min=15.0 -framework Foundation -framework AppKit \
      "$ROOT/$name"/Bridge/*.m -o "$app/Contents/Resources/libnp.dylib"
    codesign --force -s - "$app/Contents/Resources/libnp.dylib"
    cp "$ROOT/$name"/Bridge/*.pl "$app/Contents/Resources/"
  fi
  "$ROOT/build/make_icon" "$icon" "$app/Contents/Resources/AppIcon.icns"
  # Стабильное требование подписи: разрешения macOS (запись экрана и т.п.) не слетают после пересборки
  local bid; bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
  codesign --force --deep -s - -r="designated => identifier \"$bid\"" "$app"
  pkill -x "$name" 2>/dev/null || true
  rm -rf "/Applications/$name.app"
  cp -R "$app" "/Applications/$name.app"
  sleep 0.5
  open "/Applications/$name.app" 2>/dev/null || { sleep 1.5; open "/Applications/$name.app" || true; }
}

# ./build.sh            — все приложения
# ./build.sh NotchDeck  — только указанные
ARGS="$*"
[ -z "$ARGS" ] || [[ " $ARGS " == *" Shifty "* ]] && build Shifty shifty
[ -z "$ARGS" ] || [[ " $ARGS " == *" NotchDeck "* ]] && build NotchDeck deck
[ -z "$ARGS" ] || [[ " $ARGS " == *" Awake "* ]] && build Awake awake
[ -z "$ARGS" ] || [[ " $ARGS " == *" Orbit "* ]] && build Orbit orbit
[ -z "$ARGS" ] || [[ " $ARGS " == *" Reel "* ]] && build Reel reel
echo "✅ Готово"
