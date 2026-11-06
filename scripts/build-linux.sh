#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Linux ]] || { echo 'Run this script in WSL2 / Linux.' >&2; exit 1; }
command -v swift >/dev/null
/usr/bin/python3 -c 'from PIL import Image' || { echo 'Install python3-pil first.' >&2; exit 1; }
swift build -c release --jobs "${DAFEIYU_BUILD_JOBS:-2}"
APP="$PWD/dist/dafeiyu-linux"
mkdir -p "$APP/Resources"
staged=$(mktemp "$APP/.dafeiyu.XXXXXX")
trap 'rm -f -- "$staged"' EXIT
install -m 755 "$(swift build -c release --show-bin-path)/WeChatAIBot" "$staged"
cp -R Resources/QQControl Resources/QQStickers Resources/Linux Resources/SocialControl Resources/SocialBrowser "$APP/Resources/"
mv -f -- "$staged" "$APP/dafeiyu"
echo "Built: $APP/dafeiyu"
