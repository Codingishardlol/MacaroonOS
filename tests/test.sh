#!/usr/bin/env bash
# Macaroon OS behavioral test suite — one command:  bash tests/test.sh
# Run from the "Macaroon OS" folder. Boots the real OS in CraftOS-PC and
# checks behavior, not just syntax. Exit 0 = all pass.
#
# Lessons baked in: craftos ignores SIGTERM (always `timeout -s KILL`),
# headless craftos ignores piped stdin (keys go via xdotool under Xvfb),
# headless output has terminal control bytes (grep via `strings`).
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
# Count green (desktop Start button) or light-blue (splash/login/desktop bg) pixels.
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

echo "=== T0: syntax (luac -p every Lua file, plus 5.1 subset) ==="
luac -p startup.lua installer.lua update.lua macaroon/*.lua macaroon/apps/*.lua
hit $? "T0a luac clean"
luac5.1 -p startup.lua installer.lua update.lua macaroon/*.lua macaroon/apps/*.lua
hit $? "T0b lua 5.1 subset clean (CC runs 5.1)"

echo "=== T1a: boot with NO accounts reaches desktop ==="
D=$(mkdata)
timeout -s KILL 12 craftos --directory "$D" --headless >"$TMPBASE/t1a.txt" 2>&1; rc=$?
grep -aqE "[0-9]{1,2}:[0-9]{2}" "$TMPBASE/t1a.txt" && clock=0 || clock=1
{ [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && running=0 || running=1
hit $((clock || running)) "T1a desktop taskbar clock visible, OS still running (rc=$rc)"
rm -rf "$D"

echo "=== T1b: boot WITH accounts stops at login ==="
D=$(mkdata); mkaccount "$D" >/dev/null
timeout -s KILL 12 craftos --directory "$D" --headless >"$TMPBASE/t1b.txt" 2>&1; rc=$?
grep -aq "Password" "$TMPBASE/t1b.txt" && pw=0 || pw=1
{ [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && running=0 || running=1
hit $((pw || running)) "T1b login screen waiting (rc=$rc)"

echo "=== T2a: password verify logic (real Users API in emulator) ==="
timeout -s KILL 20 craftos --directory "$D" --headless --exec \
  'local U=dofile("macaroon/users.lua"); local good=U.verify("testuser","testpass123"); local bad=U.verify("testuser","wrongpass123"); print("VERIFY good="..tostring(good).." bad="..tostring(bad)); os.shutdown(good and not bad and 0 or 5)' \
  2>/dev/null | strings | grep -aq "VERIFY good=true bad=false"; hit $? "T2a correct password verifies, wrong rejected"

echo "=== T2b: login UI with correct password reaches desktop ==="
export D
mkdir -p screenshots
xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
craftos --directory "$D" &
CPID=$!
sleep 15
scrot screenshots/test-login-screen.png
xdotool type --delay 80 "testpass123"
xdotool key Return
sleep 6
scrot screenshots/test-login-desktop.png
kill $CPID; sleep 1; kill -9 $CPID 2>/dev/null || true
' >/dev/null 2>&1
g=$(pxcount screenshots/test-login-desktop.png green)
echo "desktop green pixels: $g"
[ "$g" -gt 500 ]; hit $? "T2b typed correct password -> desktop (green=$g)"

echo "=== T2c: login UI with WRONG password stays locked ==="
xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
craftos --directory "$D" &
CPID=$!
sleep 15
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

echo "=== T3: R during splash gives recovery (no shell), users.dat untouched ==="
H0=$(sha256sum "$D/computer/0/macaroon/users.dat" | cut -d" " -f1)
export H0
xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
craftos --directory "$D" &
CPID=$!
sleep 2; xdotool key r
sleep 1; xdotool key r
sleep 1; xdotool key r
sleep 4
scrot screenshots/test-recovery-menu.png
xdotool type --delay 80 "2"
xdotool key Return
sleep 12
scrot screenshots/test-reboot-splash.png
kill $CPID; sleep 1; kill -9 $CPID 2>/dev/null || true
' >/dev/null 2>&1
H1=$(sha256sum "$D/computer/0/macaroon/users.dat" | cut -d" " -f1)
recblue=$(pxcount screenshots/test-recovery-menu.png blue)
postblue=$(pxcount screenshots/test-reboot-splash.png blue)
echo "users.dat $H0 -> $H1; recovery-shot blue: $recblue; post-reboot blue: $postblue"
[ "$H0" = "$H1" ]; intact=$?
[ "$recblue" -lt 20000 ]; ismenu=$?      # recovery menu is black, not splash
[ "$postblue" -gt 50000 ]; rebooted=$?   # rebooted to light-blue splash, not shell
{ [ "$intact" -eq 0 ] && [ "$ismenu" -eq 0 ] && [ "$rebooted" -eq 0 ]; }
hit $? "T3 recovery menu shown, rebooted, users.dat intact"
rm -rf "$D"

echo "=== T4: deleting core files never yields shell or open desktop ==="
t4case() { # $1=file-to-delete $2=expect-marker $3=label
  local dd; dd=$(mkdata); mkaccount "$dd" >/dev/null
  rm "$dd/computer/0/$1"
  timeout -s KILL 15 craftos --directory "$dd" --headless >"$TMPBASE/t4.txt" 2>&1; local rc=$?
  grep -aq "$2" "$TMPBASE/t4.txt" && marker=0 || marker=1
  grep -aqE "[0-9]{1,2}:[0-9]{2}" "$TMPBASE/t4.txt" && Nodesktop=1 || Nodesktop=0
  rm -rf "$dd"
  { [ "$rc" -eq 0 ] && [ "$marker" -eq 0 ] && [ "$Nodesktop" -eq 0 ]; }
  hit $? "$3 (rc=$rc)"
}
t4case "macaroon/desktop.lua" "boot failed" "T4a no desktop.lua -> shutdown, no desktop"
t4case "macaroon/window.lua" "boot failed" "T4b no window.lua -> shutdown, no desktop"
t4case "macaroon/login.lua" "Login required" "T4c no login.lua -> shutdown, no desktop"
t4case "macaroon/users.dat" "Accounts file damaged" "T4d no users.dat -> shutdown, no desktop"

echo "=== T5: fresh install — first account creation works ==="
D=$(mkdata)
timeout -s KILL 20 craftos --directory "$D" --headless --exec \
  'local U=dofile("macaroon/users.lua"); local ok=U.create("firstadmin","adminpass123"); local v=U.verify("firstadmin","adminpass123"); print("FRESH ok="..tostring(ok).." verify="..tostring(v).." accounts="..tostring(U.hasAccounts())); os.shutdown(ok and v and 0 or 9)' \
  2>/dev/null | strings | grep -aq "FRESH ok=true verify=true accounts=true"; setup=$?
[ -f "$D/computer/0/macaroon/users.dat" ] && dat=0 || dat=1
[ -f "$D/computer/0/macaroon/.provisioned" ] && marker=0 || marker=1
{ [ "$setup" -eq 0 ] && [ "$dat" -eq 0 ] && [ "$marker" -eq 0 ]; }
hit $? "T5 first account created, verified, marker written"
rm -rf "$D"

echo "=== T6: upgrade from 1.7.3 (accounts, no marker) boots, then has marker ==="
U173="$TMPBASE/u173"; mkdir -p "$U173"
git -C "$PROJ" archive origin/main | tar -x -C "$U173"
D=$(mktemp -d); mkdir -p "$D/computer/0"; cp -r "$U173"/startup.lua "$U173"/macaroon "$D/computer/0/"
git -C "$PROJ" show origin/main:macaroon/users.lua > "$D/computer/0/macaroon/users.lua"
timeout -s KILL 20 craftos --directory "$D" --headless --exec \
  'local U=dofile("macaroon/users.lua"); assert(U.create("olduser","oldpass123")); os.shutdown(0)' \
  >/dev/null 2>&1
[ -f "$D/computer/0/macaroon/.provisioned" ] && { echo "upgrade setup leaked a marker"; premark=1; } || premark=0
cp "$PROJ/macaroon/users.lua" "$D/computer/0/macaroon/users.lua"
cp "$PROJ/startup.lua" "$D/computer/0/startup.lua"
timeout -s KILL 12 craftos --directory "$D" --headless >"$TMPBASE/t6.txt" 2>&1; rc=$?
grep -aq "Password" "$TMPBASE/t6.txt" && pw=0 || pw=1
{ [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && running=0 || running=1
sleep 1
[ -f "$D/computer/0/macaroon/.provisioned" ] && adopted=0 || adopted=1
{ [ "$premark" -eq 0 ] && [ "$pw" -eq 0 ] && [ "$running" -eq 0 ] && [ "$adopted" -eq 0 ]; }
hit $? "T6 upgraded boot reaches login, marker adopted (rc=$rc)"
rm -rf "$D"

echo "=== T7: marker deleted but users.dat present boots normally ==="
D=$(mkdata); mkaccount "$D" >/dev/null
rm "$D/computer/0/macaroon/.provisioned"
timeout -s KILL 12 craftos --directory "$D" --headless >"$TMPBASE/t7.txt" 2>&1; rc=$?
grep -aq "Password" "$TMPBASE/t7.txt" && pw=0 || pw=1
{ [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && running=0 || running=1
{ [ "$pw" -eq 0 ] && [ "$running" -eq 0 ]; }
hit $? "T7 no marker + accounts present -> login, no shutdown (rc=$rc)"
rm -rf "$D"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
