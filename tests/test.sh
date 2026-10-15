#!/usr/bin/env bash
# Macaroon OS behavioral test suite.
#   bash tests/test.sh        full suite (~10 min), exit 0 = all pass
#   bash tests/test.sh quick  syntax + login smoke + tests covering files
#                             changed since the last commit (~20 s clean)
#   bash tests/test.sh <name> single test, e.g. T2b (also T2B, t2b)
# Run from the "Macaroon OS" folder (PROJ resolves from this file).
# Boots the real OS in CraftOS-PC and checks behavior, not just syntax.
#
# Lessons baked in: craftos ignores SIGTERM (always `timeout -s KILL`
# or kill -9); headless craftos ignores piped stdin (keys go via xdotool
# under Xvfb); headless output has terminal control bytes (grep via
# `strings`); the CraftOS terminal is 51 chars wide (long prints wrap,
# so keep grep patterns short); never use $! after a (… &) subshell
# under `set -u`; boot waits poll, they never sleep fixed amounts; exported functions\ndo not survive xvfb-run (inner shells source $GUIHELP instead).
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ"
TMPBASE=$(mktemp -d)
trap 'rm -rf "$TMPBASE"; pkill -9 -x craftos 2>/dev/null || true' EXIT
PASS=0; FAIL=0
hit()  { if [ "$1" -eq 0 ]; then echo "PASS: $2"; PASS=$((PASS+1)); else echo "FAIL: $2"; FAIL=$((FAIL+1)); fi; }

for t in craftos xvfb-run scrot xdotool python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "MISSING TOOL: $t"; exit 2; }
done
python3 -c "import PIL" 2>/dev/null || { echo "MISSING: python3-pil (pillow)"; exit 2; }

# Fresh emulator disk with the OS files (repo root == computer root).
mkdata() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/computer/0"
  cp startup.lua "$d/computer/0/"
  cp -r macaroon "$d/computer/0/"
  echo "$d"
}
# Create testuser/testpass123 through the real Users API. Prints CREATE:true.
mkaccount() { # $1 = DATA_DIR
  timeout -s KILL 20 craftos --directory "$1" --headless --exec \
    'local U=dofile("macaroon/users.lua"); local ok,err=U.create("testuser","testpass123"); print("CREATE:"..tostring(ok)); os.shutdown(ok and 0 or 9)' \
    2>/dev/null | strings | grep -a "CREATE:true"
}
# Exact pixel counts (final assertions).
pxcount() { # $1=png $2=green|blue
  python3 - "$1" "$2" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
W, H = im.size
px = im.load(); n = 0
kind = sys.argv[2]
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        if kind == 'green':
            if g > 110 and r < 110 and b < 110 and g > r + 40 and g > b + 40:
                n += 1
        else:
            if b > 200 and r < 180 and g < 210:
                n += 1
print(n)
EOF
}
# Fast pixel counts for polling (downscaled ~16x). Kinds: green|blue|lit.
pxfast() { # $1=png $2=green|blue|lit
  python3 - "$1" "$2" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
im.thumbnail((320, 200))
W, H = im.size
px = im.load(); n = 0
kind = sys.argv[2]
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        if kind == 'green':
            if g > 110 and r < 110 and b < 110 and g > r + 40 and g > b + 40:
                n += 1
        elif kind == 'blue':
            if b > 200 and r < 180 and g < 210:
                n += 1
        else:
            if r + g + b > 120:
                n += 1
print(n)
EOF
}
# Poll a screenshot until the screen matches. $1=outfile $2=kind $3=timeout_s.
# desktop = green Start button; active = settled light-blue OS screen;
# lit = any non-black window (text-mode screens like the installer).
poll_screen() {
  local out=$1 want=$2 timeout_s=$3 i=0
  while [ "$i" -lt "$timeout_s" ]; do
    scrot "$out" 2>/dev/null || true
    if [ "$want" = desktop ]; then
      [ "$(pxfast "$out" green)" -gt 40 ] && return 0
    elif [ "$want" = active ]; then
      [ "$(pxfast "$out" blue)" -gt 5000 ] && return 0
    else
      [ "$(pxfast "$out" lit)" -gt 500 ] && return 0
    fi
    sleep 2; i=$((i + 2))
  done
  return 1
}
# GUI helpers for inner xvfb-run shells: exported bash functions do NOT
# survive xvfb-run, so ship them as a sourced file instead.
GUIHELP="$TMPBASE/guihelp.sh"
{
  declare -f pxfast
  declare -f poll_screen
} > "$GUIHELP"
export GUIHELP
# Boot headless in background, poll OUTFILE for MARKER, then kill.
# Sets RC to the craftos exit (137/124 = still running, 0 = clean shutdown).
boot_poll() { # $1=datadir $2=outfile $3=marker-grep $4=timeout_s
  craftos --directory "$1" --headless >"$2" 2>&1 &
  local pid=$! i=0 found=1
  while [ "$i" -lt "$4" ]; do
    sleep 2; i=$((i + 2))
    if strings "$2" 2>/dev/null | grep -aq "$3"; then found=0; break; fi
    kill -0 $pid 2>/dev/null || break
  done
  kill -9 $pid 2>/dev/null || true
  wait "$pid" 2>/dev/null; RC=$?
  return $found
}

t0a() {
  echo "=== T0a: syntax (luac -p every Lua file) ==="
  luac -p startup.lua installer.lua update.lua macaroon/*.lua macaroon/apps/*.lua
  hit $? "T0a luac clean"
}
t0b() {
  echo "=== T0b: Lua 5.1 subset (what CC runs) ==="
  luac5.1 -p startup.lua installer.lua update.lua macaroon/*.lua macaroon/apps/*.lua
  hit $? "T0b lua 5.1 subset clean (CC runs 5.1)"
}
smoke() {
  echo "=== smoke: boot-to-login ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  boot_poll "$D" "$TMPBASE/smoke.txt" "Password" 30; found=$?
  { [ "$found" -eq 0 ] && { [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; }; }
  hit $? "smoke boot reaches login (rc=$RC)"
  rm -rf "$D"
}
t1a() {
  echo "=== T1a: boot with NO accounts reaches desktop ==="
  local D; D=$(mkdata)
  boot_poll "$D" "$TMPBASE/t1a.txt" "[0-9][0-9]*:[0-9][0-9]" 30; found=$?
  { [ "$found" -eq 0 ] && { [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; }; }
  hit $? "T1a desktop taskbar clock visible, OS still running (rc=$RC)"
  rm -rf "$D"
}
t1b() {
  echo "=== T1b: boot WITH accounts stops at login ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  boot_poll "$D" "$TMPBASE/t1b.txt" "Password" 30; found=$?
  { [ "$found" -eq 0 ] && { [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; }; }
  hit $? "T1b login screen waiting (rc=$RC)"
  rm -rf "$D"
}
t2a() {
  echo "=== T2a: password verify logic (real Users API in emulator) ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  timeout -s KILL 20 craftos --directory "$D" --headless --exec \
    'local U=dofile("macaroon/users.lua"); local good=U.verify("testuser","testpass123"); local bad=U.verify("testuser","wrongpass123"); print("VERIFY good="..tostring(good).." bad="..tostring(bad)); os.shutdown(good and not bad and 0 or 5)' \
    2>/dev/null | strings | grep -aq "VERIFY good=true bad=false"; hit $? "T2a correct password verifies, wrong rejected"
  rm -rf "$D"
}
t2b() {
  echo "=== T2b: login UI with correct password reaches desktop ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  export D TMPBASE
  mkdir -p screenshots
  xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
  . "$GUIHELP"
  craftos --directory "$D" &
  CPID=$!
  poll_screen screenshots/test-login-screen.png active 60
  xdotool type --delay 80 "testpass123"
  xdotool key Return
  poll_screen screenshots/test-login-desktop.png desktop 30
  kill $CPID; sleep 1; kill -9 $CPID 2>/dev/null || true
  ' >/dev/null 2>&1
  g=$(pxcount screenshots/test-login-desktop.png green)
  echo "desktop green pixels: $g"
  [ "$g" -gt 500 ]; hit $? "T2b typed correct password -> desktop (green=$g)"
  rm -rf "$D"
}
t2c() {
  echo "=== T2c: login UI with WRONG password stays locked ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  export D TMPBASE
  mkdir -p screenshots
  xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
  . "$GUIHELP"
  craftos --directory "$D" &
  CPID=$!
  poll_screen screenshots/test-login-wait.png active 60
  xdotool type --delay 80 "wrongpass123"
  xdotool key Return
  sleep 4
  scrot screenshots/test-login-wrong.png
  kill $CPID; sleep 1; kill -9 $CPID 2>/dev/null || true
  ' >/dev/null 2>&1
  g=$(pxcount screenshots/test-login-wrong.png green)
  [ "$g" -eq 0 ]; nogreen=$?
  fc=$(timeout -s KILL 15 craftos --directory "$D" --headless --exec \
    'local U=dofile("macaroon/users.lua"); print("FAILCOUNT:"..U.failCount()); os.shutdown(0)' \
    2>/dev/null | strings | grep -ao "FAILCOUNT:[0-9]*" | grep -ao "[0-9]*")
  [ "${fc:-0}" -ge 1 ]; recorded=$?
  echo "wrong-shot green: $g, failCount: ${fc:-?}"
  { [ "$nogreen" -eq 0 ] && [ "$recorded" -eq 0 ]; }; hit $? "T2c wrong password -> still login, failure recorded"
  rm -rf "$D"
}
t3() {
  echo "=== T3: R during splash gives recovery (no shell), users.dat untouched ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  H0=$(sha256sum "$D/computer/0/macaroon/users.dat" | cut -d" " -f1)
  export D H0 TMPBASE
  mkdir -p screenshots
  xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
  . "$GUIHELP"
  craftos --directory "$D" &
  CPID=$!
  poll_screen "$TMPBASE/t3early.png" active 20
  sleep 1; xdotool key r
  sleep 1; xdotool key r
  sleep 1; xdotool key r
  sleep 4
  scrot screenshots/test-recovery-menu.png
  xdotool type --delay 80 "2"
  xdotool key Return
  poll_screen screenshots/test-reboot-splash.png active 30
  kill $CPID; sleep 1; kill -9 $CPID 2>/dev/null || true
  ' >/dev/null 2>&1
  H1=$(sha256sum "$D/computer/0/macaroon/users.dat" | cut -d" " -f1)
  recblue=$(pxcount screenshots/test-recovery-menu.png blue)
  postblue=$(pxcount screenshots/test-reboot-splash.png blue)
  echo "users.dat $H0 -> $H1; recovery-shot blue: $recblue; post-reboot blue: $postblue"
  [ "$H0" = "$H1" ]; intact=$?
  [ "$recblue" -lt 20000 ]; ismenu=$?
  [ "$postblue" -gt 50000 ]; rebooted=$?
  { [ "$intact" -eq 0 ] && [ "$ismenu" -eq 0 ] && [ "$rebooted" -eq 0 ]; }
  hit $? "T3 recovery menu shown, rebooted, users.dat intact"
  rm -rf "$D"
}
t4case() { # $1=file-to-delete $2=expect-marker $3=label
  local dd; dd=$(mkdata); mkaccount "$dd" >/dev/null
  rm "$dd/computer/0/$1"
  timeout -s KILL 20 craftos --directory "$dd" --headless >"$TMPBASE/t4.txt" 2>&1; local rc=$?
  grep -aq "$2" "$TMPBASE/t4.txt" && marker=0 || marker=1
  if strings "$TMPBASE/t4.txt" | grep -aqE "[0-9][0-9]*:[0-9][0-9]"; then Nodesktop=1; else Nodesktop=0; fi
  rm -rf "$dd"
  { [ "$rc" -eq 0 ] && [ "$marker" -eq 0 ] && [ "$Nodesktop" -eq 0 ]; }
  hit $? "$3 (rc=$rc)"
}
t4a() {
  echo "=== T4a: no desktop.lua -> shutdown, no desktop ==="
  t4case "macaroon/desktop.lua" "boot failed" "T4a no desktop.lua -> shutdown, no desktop"
}
t4b() {
  echo "=== T4b: no window.lua -> shutdown, no desktop ==="
  t4case "macaroon/window.lua" "boot failed" "T4b no window.lua -> shutdown, no desktop"
}
t4c() {
  echo "=== T4c: no login.lua -> shutdown, no desktop ==="
  t4case "macaroon/login.lua" "Login required" "T4c no login.lua -> shutdown, no desktop"
}
t4d() {
  echo "=== T4d: no users.dat -> shutdown, no desktop ==="
  t4case "macaroon/users.dat" "Accounts file damaged" "T4d no users.dat -> shutdown, no desktop"
}
t5() {
  echo "=== T5: fresh install — first account creation works ==="
  local D; D=$(mkdata)
  timeout -s KILL 20 craftos --directory "$D" --headless --exec \
    'local U=dofile("macaroon/users.lua"); local ok=U.create("firstadmin","adminpass123"); local v=U.verify("firstadmin","adminpass123"); print("FRESH ok="..tostring(ok).." verify="..tostring(v).." accounts="..tostring(U.hasAccounts())); os.shutdown(ok and v and 0 or 9)' \
    2>/dev/null | strings | grep -aq "FRESH ok=true verify=true accounts=true"; setup=$?
  [ -f "$D/computer/0/macaroon/users.dat" ] && dat=0 || dat=1
  [ -f "$D/computer/0/macaroon/.provisioned" ] && marker=0 || marker=1
  { [ "$setup" -eq 0 ] && [ "$dat" -eq 0 ] && [ "$marker" -eq 0 ]; }
  hit $? "T5 first account created, verified, marker written"
  rm -rf "$D"
}
t6() {
  echo "=== T6: upgrade from 1.7.3 (accounts, no marker) boots, then has marker ==="
  local U173="$TMPBASE/u173"; mkdir -p "$U173"
  # Authentic 1.7.3 code: the v1.7.3 commit, NOT origin/main (which already
  # has the marker logic). Account created by OLD code => no marker.
  local V173=e48bf80
  git -C "$PROJ" archive $V173 | tar -x -C "$U173"
  local D; D=$(mktemp -d); mkdir -p "$D/computer/0"; cp -r "$U173"/startup.lua "$U173"/macaroon "$D/computer/0/"
  git -C "$PROJ" show $V173:macaroon/users.lua > "$D/computer/0/macaroon/users.lua"
  timeout -s KILL 20 craftos --directory "$D" --headless --exec \
    'local U=dofile("macaroon/users.lua"); assert(U.create("olduser","oldpass123")); os.shutdown(0)' \
    >/dev/null 2>&1
  [ -f "$D/computer/0/macaroon/.provisioned" ] && { echo "upgrade setup leaked a marker"; premark=1; } || premark=0
  cp "$PROJ/macaroon/users.lua" "$D/computer/0/macaroon/users.lua"
  cp "$PROJ/startup.lua" "$D/computer/0/startup.lua"
  boot_poll "$D" "$TMPBASE/t6.txt" "Password" 30; rc=$RC
  grep -aq "Password" "$TMPBASE/t6.txt" && pw=0 || pw=1
  { [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; } && running=0 || running=1
  sleep 1
  [ -f "$D/computer/0/macaroon/.provisioned" ] && adopted=0 || adopted=1
  { [ "$premark" -eq 0 ] && [ "$pw" -eq 0 ] && [ "$running" -eq 0 ] && [ "$adopted" -eq 0 ]; }
  hit $? "T6 upgraded boot reaches login, marker adopted (rc=$RC)"
  rm -rf "$D"
}
t7() {
  echo "=== T7: marker deleted but users.dat present boots normally ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  rm "$D/computer/0/macaroon/.provisioned"
  boot_poll "$D" "$TMPBASE/t7.txt" "Password" 30; rc=$RC
  grep -aq "Password" "$TMPBASE/t7.txt" && pw=0 || pw=1
  { [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; } && running=0 || running=1
  { [ "$pw" -eq 0 ] && [ "$running" -eq 0 ]; }
  hit $? "T7 no marker + accounts present -> login, no shutdown (rc=$RC)"
  rm -rf "$D"
}
t8() {
  echo "=== T8: channel module logic (no network) ==="
  local D; D=$(mkdata)
  timeout -s KILL 15 craftos --directory "$D" --headless --exec \
    'local Ch=dofile("macaroon/channel.lua"); local t={}; t[#t+1]=tostring(Ch.get()=="stable"); assert(Ch.set("beta")); t[#t+1]=tostring(Ch.get()=="beta"); t[#t+1]=tostring(Ch.branch("beta")=="beta"); t[#t+1]=tostring(Ch.branch("nope")=="main"); t[#t+1]=tostring(Ch.baseFor("beta","https://x/MacaroonOS/main")=="https://x/MacaroonOS/beta"); t[#t+1]=tostring(Ch.baseFor("stable","https://x/y/beta")=="https://x/y/main"); t[#t+1]=tostring(Ch.baseFor("beta","https://x/fork")=="https://x/fork/beta"); t[#t+1]=tostring(Ch.set("gamma")==false); print("CHAN "..table.concat(t,",")); os.shutdown(0)' \
    2>/dev/null | strings | grep -aq "CHAN true,true,true,true,true,true,true,true"; hit $? "T8 channel get/set/branch/baseFor"
  rm -rf "$D"
}
t9() {
  echo "=== T9: installer asks channel, beta install works (localhost) ==="
  local SRV="$TMPBASE/srv"; mkdir -p "$SRV/beta"
  cp startup.lua update.lua "$SRV/beta/"; cp -r macaroon "$SRV/beta/"
  sed 's|https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/main|http://127.0.0.1:8471|' installer.lua > "$TMPBASE/installer_local.lua"
  local D; D=$(mktemp -d); mkdir -p "$D/computer/0"
  cp "$TMPBASE/installer_local.lua" "$D/computer/0/installer.lua"
  printf 'pcall(dofile, "installer.lua")\n' > "$D/computer/0/startup.lua"
  python3 -m http.server 8471 --directory "$SRV" >/dev/null 2>&1 &
  local SRVPID=$!
  sleep 1
  export D TMPBASE
  xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
  . "$GUIHELP"
  craftos --directory "$D" &
  CPID=$!
  poll_screen "$TMPBASE/t9prompt.png" lit 30
  xdotool type --delay 80 "b"
  xdotool key Return
  for i in $(seq 1 75); do [ -f "$D/computer/0/macaroon/apps/terminal.lua" ] && break; sleep 2; done
  sleep 4
  xdotool type --delay 80 "n"
  xdotool key Return
  sleep 3
  xdotool type --delay 80 "n"
  xdotool key Return
  sleep 2
  scrot screenshots/test-install-beta.png
  kill $CPID; sleep 1; kill -9 $CPID 2>/dev/null || true
  ' >/dev/null 2>&1
  kill $SRVPID 2>/dev/null || true
  chn=$(cat "$D/computer/0/macaroon/channel.txt" 2>/dev/null)
  url=$(cat "$D/computer/0/macaroon/update_url.txt" 2>/dev/null)
  nlua=$(find "$D/computer/0" -name "*.lua" | wc -l)
  echo "channel=$chn url=$url lua-files=$nlua"
  { [ "$chn" = "beta" ] && [[ "$url" == *"/beta"* ]] && [ "$nlua" -ge 20 ]; }; hit $? "T9 installer beta: channel saved, branch URL, files installed"
  rm -rf "$D"
}
t10() {
  echo "=== T10: updater pulls the chosen (beta) branch ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  local BETA_URL="https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/beta"
  timeout -s KILL 90 craftos --directory "$D" --headless --exec \
    'local Ch=dofile("macaroon/channel.lua"); assert(Ch.set("beta")); local Updater=dofile("macaroon/updater.lua"); local ok,err=Updater.perform("'"$BETA_URL"'"); print("PERFORM:"..tostring(ok)); os.shutdown(ok and 0 or 7)' \
    2>/dev/null | strings | grep -aq "PERFORM:true"; perf=$?
  url=$(cat "$D/computer/0/macaroon/update_url.txt" 2>/dev/null)
  want=$(git -C "$PROJ" show origin/beta:macaroon/version.lua | grep -ao '"[0-9.]*"' | head -n 1)
  got=$(grep -ao '"[0-9.]*"' "$D/computer/0/macaroon/version.lua" 2>/dev/null | head -n 1)
  echo "update_url=$url branch-ver=$want installed-ver=$got"
  { [ "$perf" -eq 0 ] && [[ "$url" == */beta ]] && [ "$got" = "$want" ]; }; hit $? "T10 beta perform: branch URL saved, branch files installed"
  rm -rf "$D"
}
t11() {
  echo "=== T11: switch back to stable reinstalls even when lower ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  timeout -s KILL 20 craftos --directory "$D" --headless --exec \
    'local Ch=dofile("macaroon/channel.lua"); assert(Ch.set("beta")); local Updater=dofile("macaroon/updater.lua"); assert(Updater.setBaseURL("https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/beta")); os.shutdown(0)' \
    >/dev/null 2>&1
  printf 'return {\n version = "9.9.9",\n name = "macaroon OS"\n}\n' > "$D/computer/0/macaroon/version.lua"
  timeout -s KILL 120 craftos --directory "$D" --headless --exec \
    'local Updater=dofile("macaroon/updater.lua"); local ok,err=Updater.switchChannel("stable"); print("SWITCH:"..tostring(ok).." "..tostring(err)); os.shutdown(ok and 0 or 8)' \
    2>/dev/null | strings | grep -aq "SWITCH:true"; sw=$?
  chn=$(cat "$D/computer/0/macaroon/channel.txt" 2>/dev/null)
  url=$(cat "$D/computer/0/macaroon/update_url.txt" 2>/dev/null)
  got=$(grep -ao '"[0-9.]*"' "$D/computer/0/macaroon/version.lua" 2>/dev/null | head -n 1)
  want=$(git -C "$PROJ" show origin/main:macaroon/version.lua | grep -ao '"[0-9.]*"' | head -n 1)
  echo "channel=$chn url=$url installed-ver=$got (want $want, was 9.9.9)"
  { [ "$sw" -eq 0 ] && [ "$chn" = "stable" ] && [[ "$url" == */main ]] && [ "$got" = "$want" ]; }
  hit $? "T11 switch to stable: downgrade reinstalled, channel saved"
  rm -rf "$D"
}
t12() {
  echo "=== T12: no channel file means stable ==="
  local D; D=$(mkdata)
  timeout -s KILL 15 craftos --directory "$D" --headless --exec \
    'local Ch=dofile("macaroon/channel.lua"); local Updater=dofile("macaroon/updater.lua"); local g=Ch.get(); local u=Updater.getChannel(); local tail=string.sub(Ch.baseFor(u,Updater.getBaseURL()),-5); print("NOCH-G:"..g); print("NOCH-U:"..u); print("NOCH-TAIL:"..tail); os.shutdown(g=="stable" and u=="stable" and 0 or 6)' \
    >"$TMPBASE/t12.txt" 2>&1
  s=$(strings "$TMPBASE/t12.txt")
  echo "$s" | grep -aq "NOCH-G:stable" && g=0 || g=1
  echo "$s" | grep -aq "NOCH-U:stable" && u=0 || u=1
  echo "$s" | grep -aq "NOCH-TAIL:/main" && t=0 || t=1
  { [ "$g" -eq 0 ] && [ "$u" -eq 0 ] && [ "$t" -eq 0 ]; }; hit $? "T12 missing channel defaults to stable/main"
  rm -rf "$D"
}

# Files each test covers (repo-relative). Used by quick mode.
covers() { # $1 = test fn -> files
  case "$1" in
    smoke) printf '%s\n' startup.lua macaroon/boot.lua macaroon/login.lua macaroon/users.lua;;
    t1a) printf '%s\n' startup.lua macaroon/shellboot.lua macaroon/boot.lua macaroon/desktop.lua macaroon/window.lua;;
    t1b) printf '%s\n' startup.lua macaroon/shellboot.lua macaroon/boot.lua macaroon/login.lua macaroon/users.lua;;
    t2a) printf '%s\n' macaroon/users.lua;;
    t2b|t2c) printf '%s\n' macaroon/login.lua macaroon/users.lua macaroon/desktop.lua;;
    t3) printf '%s\n' startup.lua macaroon/boot.lua;;
    t4a) printf '%s\n' macaroon/desktop.lua startup.lua;;
    t4b) printf '%s\n' macaroon/window.lua startup.lua;;
    t4c) printf '%s\n' macaroon/login.lua startup.lua;;
    t4d) printf '%s\n' macaroon/users.lua startup.lua;;
    t5) printf '%s\n' macaroon/users.lua;;
    t6|t7) printf '%s\n' startup.lua macaroon/users.lua;;
    t8) printf '%s\n' macaroon/channel.lua;;
    t9) printf '%s\n' installer.lua macaroon/channel.lua;;
    t10|t11) printf '%s\n' macaroon/updater.lua macaroon/channel.lua macaroon/manifest.lua;;
    t12) printf '%s\n' macaroon/channel.lua macaroon/updater.lua;;
    t13) printf '%s\n' startup.lua macaroon/manifest.lua installer.lua macaroon/apps/notepad.lua;;
    t14) printf '%s\n' macaroon/apps/notepad.lua;;
    t15) printf '%s\n' macaroon/updater.lua macaroon/channel.lua macaroon/manifest.lua startup.lua macaroon/apps/notepad.lua;;
  esac
}
ALL_TESTS="t1a t1b t2a t2b t2c t3 t4a t4b t4c t4d t5 t6 t7 t8 t9 t10 t11 t12 t13 t14 t15"

run_full() {
  t0a; t0b
  for t in $ALL_TESTS; do "$t"; done
}
run_quick() {
  t0a; t0b; smoke
  local changed f t
  changed=$(git diff --name-only HEAD; git ls-files --others --exclude-standard | grep -v '^screenshots/' || true)
  [ -z "$changed" ] && return 0
  for t in $ALL_TESTS; do
    # T15 verifies DEPLOYED branches (needs the feature pushed first),
    # so it runs in full mode, never in quick.
    [ "$t" = t15 ] && continue
    while read -r f; do
      [ -z "$f" ] && continue
      if covers "$t" | grep -qxF "$f"; then "$t"; break; fi
    done <<< "$changed"
  done
}
run_name() { # T2b -> t2b
  local n; n=$(echo "$1" | tr 'A-Z' 'a-z')
  case "$n" in
    t0a|t0b|smoke|t1a|t1b|t2a|t2b|t2c|t3|t4a|t4b|t4c|t4d|t5|t6|t7|t8|t9|t10|t11|t12|t13|t14|t15) "$n";;
    *) echo "unknown test: $1 (try: quick, $ALL_TESTS)" >&2; return 2;;
  esac
}

t13() {
  echo "=== T13: Notepad wired consistently (local, no network) ==="
  grep -aq "notepad" startup.lua && reg=0 || reg=1
  [ -f macaroon/apps/notepad.lua ] && fil=0 || fil=1
  awk '/local FILES = \{/,/^\}/' installer.lua | grep -o '"[^"]*"' | tr -d '"' | sort -u > "$TMPBASE/ifiles.txt"
  grep -o '"[^"]*"' macaroon/manifest.lua | tr -d '"' | sort -u > "$TMPBASE/manifest.txt"
  diff -q "$TMPBASE/ifiles.txt" "$TMPBASE/manifest.txt" >/dev/null 2>&1 && same=0 || same=1
  grep -aq "macaroon/apps/notepad.lua" "$TMPBASE/ifiles.txt" && inl=0 || inl=1
  echo "registered=$reg file=$fil lists-identical=$same notepad-listed=$inl"
  { [ "$reg" -eq 0 ] && [ "$fil" -eq 0 ] && [ "$same" -eq 0 ] && [ "$inl" -eq 0 ]; }
  hit $? "T13 Notepad registered, manifest==installer FILES"
}
t14() {
  echo "=== T14: Notepad edits/saves normal files, refuses OS files ==="
  local D; D=$(mkdata)
  H0=$(sha256sum "$D/computer/0/startup.lua" | cut -d" " -f1)
  timeout -s KILL 30 craftos --directory "$D" --headless --exec \
    'local function mockWin() local m = { buf = {} }; function m.setCursorPos(x, y) m.cx, m.cy = x, y end; function m.write(s) local y = m.cy or 1; m.buf[y] = (m.buf[y] or "") .. tostring(s) end; function m.clear() m.buf = {} end; function m.setBackgroundColor(c) end; function m.setTextColor(c) end; function m.getSize() return 44, 13 end; return m end
    local App = dofile("macaroon/apps/notepad.lua")
    local win = mockWin()
    App.onEvent(win, "char", "h"); App.onEvent(win, "char", "i")
    local hdr = mockWin(); App.draw(hdr)
    local hs = table.concat(hdr.buf, "|"); print("DIRTYHDR:"..tostring(string.find(hs, "*", 1, true) ~= nil))
    App.onEvent(win, "mouse_click", 1, 40, 13)
    for c in ("notes.txt"):gmatch(".") do App.onEvent(win, "char", c) end
    App.onEvent(win, "key", 28)
    print("SAVED:"..tostring(fs.exists("notes.txt")))
    App.onEvent(win, "char", "X")
    print("VETO1:"..tostring(App.canClose()))
    print("VETO2:"..tostring(App.canClose()))
    App.onEvent(win, "mouse_click", 1, 15, 13)
    for c in ("startup.lua"):gmatch(".") do App.onEvent(win, "char", c) end
    App.onEvent(win, "key", 28)
    local hdr2 = mockWin(); App.draw(hdr2)
    print("STILLNOTES:"..tostring(string.find(table.concat(hdr2.buf, "|"), "notes.txt", 1, true) ~= nil))
    App.onEvent(win, "mouse_click", 1, 40, 13)
    for c in ("macaroon/evil.lua"):gmatch(".") do App.onEvent(win, "char", c) end
    App.onEvent(win, "key", 28)
    print("SAVEREFUSED:"..tostring(not fs.exists("macaroon/evil.lua")))
    print("CLEANVETO:"..tostring((function() local A2 = dofile("macaroon/apps/notepad.lua"); return A2.canClose() end)()))
    os.shutdown(0)' \
    >"$TMPBASE/t14.txt" 2>&1
  s=$(strings "$TMPBASE/t14.txt")
  echo "$s" | grep -aq "DIRTYHDR:true" && a=0 || a=1
  echo "$s" | grep -aq "SAVED:true" && b=0 || b=1
  echo "$s" | grep -aq "VETO1:false" && c=0 || c=1
  echo "$s" | grep -aq "VETO2:true" && d=0 || d=1
  echo "$s" | grep -aq "SAVEREFUSED:true" && e=0 || e=1
  echo "$s" | grep -aq "STILLNOTES:true" && oo=0 || oo=1
  echo "$s" | grep -aq "CLEANVETO:true" && f=0 || f=1
  [ "$(cat "$D/computer/0/notes.txt" 2>/dev/null)" = "hi" ] && content=0 || content=1
  H1=$(sha256sum "$D/computer/0/startup.lua" | cut -d" " -f1)
  [ "$H0" = "$H1" ] && intact=0 || intact=1
  echo "hdr=$a saved=$b veto=$c/$d openref=$oo saveref=$e clean=$f content=$content intact=$intact"
  { [ "$a" -eq 0 ] && [ "$b" -eq 0 ] && [ "$c" -eq 0 ] && [ "$d" -eq 0 ] && [ "$oo" -eq 0 ] && [ "$e" -eq 0 ] && [ "$f" -eq 0 ] && [ "$content" -eq 0 ] && [ "$intact" -eq 0 ]; }
  hit $? "T14 edit/save works, OS files refused, veto works"
  rm -rf "$D"
}
t15() {
  echo "=== T15: Stable->Beta installs Notepad, back removes it ==="
  local D; D=$(mkdata); mkaccount "$D" >/dev/null
  timeout -s KILL 120 craftos --directory "$D" --headless --exec \
    'local Updater=dofile("macaroon/updater.lua"); local ok,err=Updater.switchChannel("beta"); print("SWITCH:"..tostring(ok)); os.shutdown(ok and 0 or 8)' \
    2>/dev/null | strings | grep -aq "SWITCH:true"; sw1=$?
  grep -aq "notepad" "$D/computer/0/startup.lua" 2>/dev/null && reg1=0 || reg1=1
  [ -f "$D/computer/0/macaroon/apps/notepad.lua" ] && fil1=0 || fil1=1
  timeout -s KILL 120 craftos --directory "$D" --headless --exec \
    'local Updater=dofile("macaroon/updater.lua"); local ok,err=Updater.switchChannel("stable"); print("SWITCH:"..tostring(ok)); os.shutdown(ok and 0 or 8)' \
    2>/dev/null | strings | grep -aq "SWITCH:true"; sw2=$?
  grep -aq "notepad" "$D/computer/0/startup.lua" 2>/dev/null && reg2=1 || reg2=0
  echo "to-beta: sw=$sw1 reg=$reg1 file=$fil1 | to-stable: sw=$sw2 unregistered=$reg2"
  { [ "$sw1" -eq 0 ] && [ "$reg1" -eq 0 ] && [ "$fil1" -eq 0 ] && [ "$sw2" -eq 0 ] && [ "$reg2" -eq 0 ]; }
  hit $? "T15 channel switch installs/removes Notepad registration"
  rm -rf "$D"
}

if [ $# -eq 0 ]; then
  run_full
elif [ "$1" = quick ]; then
  run_quick
else
  for a in "$@"; do run_name "$a" || exit $?; done
fi
echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
