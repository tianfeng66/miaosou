#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/秒搜.app"

if [[ ! -x "$APP/Contents/MacOS/Miaosou" ]]; then
  echo "正在编译秒搜…"
  /bin/bash "$DIR/build.sh"
fi

open "$APP"
