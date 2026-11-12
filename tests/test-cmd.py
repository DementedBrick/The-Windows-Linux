#!/usr/bin/env python3
"""Regressionstests für cmd/cmdrc.sh.
Windows-Verhalten MUSS bleiben, normale Linux-Befehle dürfen NICHT verändert werden.
Laufen in einem echten Pseudo-Terminal mit der Ubuntu-Standard-.bashrc (Aliase wie ls --color).
Aufruf: python3 tests/test-cmd.py"""
import os, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pty_harness import Session

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RC = os.path.join(ROOT, "cmd", "cmdrc.sh")
home = tempfile.mkdtemp(prefix="w7test-")
open(os.path.join(home, "notizen.txt"), "w").write("alpha\nbeta welt\n")
os.makedirs(os.path.join(home, "Dokumente"))
bashrc = open("/etc/skel/.bashrc").read() if os.path.exists("/etc/skel/.bashrc") else ""
open(os.path.join(home, ".bashrc"), "w").write(
    bashrc + "\nalias dir='dir --color=auto'\nPROMPT_COMMAND='echo PCMARK'\n")
fails, passes, skips = [], 0, 0


def check(name, cond, detail=""):
    global passes
    if cond:
        passes += 1
        print(f"  ok    {name}")
    else:
        fails.append(name)
        print(f"  FAIL  {name}\n          {str(detail)[:300]!r}")


def have(tool):
    return shutil.which(tool) is not None


s = Session(home, RC, {"WIN7_DATADIR": ROOT, "WIN7_CMD_NO_BANNER": "1"})
print("== Start ==")
check("kein Syntaxfehler beim Start (Ubuntu-.bashrc mit Aliasen)", "syntax error" not in s.startup and "Syntaxfehler" not in s.startup, s.startup)

def run(c, **kw):
    out, ok = s.run(c, **kw)
    run.raw = out
    return [l for l in out if l != "PCMARK"], ok     # PCMARK stammt vom Test-PROMPT_COMMAND

print("== Linux-Befehle bleiben unverändert ==")
out, ok = run("mkdir -p lx/a/b; ls -d lx/a/b; ls -A | grep -c '^-'")
check("mkdir -p legt keine Ordner namens -p an", ok and "lx/a/b" in out and out[-1] == "0", out)
out, ok = run("cd /tmp; cd -; pwd")
check("cd - springt zurück", ok and home in out, out)
out, ok = run("find . -maxdepth 1 -name '*.txt' -exec echo F:{} \\;")
check("find -exec ... \\; funktioniert", ok and "F:./notizen.txt" in out, out)
out, ok = run('echo -e "a\\tb" | od -c | head -1')
check("echo -e wertet Escapes aus (kein '-e' in der Ausgabe)", ok and "-   e" not in out[0] and "\\t" in out[0], out)
out, ok = run("echo -n abc; echo X")
check("echo -n", ok and out == ["abcX"], out)
out, ok = run("echo 100%")
check("echo 100% bleibt 100%", ok and out == ["100%"], out)
out, ok = run("echo 100%%")
check("echo 100%% bleibt wie in bash", ok and out == ["100%%"], out)
out, ok = run("cat /nope", timeout=4)
check("cat /nope: echter Fehler statt Hänger/Optionsfehler", ok and any("No such file" in l or "Datei oder Verzeichnis" in l for l in out), out)
out, ok = run("ls /nope", timeout=4)
check("ls /nope: echter Fehler", ok and any("cannot access" in l or "Zugriff" in l or "No such" in l for l in out), out)
out, ok = run("ls -la | head -2")
check("ls -la", ok and any(l.startswith("total") or l.startswith("insgesamt") for l in out), out)
out, ok = run("printf '%s\\n' my\\ file")
check("Backslash-Leerzeichen bleibt erhalten", ok and out == ["my file"], out)
out, ok = run("cdx() { echo CDX:$1; }; cdx a\\ b")
check("Befehle mit 'cd' am Anfang werden nicht umgeschrieben", ok and out == ["CDX:a b"], out)
out, ok = run("grep -c 'a\\|b' *.txt >/dev/null")
out, ok = run("history 3 | head -1")
check("Backslash im Muster: Zeile bleibt unverändert (kein Auflösen von *.txt)", ok and out and "*.txt" in out[0] and "'a\\|b'" in out[0], out)
out, ok = run("date +%Y")
check("date +%Y", ok and out and out[0].isdigit() and len(out[0]) == 4, out)
out, ok = run("{ time true; } 2>&1 | grep -c real")
check("time true (Shell-Schlüsselwort)", ok and out == ["1"], out)
out, ok = run("set -e; set +e; echo SETOK")
check("set -e / +e", ok and out == ["SETOK"], out)
out, ok = run("mkdir -m 700 lx/priv; stat -c %a lx/priv")
check("mkdir -m 700", ok and out == ["700"], out)
out, ok = run("cp -r lx lx2 && mv lx2 lx3 && ls -d lx3")
check("cp -r / mv", ok and out == ["lx3"], out)
out, ok = run("rm -rf lx lx3; ls -d lx 2>&1 | grep -c cannot")
check("rm -rf", ok and out == ["1"], out)
out, ok = run("echo PCCHECK")
check("vorhandenes PROMPT_COMMAND aus der .bashrc bleibt aktiv", ok and "PCMARK" in run.raw, run.raw)
out, ok = run("fc -l 2>&1 | head -1")
check("fc -l (History) nicht blockiert", ok and out and "FC" not in out[0].upper()[:3], out)
out, ok = run("echo 'x' | wc -c")
check("wc -c", ok and out == ["2"], out)
if have("tree"):
    out, ok = run("tree -L 1 2>&1 | head -2")
    check("tree -L 1 (Linux)", ok and not any("Auflistung" in l for l in out), out)
if have("netstat"):
    out, ok = run("netstat -h 2>&1 | head -1")
    check("netstat -h (Linux-Argument)", ok and out and "usage" in out[0].lower(), out)
if have("ping"):
    out, ok = run("ping -c1 -W2 127.0.0.1 2>&1 | grep -c 'bytes from'", timeout=8)
    check("ping -c1 (Linux-Syntax)", ok and out == ["1"], out)
    out, ok = run("ping -n 1 -W2 127.0.0.1 2>&1 | grep -c 'bytes from'", timeout=8)
    check("ping -n 1 (Windows-Anzahl)", ok and out == ["1"], out)
out, ok = run("shutdown --help 2>&1 | head -1")
check("shutdown --help gelangt an das echte Programm (oder fehlt)", ok and not any("SHUTDOWN [/s" in l for l in out), out)

print("== Windows-Verhalten bleibt erhalten ==")
out, ok = run("ver")
check("ver", ok and out and "TheWindowsLinux [Version" in out[0], out)
out, ok = run("dir /b")
check("dir /b (trotz alias dir=...)", ok and "notizen.txt" in out and "Dokumente" in out, out)
out, ok = run("copy notizen.txt Dokumente\\k.txt")
check("copy mit Backslash-Ziel", ok and any("kopiert" in l or "copied" in l for l in out), out)
out, ok = run("type Dokumente\\k.txt")
check("type mit Backslash", ok and "beta welt" in out, out)
out, ok = run("md C:\\Users\\user\\neu & cd C:\\Users\\user\\neu & cd")
check("md/cd mit C:\\Users\\... und &", ok and any(l == "C:\\Users\\user\\neu" for l in out), out)
out, ok = run("cd .. & del /q Dokumente\\k.txt & dir /b Dokumente")
check("del /q mit Backslash-Pfad und &", ok and "k.txt" not in out, out)
out, ok = run("echo Hallo %USERNAME% aus %COMPUTERNAME%")
check("%VAR%-Erweiterung (USERNAME)", ok and out and out[0].startswith("Hallo user aus ") and "%" not in out[0], out)
out, ok = run("echo %GIBTSNICHT%")
check("undefinierte %VAR% bleibt stehen", ok and out == ["%GIBTSNICHT%"], out)
out, ok = run("cd %USERPROFILE%\\Dokumente & cd")
check("cd %USERPROFILE%\\Dokumente", ok and any(l == "C:\\Users\\user\\Dokumente" for l in out), out)
run("cd ..")
out, ok = run("DIR /W")
check("DIR /W (Großschreibung)", ok and any("[Dokumente]" in l for l in out), out)
out, ok = run("systeminfo | head -1")
check("systeminfo", ok and out and ("Hostname" in out[0] or "Host Name" in out[0]), out)
out, ok = run("shutdown")
check("shutdown ohne Argumente: Windows-Hilfe, fährt nicht herunter", ok and any("SHUTDOWN" in l.upper() for l in out), out)
out, ok = run("cd Dokumente\\nichtda")
check("cd auf fehlenden Pfad: Windows-Fehlermeldung", ok and any("Pfad" in l or "path" in l for l in out), out)
out, ok = run("Foo.exe")
check("unbekannter Befehl: Windows-Meldung", ok and any("Foo.exe" in l for l in out), out)
out, ok = run("xyz-unbekannt", timeout=8)
check("unbekannter Befehl endet mit Status 127 ohne Hänger", ok, out)
s.close()

print("== Titel-Escape-Injection ==")
tf = os.path.join(home, "title.out")
subprocess.run(["bash", "--rcfile", RC, "-ic", f"__w7_set_title $'a\\x1b]0;PWNED\\x07b' > {tf}"], capture_output=True,
               env=dict(os.environ, WIN7_CMD_NO_BANNER="1", WIN7_DATADIR=ROOT, HOME=home))
data = open(tf, "rb").read() if os.path.exists(tf) else b""
check("Titel enthält nur das eigene ESC und BEL (Eingabe-Escapes gefiltert)", data.count(b"\x1b") == 1 and data.count(b"\x07") == 1 and b"ab" in data.replace(b"]0;PWNED", b""), data)

shutil.rmtree(home, ignore_errors=True)
print(f"\n{passes} bestanden, {len(fails)} fehlgeschlagen")
sys.exit(1 if fails else 0)
