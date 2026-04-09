#!/bin/sh
# Flutter web only → build/web (Vercel outputDirectory). API is api/server.js + rewrites.
# Do not default API_BASE_URL to $VERCEL_URL: that hostname is unique per deployment, so
# production / branch aliases would cross-call another subdomain and often fail in the browser.
# Omit dart-define to use same-origin (Uri.base.origin) on web; override with Vercel env API_BASE_URL if needed.
#
# Two Vercel projects can share this script (both use repo-root vercel.json, Root Directory ./):
#   - User app: do NOT set FLUTTER_WEB_TARGET → default entry lib/main.dart (same as before this flag existed).
#   - Admin app: set Vercel env FLUTTER_WEB_TARGET=admin → -t lib/admin/main_admin.dart
# See docs/ADMIN_SPLIT_DEPLOY_CHECKLIST.md
set -e
if [ -x flutter/bin/flutter ]; then
  F=flutter/bin/flutter
else
  F=flutter
fi
$F pub get
# Match full-stack behavior: fish feed & species ID must hit the BFF (not browser-only LocalCatchRepository).
WEB_DEFINES='--dart-define=USE_REMOTE_CATCH_REPOSITORY=true --dart-define=USE_REMOTE_SPECIES_IDENTIFICATION=true'
if [ -n "${API_BASE_URL:-}" ]; then
  WEB_DEFINES="$WEB_DEFINES --dart-define=API_BASE_URL=$API_BASE_URL"
fi

TARGET_ARGS=""
case "${FLUTTER_WEB_TARGET:-}" in
  admin|Admin|ADMIN)
    TARGET_ARGS="-t lib/admin/main_admin.dart"
    ;;
esac

$F build web --release $TARGET_ARGS $WEB_DEFINES
