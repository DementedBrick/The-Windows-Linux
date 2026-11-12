# Checkliste für ein erstes öffentliches Image

Der Quellcode kann öffentlich entwickelt werden, während das installierbare Image noch experimentell ist. Vor einer stabilen Image-Veröffentlichung die folgenden Punkte konkret prüfen und dokumentieren.

## Image-Bau und Start

- [ ] Debian-Image vollständig in sauberer, reproduzierbarer Build-Umgebung bauen.
- [ ] Live-System in einer VM starten und die Desktop-Sitzung, Netzwerk, Audio, Bildschirmauflösung und Herunterfahren prüfen.
- [ ] Calamares-Installation auf eine leere virtuelle Festplatte durchführen und das installierte System danach neu starten.
- [ ] Image zusätzlich auf repräsentativer echter Hardware testen und unterstützte Hardware klar benennen.

## Konten, Updates und Wiederherstellung

- [ ] Im Live-System verwendete Standardzugänge prüfen und verhindern, dass bekannte Zugangsdaten in eine installierte Sitzung übernommen werden.
- [ ] Erstbenutzer, Passwortsetzung, Adminrechte und automatische Anmeldung dokumentieren.
- [ ] Sicherheitsupdates und Kernel-Updates nach der Installation nachvollziehbar testen.
- [ ] Recovery- und Deinstallationswege für fehlgeschlagene Installation dokumentieren.

## Veröffentlichung

- [ ] Upstream-Lizenzen und Paketquellen des Images dokumentieren.
- [ ] Versionsnummer, Build-Umgebung und bekannte Einschränkungen in Release Notes festhalten.
- [ ] SHA-256-Prüfsumme für jedes Image bereitstellen; Release-Tags signieren.
- [ ] ISO-Image und Checksummen aus Git heraushalten und über GitHub Releases veröffentlichen.
- [ ] Den Release-Build und die Installationsprüfung automatisieren, soweit sie sicher in Wegwerf-VMs laufen können.
