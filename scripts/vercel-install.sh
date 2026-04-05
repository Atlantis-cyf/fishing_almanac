#!/bin/sh
# Vercel install step: Node deps + Flutter SDK (not on default build image).
# See https://vercel.com/docs/getting-started-with-vercel (Node 18+, install then build).
set -e
npm install
if [ ! -x flutter/bin/flutter ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter
fi
flutter/bin/flutter config --no-analytics
flutter/bin/flutter precache --web
