#!/bin/zsh
set -euo pipefail
setopt extendedglob

REPO=${0:A:h}
CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin
SUPPORT="$HOME/Library/Application Support/MedianXL-macOS"
D2_MPQS=(d2data.mpq d2exp.mpq d2char.mpq d2music.mpq d2sfx.mpq d2speech.mpq d2video.mpq d2xmusic.mpq d2xtalk.mpq d2xvideo.mpq)
D2GL_MXL_URL=https://github.com/GavinK88/d2gl-mxl-1.0/releases/download/1.0.5/Release.zip
D2GL_MXL_SHA256=10a8c36b49db5cc9c9027f53f3a59f124ee3406041daeae5f38a74ab482e99ed
D2GL_MXL_FILES=(glide3x.dll ddraw.dll d2gl.mpq)

die() { print -r -- "error: $*" >&2; exit 1; }
step() { print -r -- "==> $*"; }
usage() {
  print -r -- "Usage: ./install.sh [<folder with Diablo II MPQs>] [--d2gl-mxl] [--bottle NAME] [--app NAME]"
  print -r -- "  <folder>     Diablo II: Lord of Destruction folder containing d2data.mpq, d2exp.mpq, ..."
  print -r -- "               (required on the first install)"
  print -r -- "  --d2gl-mxl   use GavinK88's D2GL-MXL 1.0.5 instead of the official MXL graphics driver"
  print -r -- "  --bottle     CrossOver bottle name (default: MedianXL)"
  print -r -- "  --app        launcher app name in ~/Applications (default: Median XL)"
  exit 1
}

SRC="" BOTTLE=MedianXL APP_NAME="Median XL" D2GL_MXL=0
while (( $# )); do
  case $1 in
    --bottle) BOTTLE=${2:?}; shift 2 ;;
    --app) APP_NAME=${2:?}; shift 2 ;;
    --d2gl-mxl) D2GL_MXL=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [[ -z $SRC ]] || usage; SRC=$1; shift ;;
  esac
done

PREFIX="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
GAME_DIR="$PREFIX/drive_c/Games/median-xl"
KEEP_FILE="$SUPPORT/$BOTTLE.keep"

[[ -x $CX/wine ]] || die "CrossOver not found in /Applications. Install it from https://www.codeweavers.com/crossover and open it once."
/usr/bin/python3 -c 'import sys' 2>/dev/null || die "/usr/bin/python3 is missing. Run 'xcode-select --install' and try again."
if pgrep -f '^C:.Games.median-xl.Game.exe' >/dev/null; then die "Median XL is running. Quit the game first."; fi

missing=()
for name in $D2_MPQS; do
  [[ -f $GAME_DIR/$name ]] && continue
  [[ -n $SRC ]] || { missing+=$name; continue; }
  found=( "$SRC"/(#i)$name(N.) )
  (( $#found )) || missing+=$name
done
(( $#missing == 0 )) || die "these Diablo II files were not found${SRC:+ in '$SRC'}: ${missing[*]}"

if [[ ! -d $PREFIX ]]; then
  step "Creating CrossOver bottle '$BOTTLE'"
  "$CX/cxbottle" --create --bottle "$BOTTLE" --template win10_64 --description "Median XL" >/dev/null
fi
/usr/bin/python3 -I - "$PREFIX/cxbottle.conf" <<'EOF'
import sys
path = sys.argv[1]
conf = open(path, encoding="utf-8").read()
if '"WINEMSYNC"' not in conf:
    conf = conf.replace("[EnvironmentVariables]\n", '[EnvironmentVariables]\n"WINEMSYNC" = "1"\n', 1)
    open(path, "w", encoding="utf-8").write(conf)
EOF

reg() { WINEDEBUG=-all "$CX/wine" --bottle "$BOTTLE" reg add "$@" /f >/dev/null 2>&1 </dev/null; }
step "Configuring the bottle"
reg 'HKCU\Software\Wine\AppDefaults\Game.exe' /v Version /t REG_SZ /d win7
D2KEY='HKCU\Software\Blizzard Entertainment\Diablo II'
reg "$D2KEY" /v InstallPath /t REG_SZ /d 'C:\Games\median-xl\'
reg "$D2KEY" /v NewSavePath /t REG_SZ /d 'C:\users\crossover\Saved Games\Diablo II\\'
reg "$D2KEY" /v 'Preferred Realm' /t REG_SZ /d TSW
reg "$D2KEY" /v 'Aux Battle.net' /t REG_SZ /d 216.148.246.35
reg "$D2KEY" /v Resolution /t REG_DWORD /d 1
mkdir -p "$PREFIX/drive_c/users/crossover/Saved Games/Diablo II"

mkdir -p "$GAME_DIR" "$SUPPORT"
for name in $D2_MPQS; do
  [[ -f $GAME_DIR/$name ]] && continue
  step "Copying $name"
  found=( "$SRC"/(#i)$name(N.) )
  cp -c "$found[1]" "$GAME_DIR/$name" 2>/dev/null || cp "$found[1]" "$GAME_DIR/$name"
done

cp "$REPO/launcher.sh" "$REPO/mxl-update.py" "$SUPPORT/"
chmod +x "$SUPPORT/launcher.sh"
if (( D2GL_MXL )); then
  print -r -- ${(j:,:)D2GL_MXL_FILES} > "$KEEP_FILE"
else
  rm -f "$KEEP_FILE"
fi
keep=""
[[ -s $KEEP_FILE ]] && keep="$(<"$KEEP_FILE")"

step "Installing / checking Median XL files from the official release manifest (about 600 MB on the first install)"
/usr/bin/python3 -I "$SUPPORT/mxl-update.py" --game "$GAME_DIR" --keep "$keep"

if (( D2GL_MXL )); then
  step "Installing D2GL-MXL 1.0.5"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/Release.zip" "$D2GL_MXL_URL"
  [[ $(shasum -a 256 "$tmp/Release.zip" | cut -d' ' -f1) == $D2GL_MXL_SHA256 ]] || die "D2GL-MXL download does not match the expected checksum"
  unzip -q -o "$tmp/Release.zip" $D2GL_MXL_FILES -d "$GAME_DIR"
fi

step "Creating ~/Applications/$APP_NAME.app"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/$APP_NAME.app"
osacompile -o "$HOME/Applications/$APP_NAME.app" \
  -e "do shell script \"/bin/zsh \" & quoted form of \"$SUPPORT/launcher.sh\" & \" \" & quoted form of \"$BOTTLE\""

step "Done. Start the game with '$APP_NAME' (Spotlight or ~/Applications)."
