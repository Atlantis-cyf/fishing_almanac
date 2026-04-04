#!/bin/sh
# For local / full Linux CI: `npm run build` → Flutter web.
#
# Tencent EdgeOne Pages builders block chmod(2); `flutter pub get` still fails there.
# Use `.github/workflows/deploy-edgeone-pages.yml` (GitHub Actions) + `npx edgeone pages deploy`.
# In EdgeOne console, turn off Git-connected auto build if it keeps running this script.
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CI=true
export HOME="${HOME:-$ROOT/.ci-home}"
export TMPDIR="${TMPDIR:-$ROOT/.ci-tmp}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$HOME" "$TMPDIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

# Prebuilt SDK avoids git-clone + "pub upgrade" on flutter_tools (fewer chmods); still need pub for app deps.
FLUTTER_VER="${FLUTTER_LINUX_VER:-3.41.6}"
TAR_NAME="flutter_linux_${FLUTTER_VER}-stable.tar.xz"
TAR_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${TAR_NAME}"

if [ ! -f flutter-sdk/bin/flutter ]; then
  rm -rf flutter-sdk flutter
  curl -fsSL "$TAR_URL" -o "$ROOT/$TAR_NAME"
  tar xf "$ROOT/$TAR_NAME" -C "$ROOT"
  rm -f "$ROOT/$TAR_NAME"
  mv "$ROOT/flutter" "$ROOT/flutter-sdk"
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
