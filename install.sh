#!/usr/bin/env bash
# install.sh — install solune for your user. No sudo needed.
#
#   ./install.sh                  install or update
#   ./install.sh --dir PATH       keep your wallpapers in PATH (default: ~/.solune-wallpaper)
#   ./install.sh --no-button      don't touch the panel
#   ./install.sh --uninstall      remove solune, keep your settings and pictures
#   ./install.sh --purge          remove solune and its settings (pictures are kept)
#
# Nothing to set up first: change anything later in ~/.solune/solune.conf.

set -uo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOLUNE_HOME="${SOLUNE_HOME:-$HOME/.solune}"
APP_DIR="$SOLUNE_HOME/bin"
CONF="$SOLUNE_HOME/solune.conf"
STATE_DIR="$SOLUNE_HOME/state"
BIN_DIR="$HOME/.local/bin"
DEFAULT_WALL_DIR="$HOME/.solune-wallpaper"
# Where solune 1.0 kept things.
OLD_APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/solune"
OLD_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/solune/solune.conf"
OLD_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/solune"
if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then RUN_DIR="$XDG_RUNTIME_DIR/solune"; else RUN_DIR="/tmp/solune-$UID"; fi

THEME_DIRS=("$HOME/.themes" "$HOME/.local/share/themes" /usr/local/share/themes /usr/share/themes)
ICON_DIRS=("$HOME/.icons" "$HOME/.local/share/icons" /usr/local/share/icons /usr/share/icons)

if [[ -t 1 ]]; then
    pink=$'\e[38;5;211m' green=$'\e[38;5;120m' yellow=$'\e[38;5;222m' dim=$'\e[2m' bold=$'\e[1m' reset=$'\e[0m'
else
    pink="" green="" yellow="" dim="" bold="" reset=""
fi
ok() { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
note() { printf '  %s~%s %s\n' "$yellow" "$reset" "$*"; }
fail() {
    printf '  %s✗ %s%s\n' "$pink" "$*" "$reset" >&2
    exit 1
}

usage() { sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; }

# --------------------------------------------------------------- arguments --

action=install wall_dir="" button=yes
while (($#)); do
    case $1 in
        --dir)
            [[ -n ${2:-} ]] || fail "--dir needs a folder"
            wall_dir=$2
            shift
            ;;
        --dir=*) wall_dir=${1#--dir=} ;;
        --no-button) button=no ;;
        --uninstall) action=uninstall ;;
        --purge) action=purge ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done
if [[ -n $wall_dir ]]; then
    wall_dir=${wall_dir/#\~/$HOME}
    [[ $wall_dir == /* ]] || wall_dir="$PWD/$wall_dir"
fi

# ------------------------------------------------------------ dependencies --

package_names() { # <what> -> package names for this distro
    local what=$1
    if command -v apt-get >/dev/null; then
        case $what in
            genmon) echo xfce4-genmon-plugin ;; imagemagick) echo imagemagick ;; zenity) echo zenity ;;
            gtk) echo python3-gi python3-gi-cairo gir1.2-gtk-3.0 ;; xrandr) echo x11-xserver-utils ;;
        esac
    elif command -v pacman >/dev/null; then
        case $what in
            genmon) echo xfce4-genmon-plugin ;; imagemagick) echo imagemagick ;; zenity) echo zenity ;;
            gtk) echo python-gobject python-cairo gtk3 ;; xrandr) echo xorg-xrandr ;;
        esac
    elif command -v dnf >/dev/null; then
        case $what in
            genmon) echo xfce4-genmon-plugin ;; imagemagick) echo ImageMagick ;; zenity) echo zenity ;;
            gtk) echo python3-gobject python3-cairo gtk3 ;; xrandr) echo xrandr ;;
        esac
    elif command -v zypper >/dev/null; then
        case $what in
            genmon) echo xfce4-panel-plugin-genmon ;; imagemagick) echo ImageMagick ;; zenity) echo zenity ;;
            gtk) echo python3-gobject python3-gobject-cairo typelib-1_0-Gtk-3_0 ;; xrandr) echo xrandr ;;
        esac
    else
        echo "$what"
    fi
}

install_command() {
    if command -v apt-get >/dev/null; then echo "sudo apt install"
    elif command -v pacman >/dev/null; then echo "sudo pacman -S"
    elif command -v dnf >/dev/null; then echo "sudo dnf install"
    elif command -v zypper >/dev/null; then echo "sudo zypper install"
    else echo "install:"
    fi
}

genmon_installed() {
    compgen -G '/usr/lib/*/xfce4/panel/plugins/libgenmon.so' >/dev/null ||
        compgen -G '/usr/lib*/xfce4/panel/plugins/libgenmon.so' >/dev/null ||
        compgen -G '/usr/local/lib*/xfce4/panel/plugins/libgenmon.so' >/dev/null
}

check_deps() {
    command -v xfconf-query >/dev/null || fail "xfconf-query not found. solune is made for the XFCE desktop (｡•́︿•̀｡)"
    local -a missing=() why=()
    genmon_installed || { missing+=(genmon) why+=("the panel button"); }
    command -v magick >/dev/null || command -v convert >/dev/null ||
        { missing+=(imagemagick) why+=("fast, screen-sized wallpapers"); }
    command -v zenity >/dev/null || { missing+=(zenity) why+=("the ▾ menu"); }
    python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk; import cairo' &>/dev/null ||
        { missing+=(gtk) why+=("the fade animation"); }
    command -v xrandr >/dev/null || { missing+=(xrandr) why+=("detecting your screens"); }

    if ((${#missing[@]})); then
        local i pkgs=()
        note "Optional pieces are missing, so a few things won't work yet:"
        for i in "${!missing[@]}"; do
            printf '      %s%s%s → %s\n' "$dim" "$(package_names "${missing[i]}")" "$reset" "${why[i]}"
            read -ra more <<<"$(package_names "${missing[i]}")"
            pkgs+=("${more[@]}")
        done
        printf '    Get them all with:  %s%s %s%s\n' "$bold" "$(install_command)" "${pkgs[*]}" "$reset"
        printf '    then run ./install.sh again.\n'
    else
        ok "All dependencies found"
    fi
}

# ------------------------------------------------------------------ themes --

has_theme() { # <gtk|wm|icon> <name>
    local kind=$1 name=$2 d
    [[ -n $name ]] || return 1
    if [[ $kind == icon ]]; then
        for d in "${ICON_DIRS[@]}"; do [[ -f $d/$name/index.theme ]] && return 0; done
    else
        local sub=gtk-3.0
        [[ $kind == wm ]] && sub=xfwm4
        for d in "${THEME_DIRS[@]}"; do [[ -d $d/$name/$sub ]] && return 0; done
    fi
    return 1
}

# Prints the installed dark (or light) partner of theme <name>, guessing from
# common naming styles: Greybird/Greybird-dark, Arc/Arc-Dark,
# Matcha-light-sea/Matcha-dark-sea, Papirus/Papirus-Dark, ...
sibling() { # <gtk|wm|icon> <name> <dark|light>
    local kind=$1 name=$2 want=$3 c
    local -a cands=()
    [[ -n $name ]] || return 1
    if [[ $want == dark ]]; then
        cands=("${name//light/dark}" "${name//Light/Dark}" "$name-dark" "$name-Dark"
            "${name/-/-dark-}" "${name/-/-Dark-}" "${name%-*}-dark" "${name%-*}-Dark")
    else
        # Strip "-dark" before trying "-light": for icons, "Papirus-Light" is
        # meant for light panels, while "Papirus" is the regular light set.
        local -a strip=("${name/-dark/}" "${name/-Dark/}" "${name/_dark/}" "${name/dark-/}" "${name/Dark-/}")
        if [[ $kind == icon ]]; then
            cands=("${strip[@]}" "${name//Dark/Light}" "${name//dark/light}")
        else
            cands=("${name//dark/light}" "${name//Dark/Light}" "${strip[@]}")
        fi
    fi
    for c in "${cands[@]}"; do
        [[ $c != "$name" ]] && has_theme "$kind" "$c" && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}

# Icon themes the given theme falls back to, in lookup order.
icon_chain() { # <theme> [depth]
    local theme=$1 depth=${2:-0} d inherits="" p
    ((depth > 5)) && return
    echo "$theme"
    for d in "${ICON_DIRS[@]}"; do
        [[ -f $d/$theme/index.theme ]] || continue
        inherits=$(sed -n 's/^Inherits=//p' "$d/$theme/index.theme" | head -n1)
        break
    done
    local -a parents=()
    IFS=, read -ra parents <<<"$inherits"
    for p in "${parents[@]}"; do icon_chain "$p" $((depth + 1)); done
}

icon_available() { # <icon> <theme>
    local t d
    while IFS= read -r t; do
        for d in "${ICON_DIRS[@]}"; do
            [[ -d $d/$t ]] || continue
            [[ -n $(find -L "$d/$t" \( -name "$1.svg" -o -name "$1.png" \) -print -quit 2>/dev/null) ]] && return 0
        done
    done < <({ icon_chain "$2"; echo hicolor; } | awk '!seen[$0]++')
    return 1
}

pick_icon() { # <theme> <candidates...> -> first one the theme has
    local theme=$1 c
    shift
    for c; do icon_available "$c" "$theme" && { echo "$c"; return; }; done
    echo "$1"
}

conf_value() { sed -n "s/^$1=\"\\([^\"]*\\)\".*/\\1/p" "$CONF"; }

set_conf() { # <key> <value>
    local key=$1 val=$2
    val=${val//\\/\\\\}
    val=${val//&/\\&}
    val=${val//|/\\|}
    sed -i "s|^$key=\"[^\"]*\"|$key=\"$val\"|" "$CONF"
}

write_config() {
    local gtk wm icon panel mode other
    gtk=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null)
    wm=$(xfconf-query -c xfwm4 -p /general/theme 2>/dev/null)
    icon=$(xfconf-query -c xsettings -p /Net/IconThemeName 2>/dev/null)
    panel=$(xfconf-query -c xfce4-panel -p /panels/dark-mode 2>/dev/null)
    if [[ ${gtk,,} == *dark* ]]; then mode=DARK other=LIGHT; else mode=LIGHT other=DARK; fi
    local want=${other,,}

    mkdir -p "$SOLUNE_HOME"
    cp "$SRC/solune.conf" "$CONF"
    set_conf WALLPAPER_DIR "${WALL_DIR/#$HOME/\~}"

    # What you use now goes to the current mode; its partners to the other one.
    set_conf "${mode}_GTK_THEME" "$gtk"
    set_conf "${mode}_WM_THEME" "$wm"
    set_conf "${mode}_ICON_THEME" "$icon"
    if [[ $want == dark ]]; then
        set_conf DARK_GTK_THEME "$(sibling gtk "$gtk" dark || echo Adwaita-dark)"
    else
        set_conf LIGHT_GTK_THEME "$(sibling gtk "$gtk" light || echo Adwaita)"
    fi
    set_conf "${other}_WM_THEME" "$(sibling wm "$wm" "$want")"
    set_conf "${other}_ICON_THEME" "$(sibling icon "$icon" "$want")"
    if [[ $panel == @(true|false) ]]; then
        set_conf "${mode}_PANEL_DARK" "$panel"
        [[ $want == dark ]] && set_conf DARK_PANEL_DARK true || set_conf LIGHT_PANEL_DARK false
    fi
    sed -i 's/^\(LIGHT\|DARK\)_PANEL_DARK="\(true\|false\)"/\1_PANEL_DARK=\2/' "$CONF"

    set_conf PANEL_ICON_LIGHT "$(pick_icon "$icon" weather-clear weather-clear-symbolic display-brightness-symbolic)"
    set_conf PANEL_ICON_DARK "$(pick_icon "$icon" weather-clear-night weather-clear-night-symbolic night-light-symbolic)"
    set_conf PANEL_ICON_AUTO "$(pick_icon "$icon" variety-indicator preferences-desktop-wallpaper image-x-generic)"

    ok "Wrote your settings to ${CONF/#$HOME/\~}"
    printf '      %slight: %s · %s · %s%s\n' "$dim" "$(conf_value LIGHT_GTK_THEME)" \
        "$(conf_value LIGHT_WM_THEME)" "$(conf_value LIGHT_ICON_THEME)" "$reset"
    printf '      %sdark:  %s · %s · %s%s\n' "$dim" "$(conf_value DARK_GTK_THEME)" \
        "$(conf_value DARK_WM_THEME)" "$(conf_value DARK_ICON_THEME)" "$reset"
}

# ----------------------------------------------------------------- install --

stop_helper() {
    local out
    [[ -p $RUN_DIR/fade.fifo ]] || return 0
    exec {out}<>"$RUN_DIR/fade.fifo" && printf 'quit\n' >&"$out" && exec {out}>&-
    sleep 0.3
}

# solune 1.0 kept its files in ~/.config, ~/.local/share and ~/.local/state.
# Move the settings and state over to ~/.solune and remove the rest.
migrate_old() {
    local moved=0
    if [[ -f $OLD_CONF && ! -f $CONF ]]; then
        mkdir -p "$SOLUNE_HOME"
        mv "$OLD_CONF" "$CONF" && moved=1
    fi
    if [[ -d $OLD_STATE_DIR ]]; then
        mkdir -p "$STATE_DIR"
        mv -n "$OLD_STATE_DIR"/* "$STATE_DIR"/ 2>/dev/null
        rm -rf "$OLD_STATE_DIR"
        moved=1
    fi
    rmdir "${OLD_CONF%/*}" 2>/dev/null
    if [[ -d $OLD_APP_DIR ]]; then
        rm -rf "$OLD_APP_DIR"
        moved=1
    fi
    ((moved)) && ok "Moved your old solune settings into ${SOLUNE_HOME/#$HOME/\~}"
    return 0
}

has_images() {
    [[ -d $1 ]] && [[ -n $(find -L "$1" -type f -regextype posix-extended \
        -iregex '.*\.(jpe?g|png|webp|bmp|gif|tiff?|svg|jxl|avif)$' -print -quit 2>/dev/null) ]]
}

do_install() {
    printf '\n  %s☀ solune ☾%s  %slight & dark for XFCE, with matching wallpapers%s\n\n' "$pink$bold" "$reset" "$dim" "$reset"
    check_deps

    mkdir -p "$APP_DIR" "$BIN_DIR" || fail "can't create $APP_DIR"
    install -m 755 "$SRC/solune" "$APP_DIR/solune"
    install -m 755 "$SRC/solune-fade" "$APP_DIR/solune-fade"
    install -m 644 "$SRC/solune.conf" "$APP_DIR/solune.conf" # template for `solune config`
    ln -sfn "$APP_DIR/solune" "$BIN_DIR/solune"
    stop_helper # after copying, so whatever restarts it is the new version
    ok "Installed the solune command"
    migrate_old

    # Settings: keep existing ones, only moving the wallpaper folder if asked.
    if [[ -f $CONF ]]; then
        [[ -n $wall_dir ]] && { WALL_DIR=$wall_dir; set_conf WALLPAPER_DIR "${WALL_DIR/#$HOME/\~}"; }
        ok "Kept your settings in ${CONF/#$HOME/\~}"
    else
        WALL_DIR=${wall_dir:-$DEFAULT_WALL_DIR}
        write_config
    fi

    # Wallpaper folders, with a few sample pictures if they're empty.
    local light dark colorful
    { read -r light; read -r dark; read -r colorful; } < <("$APP_DIR/solune" paths)
    [[ -n $light && -n $dark && -n $colorful ]] || fail "couldn't read the wallpaper folders from ${CONF/#$HOME/\~}"
    mkdir -p "$light" "$dark" "$colorful"
    if ! has_images "$light" && ! has_images "$dark" && ! has_images "$colorful"; then
        cp -n "$SRC"/examples/light/* "$light"/ 2>/dev/null
        cp -n "$SRC"/examples/dark/* "$dark"/ 2>/dev/null
        cp -n "$SRC"/examples/colorful/* "$colorful"/ 2>/dev/null
        ok "Added a few sample wallpapers to get you started"
    fi
    ok "Wallpaper folders: ${light/#$HOME/\~}  ${dark/#$HOME/\~}  ${colorful/#$HOME/\~}"

    if python3 "$APP_DIR/solune-fade" check &>/dev/null; then
        ok "Fade animation is on"
    else
        note "Fade animation is off: $(python3 "$APP_DIR/solune-fade" check 2>&1 | tail -n1)"
    fi

    if [[ $button == no ]]; then
        note "Left the panel alone (--no-button). Add the button later with: solune add-button"
    elif genmon_installed; then
        "$APP_DIR/solune" add-button 2>&1 | sed 's/^/    /'
    else
        note "Skipped the panel button (needs xfce4-genmon-plugin). You can still run: solune toggle"
    fi

    if command -v magick >/dev/null || command -v convert >/dev/null; then
        setsid "$APP_DIR/solune" cache </dev/null &>/dev/null &
        ok "Making screen-sized copies of your wallpapers in the background"
    fi

    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        note "$BIN_DIR is not in your PATH. The panel button works anyway; for the terminal,"
        printf '    add this to ~/.bashrc:  export PATH="$HOME/.local/bin:$PATH"\n'
    fi

    printf '\n  %sall done! (ﾉ◕ヮ◕)ﾉ*:･ﾟ✧%s\n' "$pink$bold" "$reset"
    printf '  Click the ☀ on your panel to switch, or the ▾ for Auto and more.\n'
    printf '  Drop your own pictures into the folders above.\n'
    printf '  Settings: %s%s%s  change anything, any time: %ssolune config%s\n\n' \
        "$bold" "${CONF/#$HOME/\~}" "$reset" "$bold" "$reset"
}

do_uninstall() {
    printf '\n  %s☀ solune ☾%s  uninstalling\n\n' "$pink$bold" "$reset"
    local app
    for app in "$APP_DIR/solune" "$OLD_APP_DIR/solune"; do
        [[ -x $app ]] && "$app" uninstall 2>&1 | sed 's/^/    /' && break
    done
    stop_helper
    rm -f "$BIN_DIR/solune"
    rm -rf "$APP_DIR" "$SOLUNE_HOME/resized" "$OLD_APP_DIR" "$RUN_DIR"
    ok "Removed the solune command, the helper and the resized copies"
    if [[ $action == purge ]]; then
        rm -rf "$SOLUNE_HOME" "$OLD_STATE_DIR" "${OLD_CONF%/*}"
        ok "Removed your settings (${SOLUNE_HOME/#$HOME/\~})"
    else
        ok "Kept your settings in ${CONF/#$HOME/\~} (use --purge to remove them too)"
    fi
    printf '\n  %sbye bye (｡•́︿•̀｡)  your pictures were not touched.%s\n\n' "$pink" "$reset"
}

case $action in
    install) do_install ;;
    uninstall | purge) do_uninstall ;;
esac
