#!/usr/bin/env python3
"""PTY-Testharness für das cmd-Overlay: startet die Eingabeaufforderung in einem echten
Pseudo-Terminal (damit auch die Enter-Taste-Umschreibung aktiv ist), sendet Befehle
einzeln und liefert deren Ausgabe. Hängt ein Befehl, wird er nach 'timeout' abgebrochen."""
import fcntl, os, pty, re, select, signal, struct, sys, termios, time

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\r")


class Session:
    def __init__(self, home, rc, extra_env=None, cwd=None):
        env = dict(os.environ, HOME=home, LANG="de_DE.UTF-8", USER="user", TERM="xterm",
                   COLUMNS="120", WIN7_STYLE="retro", WIN7_NO_BANNER="1")
        env.pop("LC_ALL", None)
        env.update(extra_env or {})
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd or home)
            os.execvpe("bash", ["bash", "--rcfile", rc, "-i"], env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 400, 0, 0))
        self.n = 0
        self.startup, _ = self._read_until(None, 1.8)
        self.startup = ANSI.sub("", self.startup)

    def _read_until(self, marker, timeout):
        out, end = b"", time.time() + timeout
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.2)
            if r:
                try:
                    d = os.read(self.fd, 65536)
                except OSError:
                    break
                if not d:
                    break
                out += d
                if marker and marker.encode() in out.split(b"\n", 1)[-1] and out.count(marker.encode()) >= 2:
                    return out.decode("utf-8", "replace"), True
        return out.decode("utf-8", "replace"), marker is None

    def run(self, cmd, timeout=6):
        """Führt cmd aus und gibt (Ausgabe, hing_nicht) zurück."""
        self.n += 1
        mark = f"@@END{self.n}@@"
        os.write(self.fd, (cmd + "\r").encode())
        # Marker getrennt senden: so sieht der Befehl selbst keine Manipulation
        time.sleep(0.15)
        os.write(self.fd, (f"echo {mark}\r").encode())
        out, ok = self._read_until(mark, timeout)
        if not ok:
            os.write(self.fd, b"\x03")
        # ruhig werden lassen, damit das nächste Kommando nicht als Typeahead ankommt
        more, _ = self._read_until(None, 0.35)
        out += more
        text = ANSI.sub("", out)
        lines = text.split("\n")[1:]          # erste Zeile = Echo der eingetippten Befehlszeile
        body = []
        for ln in lines:
            ln = ln.rstrip()
            if mark in ln or re.search(r"C:\\[^>\s]*>", ln) or not ln.strip():
                continue          # Prompt-/Echo-Zeilen und Marker entfernen
            body.append(ln)
        return body, ok

    def close(self):
        try:
            os.write(self.fd, b"exit\r")
            time.sleep(0.2)
            os.kill(self.pid, signal.SIGKILL)
        except Exception:
            pass
        try:
            os.waitpid(self.pid, 0)
        except Exception:
            pass
