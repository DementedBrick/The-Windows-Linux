# Prüfbericht – TheWindowsLinux 1.2.0

Stand: 12.11.2026. Geprüft wurde das gesamte Projekt: Installer, Deinstaller, Hilfsprogramme, das Terminal-Overlay,
die XFCE-Konfiguration, die ISO-Skripte und der Umgang mit „bekannten Linux-Dingen“ (Distributionen, Paketquellen,
Standard-Konfigurationsdateien, übliche Befehle). Methode: Quelltext-Durchsicht, `shellcheck`, und vor allem **echte
Läufe**: Installieren/Deinstallieren auf Testkonten, eine echte XFCE-Sitzung für einen neuen Benutzer und ein
Pseudo-Terminal für die Eingabeaufforderung.

**Ergebnis in einem Satz:** Es gab zwei schwere und mehrere mittlere Lücken, alle sind behoben und durch automatische Tests
abgesichert. Das Overlay bringt keine eigenen Programme mit – Sicherheitslücken in installierter Software kommen aus der
Distribution (siehe „Was dieser Bericht nicht abdeckt“).

## Gefundene und behobene Lücken

### Sicherheit

| Schwere | Problem | Wirkung | Behebung | Test |
|---|---|---|---|---|
| **Hoch** | Im Systemmodus übernahm der Installer Eigentümer und Rechte aus dem Quellordner (`cp -a` als root). | Systemdateien (auch Skripte, die root oder andere Benutzer ausführen) gehörten dem Benutzer, der das Projekt geklont hat, und waren je nach `umask` gruppenbeschreibbar. Dieser Benutzer hätte sie später ändern und damit Rechte erweitern können. | Dateien werden ohne Eigentümer übernommen, danach `chown root:root` und `go-w`. | `test-system.sh` baut den Quellordner absichtlich mit fremdem Eigentümer und Gruppen-Schreibrecht und prüft das Ergebnis. |
| **Hoch** | Im Systemmodus wurde `xfce4-session.xml` der Distribution überschrieben. Darin steht, welche Programme beim Start der Sitzung laufen. | Für jeden neuen Benutzer startete kein Fenstermanager, kein Panel und kein Desktop. | Dateien der Distribution an gemeinsamen Orten (`/etc/xdg`) werden nie überschrieben; neue Benutzer erhalten ihre Fassung im eigenen Profil, die XFCE mit der Systemdatei zusammenführt. Die Sitzungsdatei entfällt ganz. | Der Test legt einen Benutzer an, startet seine XFCE-Sitzung und prüft Panel, Fenstermanager, Desktop, Theme und Hintergrund. |
| Mittel | Die Schrift „Selawik“ wurde automatisch von GitHub (Branch `master`, ohne Prüfsumme) geladen und im Systemschriftordner abgelegt. | Schriften werden von FreeType/Pango eingelesen; ein untergeschobener Download wäre eine Angriffsfläche. | Nur noch auf Wunsch (`--with-selawik`), nur über HTTPS (mind. TLS 1.2), Format-Prüfung, SHA-256 wird zum Vergleich angezeigt. | – |
| Mittel | `win7-firstrun` las seine Stil-Datei mit `source`. | Jeder Code in der Datei würde ausgeführt. | Schlüssel=Wert-Einlesen mit fester Schlüsselliste. | – |
| Mittel | Terminal-Titel: Der eingetippte Befehlsname gelangte ungefiltert in eine Titel-Escape-Sequenz. | Eingefügte Steuerzeichen konnten das Terminal manipulieren. | Steuerzeichen werden entfernt. | `test-cmd.py` |
| Mittel | `rm -rf` ohne Sicherheitsnetz im Deinstaller. | Ein leerer oder falscher Pfad hätte große Teile des Systems löschen können. | Zentrale Löschfunktion verweigert Wurzel-/Home-/Systemordner und zu kurze Pfade. | – |
| Mittel | Der Deinstaller löschte per Muster Zeilen aus `.bashrc`, die denen des Benutzers glichen (`PATH`-Zeile). | Eigene Einstellungen gingen verloren. | Nur noch ausdrücklich markierte Zeilen werden entfernt; Originaldateien werden gesichert und wiederhergestellt. | `test-install.sh` (Byte-Vergleich) |
| Niedrig | `sudo ./install.sh` ohne `--system` installierte nach `/root`. | Der Desktop des normalen Benutzers blieb unverändert, ohne Fehlermeldung. | Abbruch mit klarem Hinweis. | – |
| Niedrig | Pfade mit Sonderzeichen konnten die erzeugten XML-Konfigurationsdateien ungültig machen. | Panel/Desktop starten nicht. | Werte werden XML-escaped. | `test-install.sh` prüft alle erzeugten XML-Dateien. |
| Niedrig | `win7-sound` und `win7-wallpaper` akzeptierten Namen mit `/`. | Abspielen/Setzen beliebiger Dateien. | Namen werden validiert. | – |
| Niedrig | `cmd /k` ließ Temporärdateien liegen. | Müll in `/tmp`. | Datei löscht sich selbst. | – |
| Niedrig | Auf Arch lief `pacman -Sy` ohne Upgrade. | „Teil-Upgrades“ können Arch-Systeme beschädigen. | Vollständiges `pacman -Syu` zusammen mit der Installation. | – |

### Fehlende „übliche Linux-Dinge“

| Befund | Behebung |
|---|---|
| **Keine Bildschirmsperre** – `Win+L` lief ins Leere. | `xfce4-screensaver` wird mitinstalliert. |
| Kein Bluetooth-Applet, keine Lautstärke-Oberfläche, kein Passwortspeicher für WLAN/SSH, kein Portal für Flatpak. | `blueman`, `pavucontrol`, `gnome-keyring`, `xdg-desktop-portal-gtk`. Drucken fehlt **bewusst** (Druckdienste hatten 2024 eine schwere Sicherheitslücke). |
| Keine Firewall, keine automatischen Sicherheitsupdates, Standard-Kernel-Einstellungen. | Optional `--harden` (siehe README) und die Diagnose `win7-doctor`. |
| Paketlisten: ein einzelnes fehlendes Paket (z. B. `network-manager-gnome`) stoppte die ganze Installation. | Pro Paket prüfen und überspringen, bei Fehlern einzeln weiterinstallieren. |

### Eingabeaufforderung (Terminal-Overlay) – das Overlay verbog echte Linux-Befehle

Das war die größte Gruppe. Ursache: Funktionen mit denselben Namen wie echte Befehle (`ls`, `mkdir`, `find`, `echo`, `cd`, `ping` …)
und eine Umschreibung der Eingabezeile. Die Tests zeigten:

| Befund | Wirkung | Behebung |
|---|---|---|
| Aliase der `.bashrc` (z. B. `alias ls='ls --color=auto'`; unter Debian/Mint auch `alias dir=…`) | Syntaxfehler beim Start; mit `alias dir` brach das Laden mitten ab – **`ver`, `copy`, `type` u. v. m. fehlten komplett**. Betrifft die Standard-`.bashrc` der gängigen Distributionen. | Alias-Expansion während des Ladens aus, danach wieder an. |
| `cat /nope` → `cat -nope` (Pfade mit ein bis acht Buchstaben wurden als Schalter gelesen) | Falsche Fehlermeldung oder Hänger | Windows-Übersetzung nur bei eindeutig Windows-artigen Aufrufen (`C:\…`, `..\x`, `/s`-Schalter), sonst unverändert. |
| `mkdir -p a/b` legte Ordner namens `-p` an | Datenmüll | s. o. |
| `find … -exec … \;` wurde zu `/;` | `find` unbrauchbar | Umschreibung nur für Windows-eigene Befehle, und `\ `/`\;` bleiben unberührt. |
| Umschreibung löste `*.txt` zu Dateinamen auf und veränderte Leerzeichen | Befehle mit Platzhaltern wurden verändert | Wortweise Verarbeitung ohne Dateinamen-Expansion. |
| Befehle, die mit `cd` beginnen (`cdrecord …`), wurden wie `cd` behandelt | Falsche Argumente | Nur `cd`, `cd..`, `cd\`. |
| Wurde während eines laufenden Befehls weitergetippt, kam Enter als `\n` an und umging die Umschreibung | Backslash-Pfade gingen verloren | Beide Tasten (`Enter`, `Strg+J`) laufen über die Umschreibung. |
| `time`, `cd -`, `echo -e/-n`, `fc -l` (Verlauf) | gingen nicht oder falsch | bash-Schlüsselwort bzw. Optionen werden durchgereicht. |
| `ping -t 64`/`-n` (Linux: TTL/numerisch) und `netstat -tulpn`, `net` (Samba), `tree -L`, `rename s/x/y/`, `calc 2+2`, `sc` | Windows-Bedeutung überdeckte die Linux-Bedeutung | Windows-Form nur, wenn eindeutig (z. B. `-t` ohne Zahl); sonst echtes Programm. |
| **`shutdown -h now`** wäre als **Ruhezustand** (Windows-`-h` = hibernate) gedeutet worden | Rechner fällt in den Ruhezustand statt auszuschalten | Linux-Aufrufe gehen unverändert an das echte `shutdown`; Windows-Schalter nur als `/s /r /l /h /a`. |
| Vorhandenes `PROMPT_COMMAND` und `DEBUG`-Trap wurden überschrieben (direnv, starship, History-Sync, …) | Andere Shell-Werkzeuge fielen aus | Ergänzen statt ersetzen. |
| Paketvorschläge von `command-not-found` gingen verloren | Weniger hilfreich | Werden nach der Windows-Meldung angezeigt. |
| `taskkill /t` war angekündigt, aber ohne Funktion | – | Kindprozesse werden mitbeendet. |
| `%USERNAME%`, `%COMPUTERNAME%`, `%TEMP%`, `%CD%`, `%DATE%` … blieben unaufgelöst | Windows-Skripte-Gefühl fehlte | werden erweitert; Unbekanntes bleibt stehen. |

### Installer und Deinstaller

| Befund | Behebung |
|---|---|
| Zweite Installation überschrieb die Sicherung der Originale; die Deinstallation stellte dann die **Overlay-Dateien** statt der Originale wieder her. | Originale werden genau einmal gesichert; Installationsliste und angelegte Ordner werden protokolliert. |
| Die Deinstallation hinterließ Ordner, `.profile`-Leerzeilen und Cache-Dateien. | Der Zustand nach Deinstallation ist **byte-identisch** mit dem vorherigen (Dateien, Ordner, Rechte, Inhalte). |
| Installationen älterer Versionen (1.0/1.1) ließen sich nicht sauber entfernen. | Werden erkannt und aufgeräumt (getestet mit einer echten 1.1-Installation). |
| Bei Neuinstallation blieben veraltete Dateien im Theme-Ordner. | Theme- und Icon-Ordner werden vor dem Kopieren ersetzt. |
| **Upgrade von Version 1.1 auf 1.2** (der Weg der meisten Anwender): Die neue Version hätte die Overlay-Dateien der alten Installation als »Originale des Benutzers« gesichert und die echten Originale nie zurückgespielt. | Beim ersten Start werden die alten Sicherungen übernommen, unprotokollierte Dateien der alten Version als »unsere« markiert und Dateien in protokollierten Ordnern nie als fremd gesichert. Getestet: alt installieren → neu darüber installieren → deinstallieren → Zustand wie vorher. |
| Zwei Fehler in genau diesem neuen Code (Lesen einer noch nicht vorhandenen Datei unter `set -e`) hätten **jede Erstinstallation** abgebrochen. | Vom Gesamttest sofort entdeckt und behoben – ein Beispiel dafür, warum die Tests bei jeder Änderung laufen. |

### Linux-Kernel

Alles hier läuft auf dem Linux-Kernel deiner Distribution; er ist die wichtigste Schicht. Das Projekt liefert **keinen** Kernel, keine
Kernel-Module, keine SUID-Programme, keine Systemdienste und öffnet keine Ports – nur Konfiguration, Grafiken und Skripte. Das wird
automatisch geprüft (`tests/test-system.sh`: keine SUID/SGID-Dateien, keine Capabilities, keine Dienste im Overlay). Eine Lücke
**im Kernel selbst** kann das Projekt deshalb weder einbauen noch beheben – sie verschwindet nur mit einem Kernel-Update der
Distribution samt Neustart. Was sich lokal prüfen und abfedern lässt, übernimmt `win7-doctor` (Abschnitt 6 und 9):

| Prüfung | Warum |
|---|---|
| Läuft der **neueste installierte** Kernel? Steht ein Kernel-Update aus? | Kernel-Korrekturen wirken erst nach dem Neustart; ein installierter, aber nicht gebooteter Kernel schützt nicht. |
| **CPU-Schwachstellen** (Spectre, Meltdown, MDS, Retbleed …): Status, den der Kernel selbst meldet | »Vulnerable« bedeutet: Der Schutz fehlt (Kernel/Microcode veraltet). |
| **Startparameter**, die Schutz abschalten (`mitigations=off`, `nokaslr`, `nopti`, `apparmor=0`, `selinux=0` …) | Solche Optionen bleiben nach Bastelversuchen oft unbemerkt stehen. |
| Kernel-Einstellungen: ASLR, verborgene Kernel-Adressen, `dmesg`, **BPF nur für root**, `perf`, Null-Zeiger-Schutz, Symlink-/Hardlink-Schutz, SYN-Cookies | Häufige Wege für lokale Rechteausweitung; die meisten lassen sich mit `--harden` setzen. |
| `tainted`-Zustand, Lockdown, Secure Boot, Festplattenverschlüsselung, AppArmor/SELinux | Zustand und Schutzschichten rund um den Kernel. |
| **Bekannte Schwachstellen (CVE)** über die Werkzeuge der Distribution: Ubuntu `ubuntu-security-status`, Debian `debsecan`, Arch `arch-audit`, Fedora `dnf updateinfo`; auf Kali `full-upgrade` | Kernel-Versionsnummern allein täuschen: Distributionen übernehmen Korrekturen in alte Versionen (»Backports«). Ein bloßer Versionsvergleich meldet deshalb zu viel oder zu wenig. Nur der Abgleich mit der Datenbank der Distribution ist verlässlich. |

`--harden` setzt dazu nur Einstellungen, die sich ohne Neustart wieder zurücknehmen lassen. **Bewusst nicht** gesetzt: `kexec_load_disabled` und
`modules_disabled` (erst nach Neustart rückgängig), User-Namespaces (Browser-Sandbox und Flatpak brauchen sie) und `ptrace_scope`
(Debugger und Pentest-Werkzeuge brauchen es).

**Berührungspunkte der Kali-Werkzeuge mit dem Kernel:** Sie nutzen rohe Netzwerk-Sockets, Paketmitschnitt und WLAN-Monitor-Modus. Wireshark
installiert sein Mitschnitt-Programm absichtlich **ohne** Sonderrechte (nur root), der Tor-Dienst wird abgeschaltet. Die Firewall aus
`--harden` sperrt eingehende Verbindungen; für Labore mit Rückverbindungen gezielt Ports freigeben.

## Tests

| Test | Prüft | Ergebnis |
|---|---|---|
| `shellcheck` (Warnungen + Fehler) | alle Shell-Skripte | sauber |
| `tests/test-cmd.py` | 40 Fälle im echten Pseudo-Terminal mit Ubuntu-`.bashrc`: Windows- und Linux-Verhalten | 44 / 44 |
| `tests/test-install.sh` | Installation Retro → Aero → Deinstallation auf Testkonto mit eigenen Dateien, Byte-Vergleich | 22 / 22 |
| `tests/test-legacy-uninstall.sh` | 1.1-Installation deinstallieren, und 1.1 → neu darüberinstallieren → deinstallieren | 8 / 8 |
| `tests/test-system.sh` | Systemmodus: Eigentümer/Rechte, keine SUID/Capabilities/Dienste im Overlay, neuer Benutzer mit echter Sitzung, Deinstallation | 19 / 19 |
| `tests/test-doctor.sh` | `win7-doctor` gegen nachgebaute Kernel-Zustände (gut/schlecht), Kernel-Versionen, CVE-Werkzeuge je Distribution | 18 / 18 |
| Kali-Werkzeugliste | 114 Werkzeuge in Ubuntu 24.04 gemeinsam installierbar (Simulation, 720 Pakete, keine Konflikte) | bestanden |
| Kali-ISO-Vorbereitung | gegen die echte offizielle Kali-Baukonfiguration | bestanden |

## Was dieser Bericht nicht abdeckt

* **Dein tatsächliches System.** Ich kann nicht darauf zugreifen. `win7-doctor` prüft es – am besten einmal mit `sudo`.
* **Sicherheitslücken in installierter Software, auch im Kernel selbst** (Browser, XFCE, Kali-Werkzeuge): Das Projekt kann sie nur
  **erkennen und abfedern**, nicht beheben – dafür sind Updates der Distribution nötig (bei Kernel-Updates mit Neustart).
  `win7-doctor` zeigt Kernel-Stand, CPU-Schwachstellen und bekannte Lücken; `--harden` richtet automatische Sicherheitsupdates ein.
* **Nicht ausgeführt** (nur Syntax bzw. Vorbereitung geprüft): GRUB-/Plymouth-/LightDM-Schritte auf echter Hardware, der
  komplette ISO-Bau (Debian und Kali; braucht Root, viel Platz und Stunden) und die Wirkung von `--harden` auf einem echten
  Rechner (im Test nur als Trockenlauf und Schlüsselprüfung gegen den Kernel).
* **Bewusst nicht enthalten:** das Kali-Repository auf Fremddistributionen (zerstört Systeme), Metasploit/Burp Suite
  (nur im Kali-Repository; Installer des Herstellers nutzen) und Druckdienste.
* Pentest-Werkzeuge sind zweischneidig: Sie nur auf eigenen Systemen oder mit schriftlicher Erlaubnis einsetzen.
