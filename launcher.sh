#!/bin/zsh
BOTTLE=${1:-MedianXL}
shift
SUPPORT=${0:A:h}
CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin
PREFIX="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
GAME_DIR="$PREFIX/drive_c/Games/median-xl"
INI="$GAME_DIR/d2gl.ini"
SAVED_PRESET="$SUPPORT/$BOTTLE.shader-preset"
UPDATE_LOG="$SUPPORT/$BOTTLE.update.log"
KEEP_FILE="$SUPPORT/$BOTTLE.keep"
GAME_RE='^C:.Games.median-xl.Game.exe'

notify() { osascript -e "display notification \"$2\" with title \"Median XL\" subtitle \"$1\"" >/dev/null 2>&1; }
alert() { osascript -e "display alert \"Median XL\" message \"$1\"" >/dev/null 2>&1; }

crashes() { LC_ALL=C cat "$GAME_DIR"/logs/D2Debug-*.txt 2>/dev/null | LC_ALL=C grep -a -c "Fault address:  00000000 "; }

keep_preset() {
  [[ -f "$INI" ]] || return
  local cur=$(grep -m1 '^shader_preset=' "$INI" | cut -d= -f2- | tr -d '\r')
  if [[ "$cur" == *.slangp ]]; then
    print -r -- "$cur" > "$SAVED_PRESET"
  elif [[ -s "$SAVED_PRESET" ]]; then
    PRESET="$(<"$SAVED_PRESET")" perl -pi -e 's/^shader_preset=[^\r\n]*/shader_preset=$ENV{PRESET}/' "$INI"
  fi
}

update_game() {
  local keep="" out code
  [[ -s "$KEEP_FILE" ]] && keep="$(<"$KEEP_FILE")"
  out=$(/usr/bin/python3 -I "$SUPPORT/mxl-update.py" --game "$GAME_DIR" --keep "$keep" --check 2>&1); code=$?
  print -r -- "$(date '+%F %T') $out" >> "$UPDATE_LOG"
  (( code == 1 )) || return 0
  notify "Downloading update" "$(print -r -- "$out" | head -1)"
  out=$(/usr/bin/python3 -I "$SUPPORT/mxl-update.py" --game "$GAME_DIR" --keep "$keep" 2>&1); code=$?
  print -r -- "$(date '+%F %T') $out" >> "$UPDATE_LOG"
  if (( code != 0 )); then
    alert "The update did not finish. Details: $UPDATE_LOG. Start the game again to retry."
    return 1
  fi
  notify "Updated" "$(print -r -- "$out" | tail -1)"
}

stop_game() {
  pkill -f "$GAME_RE"
  for i in {1..15}; do pgrep -f "$GAME_RE" >/dev/null || return; sleep 1; done
  pkill -9 -f "$GAME_RE"; sleep 2
}

[[ -d "$GAME_DIR" ]] || { alert "Median XL is not installed in the CrossOver bottle '$BOTTLE'."; exit 1; }
pgrep -f "$GAME_RE" >/dev/null && exit 0

WINEPREFIX="$PREFIX" "$CX/wineserver" -k 2>/dev/null
for i in {1..15}; do pgrep -f 'CrossOver.*wineserver' >/dev/null || break; sleep 1; done

update_game || exit 1

for attempt in {1..6}; do
  keep_preset
  before=$(crashes)
  "$CX/wine" --bottle "$BOTTLE" --workdir 'C:\Games\median-xl' -- 'C:\Games\median-xl\Game.exe' -3dfx -skiptobnet "$@" >/dev/null 2>&1 &
  for i in {1..12}; do
    sleep 1
    (( $(crashes) > before )) && break
  done
  (( $(crashes) > before )) || exit 0
  stop_game
done
alert "The game failed to start 6 times in a row. Check $GAME_DIR/logs."
exit 1
