#!/usr/bin/env bash
# Headless validation loop for PomodoroKDE — no plasmashell restart required.
# Exits non-zero if any stage fails. Run: ./scripts/check.sh
set -u
cd "$(dirname "$0")/.."

QT6=/usr/lib/qt6/bin
QMLDIRS=/usr/lib/qt6/qml
FAIL=0

stage() { printf '\n===== %s =====\n' "$1"; shift; "$@" || FAIL=1; }

# 1. Static lint of all QML against Qt 6 / Plasma 6 imports (catches deprecated
#    Plasma 5 API usage, unqualified access, syntax errors).
for f in plasmoid/contents/ui/*.qml tests/*.qml; do
    stage "qmllint: $f" "$QT6/qmllint" -I "$QMLDIRS" -W 0 "$f"
done

# 2. Headless state-machine tests (Qt Test QML runner, no plasmashell).
stage "qmltestrunner: tests/tst_machine.qml" \
    "$QT6/qmltestrunner" -input tests/tst_machine.qml -platform offscreen

echo
if [ "$FAIL" -eq 0 ]; then echo "CHECK: PASS"; else echo "CHECK: FAIL"; fi
exit "$FAIL"
