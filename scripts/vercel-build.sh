#!/bin/sh
# Flutter web only → build/web (Vercel outputDirectory). API is api/server.js + rewrites.
# Do not default API_BASE_URL to $VERCEL_URL: that hostname is unique per deployment, so
# production / branch aliases would cross-call another subdomain and often fail in the browser.
# Omit dart-define to use same-origin (Uri.base.origin) on web; override with Vercel env API_BASE_URL if needed.
set -e
if [ -x flutter/bin/flutter ]; then
  F=flutter/bin/flutter
else
  F=flutter
fi
$F pub get
if [ -n "${API_BASE_URL:-}" ]; then
  $F build web --release --dart-define="API_BASE_URL=$API_BASE_URL"
else
  $F build web --release
fi
