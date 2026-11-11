#!/usr/bin/env bash
# TheWindowsLinux – Schritt 5 (optional, nur Systemmodus): Anmeldebildschirm, Bootmenü, Boot-Splash
#   --with-login     LightDM GTK-Greeter im Windows-7-Look
#   --with-grub      GRUB-Hintergrund
#   --with-plymouth  Plymouth-Theme "windows7" (Script-Modul)
# Wird von install.sh gesourct; nutzt lib/common.sh.
set -u

w7_step_login() {
    [ "${W7_WITH_LOGIN:-0}" = 1 ] || return 0
    w7_step "Anmeldebildschirm (LightDM GTK-Greeter)"
    if [ "$W7_MODE" != system ]; then w7_warn "Nur im Systemmodus (--system) möglich."; return 0; fi
    if ! w7_have lightdm; then w7_warn "LightDM nicht installiert – übersprungen."; return 0; fi
    local bg="$W7_LOGIN_WALLPAPER"
    local tmp; tmp="$(mktemp)"
    local aa=true; [ "$W7_AA" = 0 ] && aa=false
    cat > "$tmp" <<EOF
# TheWindowsLinux – LightDM GTK-Greeter im Stil »$W7_STYLE«
[greeter]
background=$bg
theme-name=$W7_GTKTHEME
icon-theme-name=$W7_ICONTHEME
cursor-theme-name=$W7_CURSOR
font-name=$W7_UIFONT $W7_UIFONTSIZE
xft-antialias=$aa
xft-hintstyle=$W7_HINTSTYLE
xft-rgba=$W7_RGBA
position=50%,center 50%,center
panel-position=bottom
indicators=~host;~spacer;~clock;~spacer;~language;~a11y;~session;~power
clock-format=%H:%M
default-user-image=$W7_DATADIR/win7-start.png
hide-user-image=false
round-user-image=true
EOF
    w7_mkdir /etc/lightdm/lightdm-gtk-greeter.conf.d
    w7_install "$tmp" /etc/lightdm/lightdm-gtk-greeter.conf.d/50-thewindowslinux.conf
    w7_track /etc/lightdm/lightdm-gtk-greeter.conf.d/50-thewindowslinux.conf
    rm -f "$tmp"
    # Greeter-Session + Standard-Session auf XFCE
    tmp="$(mktemp)"
    printf '[Seat:*]\ngreeter-session=lightdm-gtk-greeter\nuser-session=xfce\n' > "$tmp"
    w7_mkdir /etc/lightdm/lightdm.conf.d
    w7_install "$tmp" /etc/lightdm/lightdm.conf.d/50-thewindowslinux.conf
    w7_track /etc/lightdm/lightdm.conf.d/50-thewindowslinux.conf
    rm -f "$tmp"
    w7_ok "LightDM konfiguriert (/etc/lightdm/lightdm-gtk-greeter.conf.d/50-thewindowslinux.conf)"
}

w7_step_grub() {
    [ "${W7_WITH_GRUB:-0}" = 1 ] || return 0
    w7_step "GRUB-Hintergrund"
    if [ "$W7_MODE" != system ]; then w7_warn "Nur im Systemmodus (--system) möglich."; return 0; fi
    [ -f /etc/default/grub ] || { w7_warn "/etc/default/grub nicht gefunden – übersprungen."; return 0; }
    local bg="$W7_LOGIN_WALLPAPER"
    local tmp; tmp="$(mktemp)"
    printf '# TheWindowsLinux\nGRUB_BACKGROUND="%s"\nGRUB_COLOR_NORMAL="white/black"\nGRUB_COLOR_HIGHLIGHT="black/light-cyan"\nGRUB_DISTRIBUTOR="TheWindowsLinux"\n' "$bg" > "$tmp"
    w7_mkdir /etc/default/grub.d
    w7_install "$tmp" /etc/default/grub.d/50-thewindowslinux.cfg
    w7_track /etc/default/grub.d/50-thewindowslinux.cfg
    rm -f "$tmp"
    if ! grep -q 'grub.d' /etc/default/grub 2>/dev/null && ! [ -d /etc/default/grub.d ]; then
        w7_warn "Diese Distribution liest /etc/default/grub.d nicht – GRUB_BACKGROUND bitte manuell in /etc/default/grub setzen."
    fi
    if w7_have update-grub; then w7_root update-grub >/dev/null 2>&1 && w7_ok "GRUB aktualisiert."
    elif w7_have grub2-mkconfig; then w7_root grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 && w7_ok "GRUB aktualisiert."
    elif w7_have grub-mkconfig; then w7_root grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 && w7_ok "GRUB aktualisiert."
    fi
}

w7_step_plymouth() {
    [ "${W7_WITH_PLYMOUTH:-0}" = 1 ] || return 0
    w7_step "Plymouth-Boot-Splash"
    if [ "$W7_MODE" != system ]; then w7_warn "Nur im Systemmodus (--system) möglich."; return 0; fi
    if ! w7_have plymouth-set-default-theme && ! w7_have plymouth; then w7_warn "Plymouth nicht installiert – übersprungen."; return 0; fi
    local pdir=/usr/share/plymouth/themes/windows7
    w7_mkdir "$pdir"
    w7_install "$W7_STYLEDIR/icons/$W7_ICONTHEME/128x128/apps/win7-start.png" "$pdir/logo.png"
    local tmp; tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
[Plymouth Theme]
Name=TheWindowsLinux
Description=Windows-7-artiger Startbildschirm (Script-Modul)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/windows7
ScriptFile=/usr/share/plymouth/themes/windows7/windows7.script
EOF
    w7_install "$tmp" "$pdir/windows7.plymouth"
    cat > "$tmp" <<'EOF'
# TheWindowsLinux – Plymouth-Script: schwarzer Hintergrund, pulsierendes Logo, Text "Wird gestartet"
Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);

logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2 - 40);

text.image = Image.Text("TheWindowsLinux wird gestartet ...", 1, 1, 1, 1, "Sans 14");
text.sprite = Sprite(text.image);
text.sprite.SetX(Window.GetWidth() / 2 - text.image.GetWidth() / 2);
text.sprite.SetY(Window.GetHeight() / 2 + logo.image.GetHeight() / 2 + 10);

progress = 0;
fun refresh_callback () {
    progress++;
    opacity = 0.55 + 0.45 * Math.Sin(progress / 12);
    logo.sprite.SetOpacity(opacity);
}
Plymouth.SetRefreshFunction(refresh_callback);

# Passwortabfrage (verschlüsselte Datenträger)
fun display_password_callback (prompt, bullets) {
    prompt_text = "";
    for (i = 0; i < bullets; i++) prompt_text += "*";
    pw.image = Image.Text(prompt + " " + prompt_text, 1, 1, 1, 1, "Sans 12");
    pw.sprite = Sprite(pw.image);
    pw.sprite.SetX(Window.GetWidth() / 2 - pw.image.GetWidth() / 2);
    pw.sprite.SetY(Window.GetHeight() * 0.75);
}
Plymouth.SetDisplayPasswordFunction(display_password_callback);
fun display_normal_callback () { pw.sprite = NULL; }
Plymouth.SetDisplayNormalFunction(display_normal_callback);

fun message_callback (text) {
    msg.image = Image.Text(text, 0.8, 0.8, 0.8, 1, "Sans 10");
    msg.sprite = Sprite(msg.image);
    msg.sprite.SetX(Window.GetWidth() / 2 - msg.image.GetWidth() / 2);
    msg.sprite.SetY(Window.GetHeight() * 0.85);
}
Plymouth.SetMessageFunction(message_callback);
EOF
    w7_install "$tmp" "$pdir/windows7.script"
    rm -f "$tmp"
    w7_track "$pdir"
    if w7_have plymouth-set-default-theme; then
        w7_root plymouth-set-default-theme -R windows7 >/dev/null 2>&1 && w7_ok "Plymouth-Theme »windows7« aktiviert (initramfs neu gebaut)."
    elif w7_have update-alternatives; then
        w7_root update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$pdir/windows7.plymouth" 100 >/dev/null 2>&1
        w7_root update-alternatives --set default.plymouth "$pdir/windows7.plymouth" >/dev/null 2>&1
        w7_have update-initramfs && w7_root update-initramfs -u >/dev/null 2>&1
        w7_ok "Plymouth-Theme »windows7« aktiviert."
    fi
}
