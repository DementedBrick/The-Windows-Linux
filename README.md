# TheWindowsLinux

**Ein normales Linux mit komplettem Windows-Overlay – wahlweise im Pixel-Retro-Look
(Windows-95-Ära, wie in alten Desktop-Spielen) oder im Windows-7-Aero-Look – plus
einer „Eingabeaufforderung“, die sich wie `cmd.exe` verhält.**

Unter der Haube bleibt es ein ganz gewöhnliches Linux (Debian, Ubuntu, Mint, Fedora,
Arch, openSUSE, Void …) mit XFCE. TheWindowsLinux legt darüber:

* **Retro-Stil (Standard):** 16-Farben-VGA-Palette, Dithering, pixelgenaue
  Win95-Fensterrahmen, Pixel-Icons, Pixel-Mauszeiger, Pixel-Schrift (Terminus),
  kein Antialiasing, Chiptune-Systemklänge, gedithertes Wallpaper mit Sternenhimmel
  und Cyber-Raster.
* **Aero-Stil:** Glas-Fensterrahmen, Start-Orb, Swirl-Wallpaper, Windows-7-Taskleiste.
* **Terminal-Overlay „Eingabeaufforderung“:** `C:\Users\name>`-Prompt, `DIR`, `CLS`,
  `COPY`, `DEL`, `TYPE`, `IPCONFIG`, `TASKLIST`, `SYSTEMINFO`, `SHUTDOWN /s`, …
  Windows-Pfade mit Backslash funktionieren. Alle Linux-Befehle bleiben verfügbar.

Echte XFCE-Screenshots des Retro-Stils (unter Xvfb aufgenommen):

![Retro-Startmenü und Desktop](docs/screenshot-retro.png)
![Windows-Explorer und Eingabeaufforderung](docs/screenshot-retro-windows.png)

Der Aero-Stil als Entwurf (`docs/preview-aero.png`):

![Aero-Stil](docs/preview-aero.png)

Alle Grafiken, Icons, Cursor und Klänge sind **eigene Arbeiten** (erzeugt von
`tools/generate-assets.py`). Es sind keine Microsoft-Dateien enthalten.

---

## Installation

```bash
git clone https://github.com/DementedBrick/TheWindowsLinux.git
cd TheWindowsLinux
./install.sh                    # Retro-Stil, nur für den aktuellen Benutzer
```

Danach **abmelden und mit der Sitzung „Xfce“ neu anmelden** (oder neu starten).

Weitere Varianten:

```bash
./install.sh --style aero                   # Windows-7-Aero-Look statt Retro
sudo ./install.sh --system --with-login     # für alle Benutzer + Anmeldebildschirm
sudo ./install.sh --full                    # alles: System, Login, GRUB, Plymouth, cmd überall
./install.sh --no-packages                  # XFCE ist schon da, nur Overlay anwenden
./install.sh --cmd-everywhere               # jedes Terminal wird zur Eingabeaufforderung
./install.sh --help                         # alle Optionen
```

Der Installer

1. installiert die Pakete (XFCE, Whisker-Menü, Thunar, xfce4-terminal, Schriften,
   Cursor; auf einem nackten System auch Xorg + LightDM),
2. kopiert Theme, Icons, Hintergründe und Sounds,
3. schreibt die XFCE-Konfiguration (Taskleiste, Startmenü, Desktop-Symbole,
   Fensterverwaltung, Tastenkürzel, Thunar, Benachrichtigungen),
4. richtet das cmd-Overlay ein,
5. optional: LightDM-Greeter, GRUB-Hintergrund, Plymouth-Boot-Splash.

Läuft bereits eine XFCE-Sitzung, wird sie sofort aktualisiert. Vorhandene
Konfigurationsdateien werden nach `~/.config/thewindowslinux/backup-<datum>/` gesichert.

**Deinstallation:** `./uninstall.sh` (bzw. `sudo ./uninstall.sh --system`).
**Stil wechseln:** `./install.sh --style aero --no-packages` (oder `--style retro`).

### Unterstützte Systeme

| Distribution | Paketschritt |
|---|---|
| Debian, Ubuntu, Mint, Pop!_OS, Zorin, Kali, Raspberry Pi OS | `apt` |
| Fedora, RHEL/Rocky/Alma | `dnf` |
| Arch, Manjaro, EndeavourOS | `pacman` |
| openSUSE | `zypper` |
| Void | `xbps` |
| andere | `--no-packages` + XFCE 4.14+ von Hand installieren |

Getestet mit XFCE 4.18 (Ubuntu 24.04). Benötigt werden `xfce4-panel`, `xfwm4`,
`xfdesktop`, `xfce4-session`, `xfconf`, `thunar`, `xfce4-terminal` und das
`xfce4-whiskermenu-plugin`.

---

## Bedienung

| Aktion | Tastenkürzel |
|---|---|
| Startmenü | **Win** (oder Alt+F1) |
| Windows-Explorer (Thunar) | **Win+E** |
| Ausführen… | **Win+R** |
| Desktop anzeigen | **Win+D** |
| Sperren | **Win+L** |
| Eingabeaufforderung | **Strg+Alt+T** / Win+T |
| Task-Manager | **Strg+Umschalt+Esc** / Strg+Alt+Entf |
| Systemsteuerung | Win+I |
| Fenster andocken (Aero Snap) | **Win+←/→/↑/↓** |
| Fenster wechseln | Alt+Tab |
| Screenshot | Druck / Alt+Druck (Fenster) |
| Lupe | Win+Plus / Win+Minus |

Im Startmenü (Whisker-Menü) liegen „Windows-Explorer“, „Eingabeaufforderung“,
„Systemsteuerung“, „Editor“, „Task-Manager“ und „Ausführen…“ als Favoriten.
Rechtsklick in Thunar bietet „Eingabeaufforderung hier öffnen“.

Hintergrund wechseln: `win7-wallpaper list` zeigt alle Bilder (sunset, matrix, sky, hills,
pattern, planet, teal, …), `win7-wallpaper set sunset` setzt eines, `win7-wallpaper random`
würfelt, und `win7-wallpaper ~/Bilder/foto.png` nimmt ein eigenes Bild.

Sounds abschalten: `win7-sound --off` (wieder an: `win7-sound --on`) oder den
Autostart-Eintrag „Anmeldesound“ in den Sitzungseinstellungen deaktivieren.

---

## Die Eingabeaufforderung (cmd-Overlay)

```
TheWindowsLinux [Version 4.10.2222]
(c) 2026 TheWindowsLinux. Alle Rechte vorbehalten.

C:\Users\user>dir
 Volume in Laufwerk C: hat keine Bezeichnung.

 Verzeichnis von C:\Users\user

11.11.2026  09:41    <DIR>          .
11.11.2026  09:41    <DIR>          ..
11.11.2026  09:41    <DIR>          Dokumente
11.11.2026  09:40             1.204 notizen.txt
               1 Datei(en),          1.204 Bytes
               3 Verzeichnis(se), 45.097.156.608 Bytes frei

C:\Users\user>copy notizen.txt Dokumente\kopie.txt
        1 Datei(en) kopiert.
```

Das Overlay ist eine `bash`-Schicht (`cmd/cmdrc.sh`): Es definiert Funktionen und
Aliase, übersetzt Windows-Pfade (`C:\Users\…`, `..\x`, `%USERPROFILE%`) transparent
und fängt Tippfehler mit der Windows-Fehlermeldung ab. Groß-/Kleinschreibung ist egal
(`DIR` = `dir`), `.exe` wird ignoriert, Tab-Vervollständigung ignoriert die Schreibweise.

Start: Menüeintrag **Eingabeaufforderung**, Strg+Alt+T, oder in jedem Terminal `cmd`.
`cmd /c BEFEHL` führt einen Befehl aus; `cmd /k BEFEHL` lässt die Shell offen.
`bash` oder `wsl` startet eine normale Linux-Shell; mit `--cmd-everywhere` ist das
Overlay in jeder bash aktiv.

| Windows-Befehl | macht |
|---|---|
| `dir [/b /w /s /a]`, `cd`, `cd..`, `cd\`, `md`, `rd /s`, `del /q`, `copy`, `xcopy`, `robocopy`, `move`, `ren`, `type`, `more`, `tree /f`, `attrib`, `mklink`, `fc`/`comp`, `find`, `findstr`, `where` | Datei-Operationen (mit Windows-Ausgabeformat) |
| `cls`, `ver`, `vol`, `date`, `time`, `pause`, `title`, `color 0A`, `echo.`, `rem`, `set`, `set /p`, `set /a`, `path`, `timeout /t`, `choice`, `help` | Konsole |
| `ipconfig [/all /flushdns]`, `getmac`, `ping [-t -n]`, `tracert`, `netstat`, `nslookup`, `net user/start/stop/view/use` | Netzwerk |
| `tasklist`, `taskkill /pid n /f`, `taskkill /im name`, `systeminfo`, `winver`, `sc query`, `chkdsk`, `diskpart`, `certutil -hashfile`, `assoc` | System |
| `shutdown /s /r /l /h /a /t n`, `logoff` | Herunterfahren / Neustart / Abmelden |
| `explorer`, `notepad`, `wordpad`, `calc`, `mspaint`, `control`, `taskmgr`, `msconfig`, `regedit`, `snippingtool`, `iexplore`, `wmplayer`, `start …` | startet das passende Linux-Programm |

`format` ist absichtlich deaktiviert.

---

## Aufbau des Repositories

```
install.sh / uninstall.sh      Installer / Deinstaller (Benutzer- oder Systemmodus)
lib/common.sh                  Hilfsfunktionen, Distributions- und Stil-Erkennung
scripts/                       Installationsschritte: packages, theme, xfce, cmd, login
cmd/cmdrc.sh                   das cmd-Overlay für bash
cmd/bin/                       cmd, win7-terminal, win7-sound, win7-firstrun
theme/styles/retro/            Retro-Stil: gtk/Windows-Retro, xfwm4, icons (+cursors), wallpapers, sounds
theme/styles/aero/             Aero-Stil: gtk/Windows7-Aero, xfwm4, icons, wallpapers, sounds
theme/xfce4/                   XFCE-Konfiguration (xfconf-Kanäle, Panel, Starter, Terminal, Thunar, Autostart)
tools/generate-assets.py       erzeugt alle Grafiken/Sounds neu (PIL + numpy, Cursor via xcursorgen)
iso/build-iso.sh               Live-ISO mit Debian live-build (Overlay vorinstalliert)
docs/                          Screenshot und Mockups
```

### Assets neu erzeugen / anpassen

```bash
pip install pillow numpy            # falls nötig; xcursorgen aus x11-apps für die Cursor
python3 tools/generate-assets.py            # beide Stile
python3 tools/generate-assets.py --style retro --only icons
```

Die Pixel-Icons und -Cursor sind als Text-Sprites in `tools/generate-assets.py`
definiert (`RETRO_SPRITES16`, `CURSOR_SPRITES`) und lassen sich dort direkt
bearbeiten; die 32-px-Icons werden mit Zeichenprimitiven gemalt.

### Live-ISO

`sudo ./iso/build-iso.sh --style retro` baut mit Debian `live-build` ein bootfähiges
ISO (XFCE + Overlay systemweit + Calamares-Installer). Benötigt einen Debian/Ubuntu-Host
mit `live-build debootstrap xorriso squashfs-tools`, Internet und ~10 GB Platz.
Der ISO-Build wurde in der Entwicklungsumgebung nur auf Syntax geprüft, nicht komplett
durchlaufen.

---

## Bekannte Grenzen

* Nur die mitgelieferten Icons (Start, Computer, Papierkorb, Netzwerk, Ordner,
  Eingabeaufforderung, Systemsteuerung, Browser, Editor, Task-Manager, Ausführen) sind
  Pixel-Art; alle anderen Programm-Icons kommen aus dem geerbten Icon-Theme
  (elementary-xfce/Adwaita).
* Der Retro-Stil schaltet das Font-Antialiasing systemweit ab (gewollt). Rückgängig:
  Einstellungen → Erscheinungsbild → Schriften, oder `--style aero`.
* Qt-Programme nehmen den GTK-Look nur an, wenn `qt5-gtk2-platformtheme`
  (bzw. `qt5-styleplugins`) installiert ist.
* Wayland-Sitzungen werden nicht unterstützt (XFCE/X11).

## Lizenz

MIT – siehe [LICENSE](LICENSE). „Windows“ ist eine Marke der Microsoft Corporation;
dieses Projekt steht in keiner Verbindung zu Microsoft.
