#!/bin/zsh
set -euo pipefail

CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin
SUPPORT="$HOME/Library/Application Support/MedianXL-macOS"
BOTTLE=MedianXL APP_NAME="Median XL" YES=0
while (( $# )); do
  case $1 in
    --bottle) BOTTLE=${2:?}; shift 2 ;;
    --app) APP_NAME=${2:?}; shift 2 ;;
    --yes) YES=1; shift ;;
    *) print -r -- "Usage: ./uninstall.sh [--bottle NAME] [--app NAME] [--yes]"; exit 1 ;;
  esac
done

PREFIX="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
print -r -- "This deletes the CrossOver bottle '$BOTTLE' (game files and offline characters inside it)"
print -r -- "and ~/Applications/$APP_NAME.app. Online (realm) characters are stored on the server and are not affected."
if (( ! YES )); then
  read -q "?Continue? [y/N] " || { print; exit 1; }
  print
fi

pkill -f '^C:.Games.median-xl.Game.exe' || true
[[ -d $PREFIX ]] && "$CX/cxbottle" --bottle "$BOTTLE" --delete --force >/dev/null
rm -rf "$HOME/Applications/$APP_NAME.app"
rm -f "$SUPPORT/$BOTTLE".*(N)
if [[ -z $(ls -A "$SUPPORT" 2>/dev/null | grep -vE '^(launcher\.sh|mxl-update\.py)$') ]]; then
  rm -rf "$SUPPORT"
fi
print -r -- "Removed."
