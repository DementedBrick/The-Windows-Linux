#!/usr/bin/env bash
# Führt alle Prüfungen aus. Aufruf: bash tests/run-all.sh [--system]
#   ohne Option : Lint (shellcheck) + Overlay-Tests + Installations-Roundtrip + Altversions-Deinstallation
#   --system    : zusätzlich der Systemmodus-Test (braucht root, ändert das System → nur in Wegwerf-Container/VM!)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
rc=0
run() { echo; echo "################ $1"; shift; "$@" || rc=1; }
if command -v shellcheck >/dev/null; then
    run "shellcheck (Warnungen und Fehler)" env LC_ALL=C.UTF-8 shellcheck -S warning -x install.sh uninstall.sh lib/common.sh scripts/*.sh cmd/bin/* cmd/cmdrc.sh iso/*.sh tests/*.sh
else echo "(shellcheck nicht installiert – Lint übersprungen)"; fi
for f in install.sh uninstall.sh lib/common.sh scripts/*.sh cmd/cmdrc.sh cmd/bin/* iso/*.sh tests/*.sh; do bash -n "$f" || { echo "Syntaxfehler: $f"; rc=1; }; done
run "Overlay (cmd) – Windows- und Linux-Verhalten" python3 tests/test-cmd.py
run "win7-doctor – Kernel- und CVE-Prüfungen" bash tests/test-doctor.sh
run "Installation/Deinstallation (Benutzermodus)" env W7_ALLOW_ROOT_USER=1 bash tests/test-install.sh
git -C "$ROOT" cat-file -e 88b2e9f 2>/dev/null && run "Deinstallation einer Version-1.1-Installation" env W7_ALLOW_ROOT_USER=1 bash tests/test-legacy-uninstall.sh
[ "${1:-}" = --system ] && run "Systemmodus (root)" bash tests/test-system.sh
echo; [ $rc -eq 0 ] && echo "ALLES BESTANDEN" || echo "FEHLER AUFGETRETEN"
exit $rc
