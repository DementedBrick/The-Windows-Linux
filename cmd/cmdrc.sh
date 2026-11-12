# shellcheck shell=bash
# shellcheck disable=SC2164,SC2294,SC2033   # cd/return bewusst über $? ; eval nur für die generierten Wrapper-Funktionen
# ============================================================================
#  TheWindowsLinux – "Eingabeaufforderung"
#  cmd.exe-artiges Terminal-Overlay für die bash
# ============================================================================
#  Laden:
#    * als eigene Shell:     cmd            (bash --rcfile .../cmdrc.sh -i)
#    * in jeder bash:        . /pfad/zu/cmdrc.sh   (install.sh --cmd-everywhere)
#
#  Es werden nur Funktionen/Aliase definiert – die normale bash bleibt darunter
#  vollständig erhalten (ls, grep, apt, ... funktionieren weiterhin).
#  Windows-Pfade wie C:\Users\name\Dokumente werden transparent übersetzt.
#  Sprache: Deutsch, wenn LANG/LC_ALL mit "de" beginnt, sonst Englisch.
# ============================================================================

# Nur in interaktiven Shells aktiv werden
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

# Persönliche bashrc laden (PATH, Aliase, Prompt-Farben des Benutzers), wenn wir
# als --rcfile gestartet wurden und nicht selbst aus der ~/.bashrc kommen.
if [ -z "${WIN7_CMD_FROM_BASHRC:-}" ] && [ -z "${WIN7_CMD_LOADED:-}" ] && [ -f "$HOME/.bashrc" ]; then
    # shellcheck disable=SC1091
    WIN7_CMD_SOURCING_BASHRC=1 . "$HOME/.bashrc"
    unset WIN7_CMD_SOURCING_BASHRC
fi
[ -n "${WIN7_CMD_SOURCING_BASHRC:-}" ] && return 0
WIN7_CMD_LOADED=1
export WIN7_CMD=1

# Aliase aus der .bashrc (z. B. alias ls='ls --color=auto' oder unter Debian/Mint alias dir=...)
# würden beim Einlesen der folgenden Funktionsdefinitionen expandiert und Syntaxfehler auslösen;
# ein Syntaxfehler bricht das Laden dieser Datei ab, dann fehlen alle Windows-Befehle.
# Darum ist die Alias-Expansion bis zum Dateiende aus (dort wird sie wieder eingeschaltet).
shopt -u expand_aliases
unalias dir 2>/dev/null     # Windows-DIR ersetzt "dir" vollständig

# ----------------------------------------------------------------------------
#  Grundeinstellungen
# ----------------------------------------------------------------------------
WIN7_DATADIR="${WIN7_DATADIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
case "${WIN7_STYLE:-retro}" in
    aero) WIN7_VERSION="6.1.7601" ;;    # Windows-7-Stil
    *)    WIN7_VERSION="4.10.2222" ;;   # Retro-Stil (Windows-98-Ära)
esac
if [ -r "${WIN7_DATADIR:-/nonexistent}/style.conf" ]; then
    WIN7_VERSION="$(sed -n 's/^CMD_VERSION=//p' "$WIN7_DATADIR/style.conf" 2>/dev/null)"
    [ -n "$WIN7_VERSION" ] || WIN7_VERSION="4.10.2222"
fi
WIN7_TITLE="${WIN7_TITLE:-Eingabeaufforderung}"
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    de*) WIN7_LANG=de ;;
    *)   WIN7_LANG=en; WIN7_TITLE="${WIN7_TITLE_EN:-Command Prompt}" ;;
esac

# Windows-übliche Variablen für die %NAME%-Erweiterung (nur Shell-Variablen, werden nicht exportiert)
# shellcheck disable=SC2034
{
    : "${USERNAME:=${USER:-$(id -un 2>/dev/null)}}"
    USERPROFILE="$HOME"; HOMEDRIVE="C:"; HOMEPATH="\\Users\\${USER:-$USERNAME}"
    COMPUTERNAME="${HOSTNAME:-$(hostname 2>/dev/null)}"
    TEMP="${TMPDIR:-/tmp}"; TMP="$TEMP"; APPDATA="$HOME/.config"; LOCALAPPDATA="$HOME/.local/share"
    SystemRoot='C:\Windows'; windir="$SystemRoot"; SystemDrive="C:"; OS="TheWindowsLinux"
}

# Windows ist nicht case-sensitiv: Tab-Vervollständigung ebenfalls nicht
bind 'set completion-ignore-case on' 2>/dev/null
bind 'set show-all-if-ambiguous on' 2>/dev/null
shopt -s nocaseglob 2>/dev/null
shopt -s checkwinsize 2>/dev/null

# ----------------------------------------------------------------------------
#  Hilfsfunktionen
# ----------------------------------------------------------------------------
__w7_t() {  # Übersetzung: __w7_t schlüssel [printf-argumente]
    local k="$1"; shift
    local s
    if [ "$WIN7_LANG" = de ]; then
        case "$k" in
            banner2)      s='(c) 2026 TheWindowsLinux. Alle Rechte vorbehalten.' ;;
            notfound)     s='Der Befehl "%s" ist entweder falsch geschrieben oder\nkonnte nicht gefunden werden.' ;;
            volume)       s=' Volume in Laufwerk %s: hat keine Bezeichnung.' ;;
            volume_label) s=' Volume in Laufwerk %s: ist %s' ;;
            serial)       s=' Volumeseriennummer: %s' ;;
            dirof)        s=' Verzeichnis von %s' ;;
            files)        s='%16s Datei(en), %14s Bytes' ;;
            dirs)         s='%16s Verzeichnis(se), %14s Bytes frei' ;;
            nofile)       s='Datei nicht gefunden' ;;
            nopath)       s='Das System kann den angegebenen Pfad nicht finden.' ;;
            nodrive)      s='Das System kann das angegebene Laufwerk nicht finden.' ;;
            denied)       s='Zugriff verweigert' ;;
            pause)        s='Drücken Sie eine beliebige Taste . . . ' ;;
            ver)          s='TheWindowsLinux [Version %s]' ;;
            kernel)       s='Linux-Kernel %s auf %s' ;;
            date)         s='Aktuelles Datum: %s' ;;
            time)         s='Aktuelle Zeit: %s' ;;
            copied)       s='%8s Datei(en) kopiert.' ;;
            moved)        s='%8s Datei(en) verschoben.' ;;
            syntax)       s='Die Syntax für den Dateinamen, Verzeichnisnamen oder die Datenträgerbezeichnung ist falsch.' ;;
            killed)       s='ERFOLGREICH: Der Prozess mit PID %s wurde beendet.' ;;
            killed_im)    s='ERFOLGREICH: Der Prozess "%s" wurde beendet.' ;;
            nokill)       s='FEHLER: Der Prozess "%s" wurde nicht gefunden.' ;;
            tasklist_hdr) s='Abbildname                     PID Sitzungsname       Sitz.-Nr. Speichernutzung' ;;
            ipcfg)        s='TheWindowsLinux-IP-Konfiguration' ;;
            adapter)      s='Ethernet-Adapter %s:' ;;
            wadapter)     s='Drahtlos-LAN-Adapter %s:' ;;
            ladapter)     s='Loopback-Adapter %s:' ;;
            ipv4)         s='   IPv4-Adresse  . . . . . . . . . . : %s' ;;
            ipv6)         s='   IPv6-Adresse  . . . . . . . . . . : %s' ;;
            mask)         s='   Subnetzmaske  . . . . . . . . . . : %s' ;;
            gw)           s='   Standardgateway . . . . . . . . . : %s' ;;
            mac)          s='   Physische Adresse . . . . . . . . : %s' ;;
            dns)          s='   DNS-Server  . . . . . . . . . . . : %s' ;;
            state)        s='   Medienstatus. . . . . . . . . . . : %s' ;;
            connected)    s='Verbunden' ;;
            disconnected) s='Medium getrennt' ;;
            hostname_l)   s='Hostname:                      %s' ;;
            os_l)         s='Betriebsystemname:             %s' ;;
            osver_l)      s='Betriebsystemversion:          %s' ;;
            kernel_l)     s='Kernel:                        %s' ;;
            arch_l)       s='Systemtyp:                     %s' ;;
            uptime_l)     s='Systemstartzeit:               %s' ;;
            cpu_l)        s='Prozessor(en):                 %s' ;;
            ram_l)        s='Gesamter physischer Speicher:  %s MB' ;;
            freeram_l)    s='Verfügbarer physischer Speicher: %s MB' ;;
            user_l)       s='Registrierter Benutzer:        %s' ;;
            shell_l)      s='Shell:                         %s' ;;
            de_l)         s='Desktop:                       %s' ;;
            disk_l)       s='Systemlaufwerk (C:):           %s frei von %s' ;;
            help_hdr)     s='Eine Liste der am häufigsten verwendeten Befehle:' ;;
            help_more)    s='Weitere Informationen: HELP <Befehl>. Alle Linux-Befehle (ls, grep, apt, ...) bleiben verfügbar. BASH startet eine normale Shell.' ;;
            nohelp)       s='Für diesen Befehl ist keine Hilfe verfügbar. Versuchen Sie "man %s".' ;;
            tree_hdr)     s='Auflistung der Ordnerpfade für Volume C:' ;;
            shutdown_use) s='Verwendung: SHUTDOWN [/s | /r | /l | /h | /a] [/t xx]' ;;
            shutdown_in)  s='Das System wird in %s Sekunden heruntergefahren/neu gestartet. (SHUTDOWN /a bricht ab)' ;;
            net_users)    s='Benutzerkonten für \\\\%s' ;;
            where_none)   s='INFO: Es konnten keine Dateien mit dem angegebenen Muster gefunden werden.' ;;
            choice_p)     s='[J,N]?' ;;
            format_deny)  s='FORMAT ist in TheWindowsLinux deaktiviert. Verwenden Sie gparted oder mkfs (als root) bewusst von Hand.' ;;
            assoc_l)      s='%s=%s  (Standardprogramm: %s)' ;;
            *)            s="$k" ;;
        esac
    else
        case "$k" in
            banner2)      s='(c) 2026 TheWindowsLinux. All rights reserved.' ;;
            notfound)     s="'%s' is not recognized as an internal or external command,\noperable program or batch file." ;;
            volume)       s=' Volume in drive %s has no label.' ;;
            volume_label) s=' Volume in drive %s is %s' ;;
            serial)       s=' Volume Serial Number is %s' ;;
            dirof)        s=' Directory of %s' ;;
            files)        s='%16s File(s) %14s bytes' ;;
            dirs)         s='%16s Dir(s)  %14s bytes free' ;;
            nofile)       s='File Not Found' ;;
            nopath)       s='The system cannot find the path specified.' ;;
            nodrive)      s='The system cannot find the drive specified.' ;;
            denied)       s='Access is denied.' ;;
            pause)        s='Press any key to continue . . . ' ;;
            ver)          s='TheWindowsLinux [Version %s]' ;;
            kernel)       s='Linux kernel %s on %s' ;;
            date)         s='The current date is: %s' ;;
            time)         s='The current time is: %s' ;;
            copied)       s='%8s file(s) copied.' ;;
            moved)        s='%8s file(s) moved.' ;;
            syntax)       s='The filename, directory name, or volume label syntax is incorrect.' ;;
            killed)       s='SUCCESS: The process with PID %s has been terminated.' ;;
            killed_im)    s='SUCCESS: The process "%s" has been terminated.' ;;
            nokill)       s='ERROR: The process "%s" not found.' ;;
            tasklist_hdr) s='Image Name                     PID Session Name        Session#    Mem Usage' ;;
            ipcfg)        s='TheWindowsLinux IP Configuration' ;;
            adapter)      s='Ethernet adapter %s:' ;;
            wadapter)     s='Wireless LAN adapter %s:' ;;
            ladapter)     s='Loopback adapter %s:' ;;
            ipv4)         s='   IPv4 Address. . . . . . . . . . . : %s' ;;
            ipv6)         s='   IPv6 Address. . . . . . . . . . . : %s' ;;
            mask)         s='   Subnet Mask . . . . . . . . . . . : %s' ;;
            gw)           s='   Default Gateway . . . . . . . . . : %s' ;;
            mac)          s='   Physical Address. . . . . . . . . : %s' ;;
            dns)          s='   DNS Servers . . . . . . . . . . . : %s' ;;
            state)        s='   Media State . . . . . . . . . . . : %s' ;;
            connected)    s='Connected' ;;
            disconnected) s='Media disconnected' ;;
            hostname_l)   s='Host Name:                     %s' ;;
            os_l)         s='OS Name:                       %s' ;;
            osver_l)      s='OS Version:                    %s' ;;
            kernel_l)     s='Kernel:                        %s' ;;
            arch_l)       s='System Type:                   %s' ;;
            uptime_l)     s='System Boot Time:              %s' ;;
            cpu_l)        s='Processor(s):                  %s' ;;
            ram_l)        s='Total Physical Memory:         %s MB' ;;
            freeram_l)    s='Available Physical Memory:     %s MB' ;;
            user_l)       s='Registered Owner:              %s' ;;
            shell_l)      s='Shell:                         %s' ;;
            de_l)         s='Desktop:                       %s' ;;
            disk_l)       s='System Drive (C:):             %s free of %s' ;;
            help_hdr)     s='For more information on a specific command, type HELP command-name' ;;
            help_more)    s='All Linux commands (ls, grep, apt, ...) stay available. BASH starts a plain shell.' ;;
            nohelp)       s='This command is not supported by the help utility. Try "man %s".' ;;
            tree_hdr)     s='Folder PATH listing for volume C:' ;;
            shutdown_use) s='Usage: SHUTDOWN [/s | /r | /l | /h | /a] [/t xx]' ;;
            shutdown_in)  s='The system will shut down/restart in %s seconds. (SHUTDOWN /a aborts)' ;;
            net_users)    s='User accounts for \\\\%s' ;;
            where_none)   s='INFO: Could not find files for the given pattern(s).' ;;
            choice_p)     s='[Y,N]?' ;;
            format_deny)  s='FORMAT is disabled in TheWindowsLinux. Use gparted or mkfs (as root) deliberately by hand.' ;;
            assoc_l)      s='%s=%s  (default application: %s)' ;;
            *)            s="$k" ;;
        esac
    fi
    # shellcheck disable=SC2059
    printf "$s\n" "$@"
}

__w7_num() {  # Tausendertrennung: 1234567 → 1.234.567 (de) / 1,234,567 (en)
    local n="${1:-0}" sep='.'
    [ "$WIN7_LANG" = de ] || sep=','
    printf '%s' "$n" | sed -e :a -e "s/\\B[0-9]\\{3\\}\\>/$sep&/;ta"
}

__w7_winpath() {  # Unix-Pfad → Windows-Schreibweise
    local p="${1:-$PWD}"
    case "$p" in
        "$HOME")   p="C:\\Users\\$USER" ;;
        "$HOME"/*) p="C:\\Users\\$USER\\${p#"$HOME"/}" ;;
        /)         p="C:\\" ;;
        /*)        p="C:\\${p#/}" ;;
    esac
    printf '%s' "${p//\//\\}"
}

__w7_expand_vars() {  # %NAME% → Wert (nur gesetzte Variablen; Ergebnis in W7EXP)
    local rest="$1" out="" name val
    while [[ "$rest" =~ ^([^%]*)%([A-Za-z_][A-Za-z0-9_]*)%(.*)$ ]]; do
        out+="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
        case "${name^^}" in
            CD)   val="$(__w7_winpath "$PWD")" ;;
            DATE) val="$(command date '+%d.%m.%Y')" ;;
            TIME) val="$(command date '+%H:%M:%S')" ;;
            *)    if [ -n "${!name+x}" ]; then val="${!name}"; else val="%$name%"; fi ;;
        esac
        out+="$val"
    done
    W7EXP="$out$rest"
}

__w7_unixpath() {  # Windows-Schreibweise → Unix-Pfad (lässt Unix-Pfade unverändert)
    local p="$1"
    case "$p" in *%*%*) __w7_expand_vars "$p"; p="$W7EXP" ;; esac
    case "$p" in
        [A-Za-z]:|[A-Za-z]:/*|[A-Za-z]:\\*|*\\*) p="${p//\\//}" ;;
    esac
    case "$p" in
        [A-Za-z]:/[Uu]sers/"$USER"|[A-Za-z]:/[Uu]sers/"$USER"/*) p="$HOME${p#??/[Uu]sers/"$USER"}" ;;
        [A-Za-z]:/*) p="${p#??}" ;;
        [A-Za-z]:)   p="/" ;;
    esac
    printf '%s' "$p"
}

# Sieht der Aufruf nach Windows aus? (Backslash, Laufwerk, %VAR%, /x-Schalter) – sonst wird Linux-Verhalten nie verändert.
__w7_is_win_call() {
    local a
    for a in "$@"; do
        case "$a" in
            *\\*|[A-Za-z]:|[A-Za-z]:/*|%*%*) return 0 ;;
        esac
        if [ ! -e "$a" ] && [[ "$a" =~ ^/[A-Za-z]$ || "$a" =~ ^/[A-Za-z]:. || "$a" == '/?' ]]; then return 0; fi
    done
    return 1
}

__w7_args() {  # alle Argumente nach Unix-Pfaden übersetzen, /x-Schalter getrennt halten (W7ARGS / W7SWITCHES)
    W7ARGS=(); W7SWITCHES=()
    local a
    for a in "$@"; do
        if [ ! -e "$a" ] && [[ "$a" =~ ^/-?[A-Za-z]{1,2}(:.*)?$ || "$a" == '/?' ]]; then
            W7SWITCHES+=("${a,,}")
        else
            W7ARGS+=("$(__w7_unixpath "$a")")
        fi
    done
}

__w7_has() { local s; for s in "${W7SWITCHES[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

__w7_set_title() { local t="${1//[[:cntrl:]]/}"; printf '\033]0;%s\007' "$t"; }   # Steuerzeichen raus (Terminal-Escape-Injection)

__w7_debug_trap() {
    [ -n "${COMP_LINE:-}" ] && return
    [ "$BASH_COMMAND" = "$PROMPT_COMMAND" ] && return
    case "$BASH_COMMAND" in __w7*|_w7*) return ;; esac
    __w7_set_title "$WIN7_TITLE - ${BASH_COMMAND%% *}"
}

__w7_err() { printf '%s\n' "$*" >&2; return 1; }

# Nicht gefundene Befehle: Groß-/Kleinschreibung ignorieren, .exe abschneiden, Laufwerksbuchstaben
command_not_found_handle() {
    local cmd="$1"; shift
    local lower="${cmd,,}"
    lower="${lower%.exe}"; lower="${lower%.com}"; lower="${lower%.bat}"; lower="${lower%.cmd}"
    case "$lower" in
        c:)  cd / && return 0 ;;
        [a-z]:) __w7_t nodrive >&2; return 1 ;;
        cd\\*|cd/*) cd "${cmd#cd}" "$@"; return $? ;;
        cd..*) cd "${cmd#cd}" "$@"; return $? ;;
        cd.*) cd "${cmd#cd}" "$@"; return $? ;;
    esac
    if [ "$lower" != "$cmd" ]; then
        if declare -F "$lower" >/dev/null 2>&1 || alias "$lower" >/dev/null 2>&1 || command -v "$lower" >/dev/null 2>&1; then
            "$lower" "$@"
            return $?
        fi
    fi
    __w7_t notfound "$cmd" >&2
    # Paketvorschläge der Distribution (z. B. Ubuntu: "sudo apt install ...") nicht verlieren
    if [ -x /usr/lib/command-not-found ]; then
        timeout 3 /usr/lib/command-not-found -- "$cmd" 2>&1 | sed -n '1,6p' >&2
    fi
    return 127
}

# ----------------------------------------------------------------------------
#  Readline: Windows-Pfade mit Backslash vor dem Parsen retten
#  (bash würde "C:\Users\user" sonst zu "C:Usersjan" machen)
# ----------------------------------------------------------------------------
# Nur Windows-eigene Befehle bekommen die pauschale Umschreibung (Backslash → "/", " & " → " ; ").
# Bei allen anderen Befehlen werden nur eindeutige Windows-Pfad-Wörter angefasst (C:\x, ..\x, dir\datei).
__w7_win_cmds=" chdir dir copy xcopy robocopy move ren del erase md rd attrib mklink comp fc explorer notepad wordpad mspaint certutil icacls cacls type start "
__w7_re1='^["'"'"']?([A-Za-z]:|\.\.?|%[A-Za-z_][A-Za-z0-9_]*%)\\[A-Za-z0-9_.~%$-]'
__w7_re2='^[A-Za-z0-9_.~%$-]+(\\[A-Za-z0-9_.~%$-]+)+$'

__w7_fix_token() {  # Ergebnis in W7TOK
    W7TOK="$1"
    if [[ "$1" == *\\* ]] && { [[ "$1" =~ $__w7_re1 ]] || [[ "$1" =~ $__w7_re2 ]]; }; then W7TOK="${1//\\//}"; fi
}

__w7_rewrite_line() {
    local line="$READLINE_LINE" first win=0 out="" tok="" ch i n
    [[ "$line" == *\\* || "$line" == *" & "* ]] || return 0
    first="${line%%[[:space:]]*}"; first="${first,,}"; first="${first%.exe}"
    case "$first" in
        cd|cd..|cd/*|'cd\'*) win=1 ;;
        *) [[ "$__w7_win_cmds" == *" $first "* ]] && win=1 ;;
    esac
    if [ $win -eq 1 ]; then
        # "\ " (maskiertes Leerzeichen), "\;" und Ähnliches bleiben unberührt
        line="$(printf '%s' "$line" | sed -E 's#\\([A-Za-z0-9_.~%$-])#/\1#g; s#([A-Za-z]:)\\#\1/#g; s#\\$#/#')"
        # einzelnes " & " trennt Befehle wie in cmd (in bash würde es im Hintergrund starten)
        line="${line//&&/$'\x01'}"; line="${line// & / ; }"; line="${line//$'\x01'/&&}"
    else
        [[ "$line" == *\\* ]] || return 0
        [[ "$line" == *\\ ]] && return 0        # Zeilenfortsetzung unangetastet lassen
        n=${#line}
        for ((i = 0; i < n; i++)); do           # wortweise, ohne Dateinamen-Expansion und ohne Leerzeichen zu verändern
            ch="${line:i:1}"
            if [[ "$ch" == [[:space:]] ]]; then __w7_fix_token "$tok"; out+="$W7TOK$ch"; tok=""; else tok+="$ch"; fi
        done
        __w7_fix_token "$tok"; out+="$W7TOK"
        line="$out"
    fi
    READLINE_LINE="$line"
    READLINE_POINT=${#READLINE_LINE}
}
# Enter (\C-m) UND Zeilenvorschub (\C-j, kommt bei Typeahead/Einfügen an) laufen über die Umschreibung
if [[ $- == *i* ]] && [ -t 0 ]; then
    bind '"\C-x\C-j": accept-line' 2>/dev/null
    bind -x '"\C-x\C-w": __w7_rewrite_line' 2>/dev/null
    bind '"\C-m": "\C-x\C-w\C-x\C-j"' 2>/dev/null
    bind '"\C-j": "\C-x\C-w\C-x\C-j"' 2>/dev/null
fi

# ----------------------------------------------------------------------------
#  Prompt & Titel
# ----------------------------------------------------------------------------
PS1='\n$(__w7_winpath "$PWD")>'
PS2='Mehr? '
# Fenstertitel setzen, ohne ein vorhandenes PROMPT_COMMAND (direnv, History-Sync, ...) zu überschreiben
if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
    PROMPT_COMMAND+=('__w7_set_title "$WIN7_TITLE"')
elif [ -z "${PROMPT_COMMAND:-}" ]; then
    PROMPT_COMMAND='__w7_set_title "$WIN7_TITLE"'
else
    PROMPT_COMMAND="${PROMPT_COMMAND%;}; __w7_set_title \"\$WIN7_TITLE\""
fi
# DEBUG-Trap (zeigt den laufenden Befehl im Titel) nur, wenn nicht schon einer existiert (bash-preexec, starship, ...)
[ -n "$(trap -p DEBUG)" ] || trap '__w7_debug_trap' DEBUG

# ----------------------------------------------------------------------------
#  Kernbefehle
# ----------------------------------------------------------------------------
cls() { printf '\033[2J\033[3J\033[H'; }

cd() {
    local target
    case "${1:-}" in -|-P|-L|-e|-@|--) builtin cd "$@"; return ;; esac    # "cd -" und bash-Optionen
    case "${1,,}" in /d) shift ;; esac
    if [ $# -eq 0 ]; then __w7_winpath "$PWD"; echo; return 0; fi
    target="$(__w7_unixpath "$*")"
    if ! builtin cd -- "$target" 2>/dev/null; then
        if [ -e "$target" ]; then __w7_t denied >&2; else __w7_t nopath >&2; fi
        return 1
    fi
}
chdir() { cd "$@"; }
cd..() { builtin cd ..; }

dir() {
    __w7_args "$@"
    local bare=0 wide=0 recurse=0 all=0 target d
    __w7_has /b && bare=1
    __w7_has /w && wide=1
    __w7_has /s && recurse=1
    __w7_has /a && all=1
    for d in "${W7SWITCHES[@]}"; do case "$d" in /a*) all=1 ;; esac; done
    [ ${#W7ARGS[@]} -eq 0 ] && W7ARGS=(".")
    local first=1
    for target in "${W7ARGS[@]}"; do
        if [ -d "$target" ]; then
            if [ $recurse -eq 1 ]; then
                local sub
                while IFS= read -r -d '' sub; do
                    [ $first -eq 1 ] && { __w7_dir_header "$sub"; first=0; }
                    __w7_dir_one "$sub" $bare $wide $all
                done < <(find "$target" -type d \( -name '.*' -prune -false -o -print0 \) 2>/dev/null)
            else
                [ $first -eq 1 ] && [ $bare -eq 0 ] && { __w7_dir_header "$target"; first=0; }
                __w7_dir_one "$target" $bare $wide $all
            fi
        elif [ -e "$target" ]; then
            [ $first -eq 1 ] && [ $bare -eq 0 ] && { __w7_dir_header "$(dirname "$target")"; first=0; }
            __w7_dir_entry "$target" $bare
        else
            # Muster wie *.txt
            local matches=()
            local IFS=$'\n'
            # shellcheck disable=SC2206
            mapfile -t matches < <(compgen -G "$target" 2>/dev/null)
            unset IFS
            if [ ${#matches[@]} -eq 0 ]; then __w7_t nofile >&2; continue; fi
            [ $first -eq 1 ] && [ $bare -eq 0 ] && { __w7_dir_header "$(dirname "${matches[0]}")"; first=0; }
            local m nf=0 nd=0 bytes=0
            for m in "${matches[@]}"; do
                __w7_dir_entry "$m" $bare
                if [ -d "$m" ]; then nd=$((nd+1)); else nf=$((nf+1)); bytes=$((bytes + $(stat -c %s -- "$m" 2>/dev/null || echo 0))); fi
            done
            [ $bare -eq 0 ] && __w7_dir_footer "$(dirname "${matches[0]}")" $nf $nd $bytes
        fi
    done
}

__w7_dir_header() {
    local abs; abs="$(cd "$1" 2>/dev/null && pwd)"
    local dev label serial
    dev="$(df --output=source "$abs" 2>/dev/null | tail -1)"
    label="$(lsblk -no LABEL "$dev" 2>/dev/null | head -1)"
    serial="$(lsblk -no UUID "$dev" 2>/dev/null | head -1 | tr -d '-' | cut -c1-8 | tr '[:lower:]' '[:upper:]')"
    if [ -n "$label" ]; then __w7_t volume_label C "$label"; else __w7_t volume C; fi
    [ -n "$serial" ] && __w7_t serial "${serial:0:4}-${serial:4:4}"
}

__w7_dir_entry() {  # Datei/Ordner-Zeile
    local f="$1" bare="$2" name date size
    name="$(basename -- "$f")"
    if [ "$bare" = 1 ]; then printf '%s\n' "$name"; return; fi
    date="$(stat -c %y -- "$f" 2>/dev/null)"
    date="$(date -d "$date" '+%d.%m.%Y  %H:%M' 2>/dev/null || echo "??.??.????  ??:??")"
    if [ -d "$f" ]; then
        printf '%s    <DIR>          %s\n' "$date" "$name"
    else
        size="$(stat -c %s -- "$f" 2>/dev/null || echo 0)"
        printf '%s %17s %s\n' "$date" "$(__w7_num "$size")" "$name"
    fi
}

__w7_dir_footer() {
    local dir="$1" nf="$2" nd="$3" bytes="$4" free
    free="$(df -B1 --output=avail "$dir" 2>/dev/null | tail -1 | tr -d ' ')"
    __w7_t files "$nf" "$(__w7_num "$bytes")"
    __w7_t dirs "$nd" "$(__w7_num "${free:-0}")"
}

__w7_dir_one() {  # ein Verzeichnis auflisten
    local dir="$1" bare="$2" wide="$3" all="$4"
    local abs entries=() e nf=0 nd=0 bytes=0
    abs="$(cd "$dir" 2>/dev/null && pwd)" || { __w7_t nopath >&2; return 1; }
    if [ "$bare" = 0 ]; then echo; __w7_t dirof "$(__w7_winpath "$abs")"; echo; fi
    local IFS=$'\n'
    if [ "$all" = 1 ]; then
        # shellcheck disable=SC2207
        entries=( $(ls -1A --group-directories-first -- "$abs" 2>/dev/null | sort -f) )
    else
        # shellcheck disable=SC2207
        entries=( $(ls -1 -- "$abs" 2>/dev/null | sort -f) )
    fi
    unset IFS
    if [ "$bare" = 0 ] && [ "$wide" = 0 ] && [ "$abs" != "/" ]; then
        __w7_dir_entry "$abs" 0 | sed 's/ [^ ]*$/ ./'
        __w7_dir_entry "$(dirname "$abs")" 0 | sed 's/ [^ ]*$/ ../'
        nd=2
    fi
    if [ "$wide" = 1 ]; then
        local names=()
        for e in "${entries[@]}"; do
            if [ -d "$abs/$e" ]; then names+=("[$e]"); nd=$((nd+1)); else names+=("$e"); nf=$((nf+1)); bytes=$((bytes + $(stat -c %s -- "$abs/$e" 2>/dev/null || echo 0))); fi
        done
        printf '%s\n' "${names[@]}" | column -c "${COLUMNS:-80}" 2>/dev/null || printf '%s\n' "${names[@]}"
    else
        for e in "${entries[@]}"; do
            __w7_dir_entry "$abs/$e" "$bare"
            if [ -d "$abs/$e" ]; then nd=$((nd+1)); else nf=$((nf+1)); bytes=$((bytes + $(stat -c %s -- "$abs/$e" 2>/dev/null || echo 0))); fi
        done
    fi
    [ "$bare" = 0 ] && __w7_dir_footer "$abs" "$nf" "$nd" "$bytes"
    return 0
}

type() {  # Windows TYPE = cat; für Optionen (-t, -a, -p) und Befehlsnamen weiter das bash-builtin
    if [ $# -eq 0 ]; then builtin type; return; fi
    case "$1" in -*) builtin type "$@"; return ;; esac
    __w7_args "$@"
    local f rc=0
    for f in "${W7ARGS[@]}"; do
        if [ -f "$f" ]; then cat -- "$f"
        elif builtin type -t -- "$f" >/dev/null 2>&1; then builtin type -- "$f"
        else __w7_t syntax >&2; rc=1; fi
    done
    return $rc
}

copy() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -lt 1 ] && { __w7_err "Die Syntax für den Befehl ist falsch. / The syntax of the command is incorrect."; return 1; }
    local n dst rc=0
    n=$((${#W7ARGS[@]} - 1)); dst="${W7ARGS[$n]}"
    if [ ${#W7ARGS[@]} -eq 1 ]; then dst="."; n=1; fi
    local opts=(-p)
    __w7_has /y && opts+=(-f)
    __w7_has /-y && opts+=(-i)
    cp "${opts[@]}" -- "${W7ARGS[@]:0:$n}" "$dst" || rc=$?
    [ $rc -eq 0 ] && __w7_t copied "$n"
    return $rc
}
xcopy() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -lt 2 ] && { __w7_err "XCOPY Quelle Ziel [/E /S /Y]"; return 1; }
    cp -a -- "${W7ARGS[@]}" && __w7_t copied "$(find "${W7ARGS[0]}" -type f 2>/dev/null | wc -l)"
}
robocopy() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -lt 2 ] && { __w7_err "ROBOCOPY Quelle Ziel [Datei ...]"; return 1; }
    if command -v rsync >/dev/null 2>&1; then rsync -a --info=progress2 -- "${W7ARGS[0]}/" "${W7ARGS[1]}/"; else cp -a -- "${W7ARGS[0]}/." "${W7ARGS[1]}/"; fi
}
move() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -lt 2 ] && { __w7_err "MOVE Quelle Ziel"; return 1; }
    local n=$((${#W7ARGS[@]} - 1))
    local opts=()
    __w7_has /y && opts+=(-f)
    mv "${opts[@]}" -- "${W7ARGS[@]}" && __w7_t moved "$n"
}
ren() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -ne 2 ] && { __w7_err "REN alt neu"; return 1; }
    mv -- "${W7ARGS[0]}" "$(dirname -- "${W7ARGS[0]}")/$(basename -- "${W7ARGS[1]}")"
}
rename() {   # Windows: rename alt neu · Linux (Perl/util-linux rename): s/x/y/, Optionen, mehrere Dateien → echtes Programm
    if [ -n "$(type -P rename)" ] && { [ $# -ne 2 ] || [[ "$1" == -* || "$1" =~ ^(s|y|tr)/ ]]; }; then command rename "$@"; else ren "$@"; fi
}
del() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -eq 0 ] && { __w7_err "DEL Datei [...] [/Q /F /S /P]"; return 1; }
    local opts=() f rc=0
    __w7_has /p && opts+=(-i)
    __w7_has /f && opts+=(-f)
    for f in "${W7ARGS[@]}"; do
        if [ -d "$f" ]; then
            # DEL ordner  →  Dateien darin löschen (wie Windows), Ordner bleibt
            if __w7_has /q; then find "$f" -maxdepth 1 -type f -exec rm "${opts[@]}" -- {} + ; else
                printf '%s\\*, ' "$(__w7_winpath "$(cd "$f" && pwd)")"
                read -r -p "$( [ "$WIN7_LANG" = de ] && echo 'Sind Sie sicher (J/N)? ' || echo 'Are you sure (Y/N)? ')" ans
                case "${ans,,}" in j|y|ja|yes) find "$f" -maxdepth 1 -type f -exec rm "${opts[@]}" -- {} + ;; esac
            fi
            __w7_has /s && find "$f" -mindepth 2 -type f -exec rm "${opts[@]}" -- {} +
        elif [ -e "$f" ]; then
            rm "${opts[@]}" -- "$f" || rc=1
        else
            # Muster
            local matched=0 m
            for m in $f; do [ -e "$m" ] && { rm "${opts[@]}" -- "$m" || rc=1; matched=1; }; done
            [ $matched -eq 0 ] && { __w7_t nofile >&2; rc=1; }
        fi
    done
    return $rc
}
erase() { del "$@"; }
md() { __w7_args "$@"; command mkdir -p -- "${W7ARGS[@]}"; }
mkdir() { if __w7_is_win_call "$@"; then md "$@"; else command mkdir "$@"; fi; }
rd() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -eq 0 ] && { __w7_err "RD Verzeichnis [/S /Q]"; return 1; }
    if __w7_has /s; then
        if __w7_has /q; then rm -rf -- "${W7ARGS[@]}"; else rm -rI -- "${W7ARGS[@]}"; fi
    else
        command rmdir -- "${W7ARGS[@]}"
    fi
}
rmdir() { if __w7_is_win_call "$@"; then rd "$@"; else command rmdir "$@"; fi; }
mklink() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -ne 2 ] && { __w7_err "MKLINK [/D] Link Ziel"; return 1; }
    ln -s -- "${W7ARGS[1]}" "${W7ARGS[0]}" && printf 'Link %s <<===>> %s\n' "${W7ARGS[0]}" "${W7ARGS[1]}"
}
attrib() {
    __w7_args "$@"
    [ ${#W7ARGS[@]} -eq 0 ] && W7ARGS=(*)
    local f a
    for f in "${W7ARGS[@]}"; do
        [ -e "$f" ] || continue
        a="A"
        [ -w "$f" ] || a="${a}R"
        case "$(basename -- "$f")" in .*) a="${a}H" ;; esac
        printf '%-6s %s\n' "$a" "$(__w7_winpath "$(readlink -f -- "$f")")"
    done
}
tree() {
    local a
    for a in "$@"; do        # Linux-tree-Optionen (-L, -a, -I ...) gehen unverändert an das echte Programm
        case "$a" in -*) [ -n "$(type -P tree)" ] && { command tree "$@"; return; } ;; esac
    done
    __w7_args "$@"
    local d="${W7ARGS[0]:-.}"
    __w7_t tree_hdr
    __w7_winpath "$(builtin cd "$d" && pwd)"; echo
    if [ -n "$(type -P tree)" ]; then
        local o=(-d --noreport)
        __w7_has /f && o=(--noreport)
        __w7_has /a || o+=(--charset=utf8)
        command tree "${o[@]}" -- "$d" | tail -n +2
    else
        command find "$d" -mindepth 1 \( -name '.*' -prune \) -o -print 2>/dev/null | sed -e "s|^$d/||" -e 's|[^/]*/|   |g' -e 's|^\(\s*\)\([^ ]\)|\1├───\2|'
    fi
}
more() { if [ $# -eq 0 ]; then command more; elif __w7_is_win_call "$@"; then __w7_args "$@"; command more -- "${W7ARGS[@]}"; else command more "$@"; fi; }
comp() { __w7_args "$@"; diff -- "${W7ARGS[@]}" && echo "OK"; }
fc() { if [ $# -ge 2 ] && [[ "$1" != -* ]]; then comp "$@"; else builtin fc "$@"; fi; }   # fc -l usw. = bash-History
find() {  # Windows-FIND (Textsuche) – echte find-Aufrufe (Pfad/Option zuerst) werden durchgereicht
    case "$1" in
        ""|-*|.|..|/*|~*) command find "$@"; return ;;
    esac
    [ -d "$1" ] && { command find "$@"; return; }
    local pattern="$1"; shift
    local ic=() cnt=0
    while [ $# -gt 0 ]; do case "${1,,}" in /i) ic=(-i); shift ;; /c) cnt=1; shift ;; /v) ic+=(-v); shift ;; /n) ic+=(-n); shift ;; *) break ;; esac; done
    __w7_args "$@"
    if [ $cnt -eq 1 ]; then grep -c "${ic[@]}" -- "$pattern" "${W7ARGS[@]}"; else grep "${ic[@]}" -- "$pattern" "${W7ARGS[@]}"; fi
}
findstr() {
    local opts=() a
    while [ $# -gt 0 ]; do
        case "${1,,}" in
            /i) opts+=(-i) ;; /n) opts+=(-n) ;; /s) opts+=(-r) ;; /c:*) opts+=(-e "${1#/?:}") ;; /v) opts+=(-v) ;; /r) ;; /l) opts+=(-F) ;; /m) opts+=(-l) ;; /b) ;; /e) ;;
            *) break ;;
        esac
        shift
    done
    __w7_args "$@"
    grep --color=auto "${opts[@]}" -- "${W7ARGS[@]}"
}
where() {
    [ $# -eq 0 ] && { __w7_err "WHERE Muster"; return 2; }
    local c found=0 p
    for c in "$@"; do
        while IFS= read -r p; do printf '%s\n' "$(__w7_winpath "$p")"; found=1; done < <(builtin type -aP -- "${c%.exe}" 2>/dev/null | grep '^/')
    done
    [ $found -eq 1 ] || { __w7_t where_none >&2; return 1; }
}
clip() { if command -v xclip >/dev/null 2>&1; then xclip -selection clipboard; elif command -v xsel >/dev/null 2>&1; then xsel -ib; elif command -v wl-copy >/dev/null 2>&1; then wl-copy; else cat >/dev/null; __w7_err "clip: xclip/xsel/wl-copy fehlt"; fi; }

# ----------------------------------------------------------------------------
#  Konsole / Umgebung
# ----------------------------------------------------------------------------
ver() { __w7_t ver "$WIN7_VERSION"; __w7_t kernel "$(uname -r)" "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")"; }
vol() { __w7_dir_header "${1:-.}"; }
echo.() { builtin echo; }
# echo mit %VAR%-Erweiterung (wie cmd): %USERPROFILE%, %PATH%, %FOO% ...
# Undefinierte Variablen bleiben wörtlich stehen, %% wird zu %.
echo() {   # wie bash-echo (inkl. -n/-e/-E), erweitert zusätzlich %VAR% wie cmd
    local -a opts=()
    while [[ "${1:-}" =~ ^-[neE]+$ ]]; do opts+=("$1"); shift; done
    case "$*" in
        *%*%*) __w7_expand_vars "$*"; builtin echo "${opts[@]}" "$W7EXP" ;;
        *)     builtin echo "${opts[@]}" "$@" ;;
    esac
}
rem() { :; }
pause() { read -r -n1 -s -p "$(__w7_t pause)"; echo; }
title() { WIN7_TITLE="$*"; __w7_set_title "$WIN7_TITLE"; }
timeout() {  # TIMEOUT /T 5  (sonst GNU timeout)
    case "${1,,}" in
        /t) local n="${2:-0}"; printf '%s' "$( [ "$WIN7_LANG" = de ] && printf 'Warten für %s Sekunden, Weiter mit beliebiger Taste ...' "$n" || printf 'Waiting for %s seconds, press a key to continue ...' "$n")"; read -r -t "$n" -n1 -s; echo ;;
        *) command timeout "$@" ;;
    esac
}
color() {
    local hex="${1:-07}" fg bg
    local -a pal=(000000 000080 008000 008080 800000 800080 808000 c0c0c0 808080 0000ff 00ff00 00ffff ff0000 ff00ff ffff00 ffffff)
    hex="${hex,,}"
    [ ${#hex} -eq 1 ] && hex="0$hex"
    bg="${hex:0:1}"; fg="${hex:1:1}"
    bg=$((16#$bg)); fg=$((16#$fg))
    printf '\033]11;#%s\007\033]10;#%s\007' "${pal[$bg]}" "${pal[$fg]}"
}
set() {  # SET → Umgebung, SET X=y → setzen, SET /P X=Prompt → einlesen
    if [ $# -eq 0 ]; then env | sort; return; fi
    case "${1,,}" in
        /p) shift; local kv name prompt; kv="$*"; name="${kv%%=*}"; prompt="${kv#*=}"; read -r -p "$prompt" "${name?}"; export "${name?}"; return ;;
        /a) shift; local kv name expr; kv="$*"; name="${kv%%=*}"; expr="${kv#*=}"; printf -v "${name?}" '%s' "$((expr))"; export "${name?}"; echo "${!name}"; return ;;
        -*|+*) builtin set "$@"; return ;;
    esac
    case "$*" in
        *=*) local kv name val; kv="$*"; name="${kv%%=*}"; val="${kv#*=}"; export "${name?}=$val" ;;
        *)   env | grep -i "^$1" || return 1 ;;
    esac
}
path() {
    if [ $# -eq 0 ]; then printf 'PATH=%s\n' "$PATH"; return; fi
    __w7_args "$@"
    local p
    for p in "${W7ARGS[@]}"; do export PATH="$p:$PATH"; done
}
date() {
    case "${1,,}" in
        ""|/t) __w7_t date "$(command date '+%d.%m.%Y')" ;;
        *) command date "$@" ;;
    esac
}
__w7_time() {   # "time" ist in bash ein Schlüsselwort: Funktion VOR dem Alias definieren, damit hier das Schlüsselwort gilt
    case "${1:-}" in
        ""|/t|/T) __w7_t time "$(command date '+%H:%M:%S,%N' | cut -c1-11)" ;;
        *) time "$@" ;;
    esac
}
alias time='__w7_time'   # "time" ist in bash ein reserviertes Wort
choice() {
    local ans
    read -r -n1 -p "$(__w7_t choice_p)" ans; echo
    case "${ans,,}" in j|y) return 1 ;; *) return 2 ;; esac
}
msg() { shift; command -v notify-send >/dev/null 2>&1 && notify-send "TheWindowsLinux" "$*" || echo "$*"; }
help() {
    if [ $# -gt 0 ]; then
        local c="${1,,}"
        if declare -F "$c" >/dev/null 2>&1; then
            case "$c" in
                dir) echo "DIR [Laufwerk:][Pfad][Dateiname] [/A] [/B] [/S] [/W]" ;;
                cd) echo "CD [/D] [Laufwerk:][Pfad]   |  CD..   |  CD\\" ;;
                copy) echo "COPY [/Y | /-Y] Quelle [Quelle...] Ziel" ;;
                del) echo "DEL [/P] [/F] [/S] [/Q] Namen" ;;
                shutdown) __w7_t shutdown_use ;;
                taskkill) echo "TASKKILL [/F] {/PID Prozess-ID | /IM Abbildname}" ;;
                *) declare -f "$c" | head -3 ;;
            esac
        elif command -v "$c" >/dev/null 2>&1; then man "$c" 2>/dev/null || "$c" --help 2>&1 | head -40
        else __w7_t nohelp "$c"; fi
        return
    fi
    __w7_t help_hdr
    cat <<'EOF'
ASSOC      Zeigt Dateierweiterungszuordnungen an (xdg-mime).
ATTRIB     Zeigt Dateiattribute an.
BASH       Startet eine normale Linux-Shell (ohne Overlay).
CD         Wechselt das Verzeichnis / zeigt es an (auch CD.. und CD\).
CERTUTIL   -hashfile Datei SHA256|MD5 : Prüfsumme berechnen.
CHKDSK     Zeigt Datenträgerbelegung an (df).
CLS        Löscht den Bildschirminhalt.
COLOR      Setzt Vorder- und Hintergrundfarbe (z. B. COLOR 0A).
COPY       Kopiert Dateien.                XCOPY / ROBOCOPY: rekursiv.
DATE/TIME  Zeigt Datum/Uhrzeit an.
DEL/ERASE  Löscht Dateien.                 RD /S: Ordner löschen.
DIR        Listet Dateien und Unterverzeichnisse auf (/B /W /S /A).
DISKPART   Listet Laufwerke (lsblk).
ECHO       Zeigt Meldungen an; ECHO. gibt eine Leerzeile aus.
EXIT       Beendet die Eingabeaufforderung.
EXPLORER   Öffnet den Windows-Explorer (Thunar).   NOTEPAD: Editor.  CALC: Rechner.
FIND       Sucht Text in Dateien.          FINDSTR: Suche mit Mustern (grep).
FC/COMP    Vergleicht zwei Dateien.
GETMAC     Zeigt MAC-Adressen an.
HELP       Zeigt diese Hilfe an.
HOSTNAME   Zeigt den Computernamen an.     WHOAMI: aktueller Benutzer.
IPCONFIG   Zeigt die IP-Konfiguration an (/ALL, /FLUSHDNS).
MD/MKDIR   Erstellt ein Verzeichnis.       RD/RMDIR: entfernt es.
MKLINK     Erstellt eine symbolische Verknüpfung.
MORE       Zeigt Ausgaben seitenweise an.
MOVE       Verschiebt Dateien.             REN/RENAME: benennt um.
NET        NET USER, NET START/STOP Dienst, NET STATISTICS.
NETSTAT    Netzwerkverbindungen (ss).      NSLOOKUP, PING (-t endlos), TRACERT.
PATH       Zeigt/erweitert den Suchpfad.
PAUSE      Wartet auf einen Tastendruck.
SET        Zeigt/setzt Umgebungsvariablen (SET /P, SET /A).
SHUTDOWN   /s herunterfahren, /r neu starten, /l abmelden, /h Ruhezustand, /a abbrechen.
START      Öffnet Datei/Ordner/URL mit Standardprogramm oder startet ein Programm.
SYSTEMINFO Zeigt Systeminformationen an.
TASKLIST   Zeigt laufende Prozesse an.     TASKKILL /PID n /F  bzw. /IM name.
TITLE      Setzt den Fenstertitel.
TREE       Zeigt die Verzeichnisstruktur grafisch an (/F mit Dateien).
TYPE       Zeigt den Inhalt einer Textdatei an.
VER        Zeigt die Versionsnummer an.    VOL: Datenträgerbezeichnung.
WHERE      Zeigt den Pfad eines Programms an.
CONTROL    Systemsteuerung. TASKMGR: Task-Manager. MSCONFIG: Autostart. WINVER: Info.
EOF
    __w7_t help_more
}

# ----------------------------------------------------------------------------
#  System / Prozesse / Netzwerk
# ----------------------------------------------------------------------------
tasklist() {
    local filt=""
    case "${1,,}" in /fi) filt="$2" ;; esac
    __w7_t tasklist_hdr
    echo "========================= ======== ================ =========== ============"
    ps -eo comm:28,pid:8,tty:16,sid:11,rss:12 --sort=pid --no-headers 2>/dev/null | awk -v f="${filt,,}" '
        { name=$1; if (length(name) > 25) name=substr(name,1,25); printf "%-25s %8s %-16s %11s %9s K\n", name, $2, ($3=="?"?"Services":"Console"), $4, $5 }' |
        if [ -n "$filt" ]; then grep -i -- "${filt#*eq }" ; else cat; fi
}
taskkill() {
    local force="" pid="" im="" tree=""
    while [ $# -gt 0 ]; do
        case "${1,,}" in
            /f) force="-9" ;; /t) tree=1 ;; /pid) pid="$2"; shift ;; /im) im="${2%.exe}"; shift ;;
            *) [ -z "$pid" ] && [[ "$1" =~ ^[0-9]+$ ]] && pid="$1" || im="${1%.exe}" ;;
        esac
        shift
    done
    if [ -n "$pid" ]; then
        [ -n "$tree" ] && pkill $force -P "$pid" 2>/dev/null      # /T: auch alle Kindprozesse beenden
        kill $force "$pid" 2>/dev/null && __w7_t killed "$pid" || { __w7_t nokill "$pid" >&2; return 128; }
    elif [ -n "$im" ]; then
        pkill $force -x -- "$im" 2>/dev/null && __w7_t killed_im "$im" || { __w7_t nokill "$im" >&2; return 128; }
    else
        echo "TASKKILL [/F] {/PID Prozess-ID | /IM Abbildname}"; return 1
    fi
}
tskill() { taskkill /pid "$@"; }
systeminfo() {
    local os="" ver="" cpu="" tot="" free="" up=""
    # shellcheck disable=SC1091
    [ -r /etc/os-release ] && { os="$(. /etc/os-release; echo "$PRETTY_NAME")"; ver="$(. /etc/os-release; echo "${VERSION_ID:-rolling}")"; }
    cpu="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
    [ -z "$cpu" ] && cpu="$(uname -m)"
    tot="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"
    free="$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"
    up="$(uptime -s 2>/dev/null || who -b 2>/dev/null | awk '{print $3, $4}')"
    __w7_t hostname_l "$(hostname)"
    __w7_t os_l "TheWindowsLinux ($os)"
    __w7_t osver_l "$WIN7_VERSION Build 7601 ($ver)"
    __w7_t kernel_l "$(uname -sr)"
    __w7_t arch_l "$(uname -m)"
    __w7_t uptime_l "$up"
    __w7_t cpu_l "$(nproc 2>/dev/null || echo 1) x $cpu"
    __w7_t ram_l "$(__w7_num "${tot:-0}")"
    __w7_t freeram_l "$(__w7_num "${free:-0}")"
    __w7_t user_l "$USER"
    __w7_t shell_l "$(basename "${SHELL:-bash}") + TheWindowsLinux cmd overlay"
    __w7_t de_l "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-?}}"
    __w7_t disk_l "$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')" "$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')"
}
winver() { ver; echo; systeminfo | head -4; }
ipconfig() {
    case "${1,,}" in
        /flushdns) command -v resolvectl >/dev/null 2>&1 && resolvectl flush-caches 2>/dev/null; echo "DNS-Cache geleert / DNS Resolver Cache flushed."; return ;;
        /release|/renew) command -v nmcli >/dev/null 2>&1 && nmcli networking off && nmcli networking on; return ;;
    esac
    local all=0; [ "${1,,}" = /all ] && all=1
    echo; __w7_t ipcfg; echo
    if ! command -v ip >/dev/null 2>&1; then
        __w7_t adapter "$(hostname)"; echo
        local a4
        for a4 in $(hostname -I 2>/dev/null); do case "$a4" in *:*) __w7_t ipv6 "$a4" ;; *) __w7_t ipv4 "$a4" ;; esac; done
        echo; return 0
    fi
    local ifc
    local ifp
    for ifp in /sys/class/net/*; do
        ifc="${ifp##*/}"
        local kind="adapter" state ip4 ip6 mask mac gw dns
        case "$ifc" in lo) kind="ladapter" ;; wl*|wifi*) kind="wadapter" ;; esac
        [ "$ifc" = lo ] && [ $all -eq 0 ] && continue
        state="$(cat /sys/class/net/"$ifc"/operstate 2>/dev/null)"
        mac="$(cat /sys/class/net/"$ifc"/address 2>/dev/null | tr 'a-f' 'A-F' | tr ':' '-')"
        ip4="$(ip -o -4 addr show dev "$ifc" 2>/dev/null | awk '{print $4}' | head -1)"
        ip6="$(ip -o -6 addr show dev "$ifc" scope global 2>/dev/null | awk '{print $4}' | head -1)"
        gw="$(ip -4 route show default dev "$ifc" 2>/dev/null | awk '{print $3}' | head -1)"
        __w7_t "$kind" "$ifc"; echo
        if [ -z "$ip4" ] && [ "$state" != up ] && [ "$ifc" != lo ]; then __w7_t state "$(__w7_t disconnected)"; echo; continue; fi
        [ $all -eq 1 ] && [ -n "$mac" ] && __w7_t mac "$mac"
        if [ -n "$ip4" ]; then
            __w7_t ipv4 "${ip4%/*}"
            mask="$(__w7_cidr2mask "${ip4#*/}")"; __w7_t mask "$mask"
        fi
        [ -n "$ip6" ] && __w7_t ipv6 "${ip6%/*}"
        [ -n "$gw" ] && __w7_t gw "$gw"
        if [ $all -eq 1 ]; then
            dns="$(grep -m3 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | paste -sd' ')"
            [ -n "$dns" ] && __w7_t dns "$dns"
        fi
        echo
    done
}
__w7_cidr2mask() {
    local bits="${1:-24}" m="" i
    for i in 1 2 3 4; do
        if [ "$bits" -ge 8 ]; then m+="255"; bits=$((bits-8)); else m+="$((256 - (1 << (8 - bits)) ))"; bits=0; fi
        [ $i -lt 4 ] && m+="."
    done
    printf '%s' "$m"
}
getmac() { local p i; for p in /sys/class/net/*; do i="${p##*/}"; [ "$i" = lo ] && continue; printf '%-16s %s\n' "$i" "$(tr 'a-f' 'A-F' < "$p/address" | tr ':' '-')"; done; }
ping() {   # Linux-Syntax bleibt; Windows-Formen nur wenn eindeutig: "-t" ohne Zahl (endlos), "-n <Zahl>" (Anzahl)
    local -a in=("$@") args=()
    local i n=${#in[@]} a nxt cont=0 count=0 host=0
    for ((i = 0; i < n; i++)); do
        a="${in[i]}"; nxt="${in[i+1]:-}"
        case "$a" in
            -t)       if [[ "$nxt" =~ ^[0-9]+$ ]]; then args+=("$a"); else cont=1; fi ;;
            -n)       if [[ "$nxt" =~ ^[0-9]+$ ]]; then args+=(-c); count=1; else args+=("$a"); fi ;;
            -c|-w|-f) count=1; args+=("$a") ;;
            -*)       args+=("$a") ;;
            *)        host=1; args+=("$a") ;;
        esac
    done
    [ $cont -eq 0 ] && [ $count -eq 0 ] && [ $host -eq 1 ] && args=(-c 4 "${args[@]}")   # Windows pingt standardmäßig 4-mal
    command ping "${args[@]}"
}
tracert() { if command -v traceroute >/dev/null 2>&1; then traceroute "$@"; elif command -v tracepath >/dev/null 2>&1; then tracepath "$@"; else command -v mtr >/dev/null 2>&1 && mtr -rw "$@" || __w7_err "traceroute/tracepath nicht installiert"; fi; }
netstat() {
    if [ $# -gt 0 ]; then
        if [ -n "$(type -P netstat)" ]; then command netstat "$@"; else ss "$@"; fi
    elif command -v ss >/dev/null 2>&1; then ss -tunap 2>/dev/null
    else command netstat; fi
}
net() {
    case "${1,,}" in
        user|users)
            if [ -n "$2" ]; then id "$2" 2>/dev/null; getent passwd "$2"; return; fi
            __w7_t net_users "$(hostname)"; echo "-------------------------------------------------------------------------------"
            getent passwd | awk -F: '($3>=1000 && $3<65534) || $1=="root" {print $1}' | column -c 80 2>/dev/null || getent passwd | awk -F: '$3>=1000 {print $1}'
            ;;
        start) if [ -n "$2" ]; then sudo systemctl start "$2"; else systemctl list-units --type=service --state=running --no-pager; fi ;;
        stop)  [ -n "$2" ] && sudo systemctl stop "$2" || __w7_err "NET STOP Dienst" ;;
        statistics|stats) ip -s link 2>/dev/null || cat /proc/net/dev ;;
        view) command -v smbtree >/dev/null 2>&1 && smbtree -N 2>/dev/null || { avahi-browse -at 2>/dev/null | head -30 || ip neigh; } ;;
        use) mount | grep -E 'cifs|nfs|fuse' || findmnt -t cifs,nfs,nfs4 2>/dev/null || echo "Es sind keine Netzlaufwerke verbunden." ;;
        share) cat /etc/exports 2>/dev/null; command -v smbstatus >/dev/null 2>&1 && smbstatus -S 2>/dev/null ;;
        session) who ;;
        time) command date ;;
        *) if [ $# -gt 0 ] && [ -n "$(type -P net)" ]; then command net "$@"; else echo "NET [ USER | START | STOP | STATISTICS | VIEW | USE | SHARE | SESSION | TIME ]"; fi ;;
    esac
}
sc() {
    case "${1,,}" in
        query)   if [ -n "$2" ]; then systemctl status "$2" --no-pager; else systemctl list-units --type=service --no-pager; fi ;;
        start)   sudo systemctl start "$2" ;;
        stop)    sudo systemctl stop "$2" ;;
        config)  sudo systemctl "$( [ "${3,,}" = "start=auto" ] && echo enable || echo disable)" "$2" ;;
        *) if [ $# -gt 0 ] && [ -n "$(type -P sc)" ]; then command sc "$@"; else echo "SC [query|start|stop|config] Dienst"; fi ;;
    esac
}
chkdsk() { __w7_args "$@"; df -h "${W7ARGS[@]:-/}"; echo; echo "Hinweis/Note: Reparatur = fsck (als root, Laufwerk ausgehängt)."; }
diskpart() { lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT; }
format() { __w7_t format_deny >&2; return 5; }
fsutil() { case "${1,,}" in fsinfo) df -hT ;; *) echo "FSUTIL FSINFO" ;; esac; }
certutil() {
    case "${1,,}" in
        -hashfile)
            local f; f="$(__w7_unixpath "$2")"; local algo="${3:-SHA1}"
            case "${algo,,}" in md5) md5sum -- "$f" ;; sha256) sha256sum -- "$f" ;; sha512) sha512sum -- "$f" ;; *) sha1sum -- "$f" ;; esac ;;
        *) echo "CERTUTIL -hashfile Datei [MD5|SHA1|SHA256|SHA512]" ;;
    esac
}
assoc() {
    local ext="${1:-}" mime app
    [ -z "$ext" ] && { __w7_err "ASSOC .erweiterung"; return 1; }
    mime="$(xdg-mime query filetype "/tmp/x$ext" 2>/dev/null)"
    [ -z "$mime" ] && mime="$(xdg-mime query filetype "$ext" 2>/dev/null)"
    app="$(xdg-mime query default "$mime" 2>/dev/null)"
    __w7_t assoc_l "$ext" "${mime:-?}" "${app:-?}"
}
ftype() { assoc "$@"; }
shutdown() {
    local action="" t=0 a win=0
    [ $# -eq 0 ] && { __w7_t shutdown_use; return 1; }
    # Linux-Syntax (shutdown now, -h now, -r +5, -c ...) geht unverändert an das echte Programm
    for a in "$@"; do case "$a" in /*) win=1 ;; esac; done
    if [ $win -eq 0 ]; then command shutdown "$@"; return; fi
    while [ $# -gt 0 ]; do
        case "${1,,}" in
            /s|/p) action=poweroff ;; /r) action=reboot ;; /l) action=logout ;; /h) action=hibernate ;;
            /a) action=abort ;; /t) t="${2:-0}"; shift ;; /f) ;;
        esac
        shift
    done
    [[ "$t" =~ ^[0-9]+$ ]] || t=0
    case "$action" in
        logout)    xfce4-session-logout --logout 2>/dev/null || loginctl terminate-session "$XDG_SESSION_ID" ;;
        hibernate) systemctl hibernate ;;
        abort)     command shutdown -c 2>/dev/null || sudo shutdown -c ;;
        poweroff|reboot)
            if [ "$t" -gt 0 ]; then __w7_t shutdown_in "$t"; sleep "$t"; fi
            if command -v xfce4-session-logout >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
                [ "$action" = poweroff ] && xfce4-session-logout --halt || xfce4-session-logout --reboot
            else
                systemctl "$action"
            fi ;;
        *) __w7_t shutdown_use ;;
    esac
}
logoff() { shutdown /l; }

# ----------------------------------------------------------------------------
#  Programme (Windows-Namen → Linux-Programme)
# ----------------------------------------------------------------------------
__w7_first_of() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 && { printf '%s' "$c"; return 0; }; done; return 1; }
__w7_gui() {  # Programm abgekoppelt starten
    local prog="$1"; shift
    [ -z "$prog" ] && { __w7_err "Programm nicht installiert / program not installed"; return 1; }
    nohup "$prog" "$@" >/dev/null 2>&1 &
    disown 2>/dev/null
}
explorer() { __w7_args "$@"; __w7_gui "$(__w7_first_of thunar nautilus pcmanfm nemo dolphin caja xdg-open)" "${W7ARGS[@]:-.}"; }
notepad()  { __w7_args "$@"; __w7_gui "$(__w7_first_of "${WIN7_EDITOR_APP:-}" mousepad gedit pluma leafpad xed kate featherpad)" "${W7ARGS[@]}"; }
wordpad()  { __w7_args "$@"; __w7_gui "$(__w7_first_of abiword libreoffice lowriter mousepad)" "${W7ARGS[@]}"; }
calc() { if [ $# -gt 0 ] && [ -n "$(type -P calc)" ]; then command calc "$@"; else __w7_gui "$(__w7_first_of galculator gnome-calculator mate-calc qalculate-gtk kcalc xcalc)"; fi; }
mspaint()  { __w7_args "$@"; __w7_gui "$(__w7_first_of pinta drawing kolourpaint gimp mtpaint)" "${W7ARGS[@]}"; }
control()  { __w7_gui "$(__w7_first_of xfce4-settings-manager gnome-control-center systemsettings)"; }
taskmgr()  { __w7_gui "$(__w7_first_of xfce4-taskmanager gnome-system-monitor ksysguard mate-system-monitor htop)"; }
msconfig() { __w7_gui "$(__w7_first_of xfce4-session-settings)"; }
regedit()  { __w7_gui "$(__w7_first_of dconf-editor xfce4-settings-editor)"; }
devmgmt()  { __w7_gui "$(__w7_first_of hardinfo gnome-device-manager)" || lspci; }
eventvwr() { __w7_gui "$(__w7_first_of gnome-logs ksystemlog)" || journalctl -xe --no-pager | tail -50; }
charmap()  { __w7_gui "$(__w7_first_of gucharmap kcharselect)"; }
snippingtool() { __w7_gui "$(__w7_first_of xfce4-screenshooter gnome-screenshot flameshot spectacle)"; }
magnify()  { __w7_gui "$(__w7_first_of xzoom kmag)"; }
osk()      { __w7_gui "$(__w7_first_of onboard florence)"; }
iexplore() { __w7_args "$@"; __w7_gui "$(__w7_first_of xdg-open firefox chromium)" "${W7ARGS[@]:-about:blank}"; }
mstsc()    { __w7_gui "$(__w7_first_of remmina xfreerdp vinagre)"; }
wmplayer() { __w7_args "$@"; __w7_gui "$(__w7_first_of parole vlc mpv totem)" "${W7ARGS[@]}"; }
sndvol()   { __w7_gui "$(__w7_first_of pavucontrol alsamixer)"; }
wsl()      { command bash --norc -i; }
powershell() { echo "Windows PowerShell ist nicht Teil von TheWindowsLinux – es startet die normale bash."; command bash --norc -i; }
cmd() {
    case "${1,,}" in
        /c) shift; bash --rcfile "${BASH_SOURCE[0]}" -ic "$*" ;;
        /k) shift; bash --rcfile <(cat "${BASH_SOURCE[0]}"; printf '%s\n' "$*") -i ;;
        *)  bash --rcfile "${BASH_SOURCE[0]}" -i ;;
    esac
}
start() {
    local wait=0 a
    [ "${1,,}" = /wait ] && { wait=1; shift; }
    # START "Titel" prog → Titel überspringen
    [ $# -gt 1 ] && [[ "$1" != *.* && "$1" == *" "* ]] && shift
    if [ $# -eq 0 ]; then __w7_gui "$WIN7_DATADIR/bin/win7-terminal"; return; fi
    __w7_args "$@"
    local first="${W7ARGS[0]}"
    case "${first,,}" in
        cmd|cmd.exe) __w7_gui "$WIN7_DATADIR/bin/win7-terminal"; return ;;
        http://*|https://*|mailto:*|www.*) __w7_gui xdg-open "$first"; return ;;
    esac
    if [ -e "$first" ] && [ ! -x "$first" ] || [ -d "$first" ]; then
        __w7_gui xdg-open "$first"
    elif command -v "${first%.exe}" >/dev/null 2>&1; then
        if [ $wait -eq 1 ]; then "${first%.exe}" "${W7ARGS[@]:1}"; else __w7_gui "${first%.exe}" "${W7ARGS[@]:1}"; fi
    elif declare -F "${first,,}" >/dev/null 2>&1; then
        "${first,,}" "${W7ARGS[@]:1}"
    else
        __w7_t notfound "$first" >&2; return 1
    fi
}

# Pfadübersetzung für häufige Linux-Werkzeuge (C:\...-Argumente funktionieren auch dort)
# Nur bei eindeutig Windows-artigen Argumenten (C:\x, ..\x, /s-Schalter) wird übersetzt; sonst unverändert durchgereicht.
for __w7_c in ls cat cp mv rm touch less head tail nano vim vi stat file wc; do
    eval "${__w7_c}() { if __w7_is_win_call \"\$@\"; then __w7_args \"\$@\"; command ${__w7_c} \"\${W7SWITCHES[@]/#\\//-}\" \"\${W7ARGS[@]}\"; else command ${__w7_c} \"\$@\"; fi; }"
done
unset __w7_c

# Alias-Expansion wieder einschalten (war während des Ladens aus, siehe oben)
shopt -s expand_aliases

# Beliebte Tippfehler/Abkürzungen
alias cd.='cd .'
alias c:='cd /'
alias ipconfig.exe='ipconfig'
alias cmd.exe='cmd'
alias cls.='cls'

# ----------------------------------------------------------------------------
#  Banner
# ----------------------------------------------------------------------------
if [ -z "${WIN7_CMD_NO_BANNER:-}" ] && [ -z "${WIN7_CMD_FROM_BASHRC:-}" ]; then
    __w7_t ver "$WIN7_VERSION"
    __w7_t banner2
fi
__w7_set_title "$WIN7_TITLE"
