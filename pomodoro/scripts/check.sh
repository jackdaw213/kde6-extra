#!/usr/bin/env bash
# Headless validation loop for PomodoroKDE — no plasmashell restart required.
# Exits non-zero if any stage fails. Run: ./scripts/check.sh
set -u
cd "$(dirname "$0")/.."

QT6=/usr/lib/qt6/bin
QMLDIRS=/usr/lib/qt6/qml
FAIL=0

stage() { printf '\n===== %s =====\n' "$1"; shift; "$@" || FAIL=1; }

# Hermetic KConfig: qmltestrunner's QtTest writes ~/.config/qmltestrunnerrc via
# QSettings (KConfig-backed on KDE). Where ~/.config is read-only (sandboxed
# CI, restricted homes), KConfig escalates to a blocking
#   kdialog --msgbox "Configuration file ... not writable"
# on the GUI thread — headless that modal never closes and the QML loader
# thread deadlocks on its load handshake, freezing the runner forever
# (observed: tst_full.qml froze on first instantiation of PlasmaCore-heavy
# QML; 'QObject::installEventFilter(): Cannot filter events for objects in a
# different thread' QWARN is only a benign marker printed just before the
# deadlock). Point XDG_CONFIG_HOME at a throwaway writable dir so the config
# is creatable and no kdialog can ever spawn.
XDG_TMP=$(mktemp -d)
trap 'rm -rf "$XDG_TMP"' EXIT
export XDG_CONFIG_HOME="$XDG_TMP"

# 1. Static lint of all QML against Qt 6 / Plasma 6 imports (catches deprecated
#    Plasma 5 API usage, unqualified access, syntax errors).
for f in plasmoid/contents/ui/*.qml tests/*.qml; do
    stage "qmllint: $f" "$QT6/qmllint" -I "$QMLDIRS" -W 0 "$f"
done

# 2. Headless QML tests (Qt Test QML runner, no plasmashell): the pure state
#    machine and the representation tests following tst_compact's pattern.
#    Each stage is capped so a regression that freezes the runner reports
#    CHECK: FAIL instead of hanging the whole script.
for t in tests/tst_*.qml; do
    stage "qmltestrunner: $t" timeout 60 "$QT6/qmltestrunner" -input "$t" -platform offscreen
done

# 3. Chime asset: structural validation only (audibility is not headless-
#    testable). Must exist, decode fully, and last 2-3 s (SPEC-002).
CHIME=plasmoid/contents/sounds/pomodoro-chime.ogg
stage "chime asset: $CHIME" bash -c '
    set -e
    f="'"$CHIME"'"
    test -s "$f"
    dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$f")
    echo "duration: ${dur}s"
    awk -v d="$dur" "BEGIN { exit !(d>=2 && d<=3) }" || { echo "duration must be 2-3 s"; exit 1; }
    ffmpeg -v error -i "$f" -f null - || { echo "failed to decode"; exit 1; }
    echo "decodes fully"
'

echo
if [ "$FAIL" -eq 0 ]; then echo "CHECK: PASS"; else echo "CHECK: FAIL"; fi
exit "$FAIL"
