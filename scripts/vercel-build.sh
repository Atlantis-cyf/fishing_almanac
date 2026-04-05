#!/bin/sh
# Flutter web only → build/web (Vercel outputDirectory). API is api/server.js + rewrites.
set -e
export API_BASE_URL="${API_BASE_URL:-https://${VERCEL_URL}}"
if [ -x flutter/bin/flutter ]; then
  F=flutter/bin/flutter
else
  F=flutter
fi
$F pub get
$F build web --release --dart-define="API_BASE_URL=$API_BASE_URL"
