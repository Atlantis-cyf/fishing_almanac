#!/bin/sh
# EdgeOne Pages runs `npm run build` for static sites; this script builds Flutter web.
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# EdgeOne default HOME is under /dev/shm where pub cannot chmod extracted packages.
# Keep HOME, caches, and temp inside the repo checkout so Dart/Flutter pub can set +x.
export CI=true
export HOME="$ROOT/.ci-home"
export TMPDIR="$ROOT/.ci-tmp"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$HOME" "$TMPDIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

if [ ! -d flutter-sdk ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter-sdk
fi
export PATH="$ROOT/flutter-sdk/bin:$PATH"

flutter config --no-analytics
flutter precache --web
flutter pub get

if [ -n "${API_BASE_URL:-}" ]; then
  flutter build web --release --dart-define="API_BASE_URL=${API_BASE_URL}"
else
  flutter build web --release
fi
