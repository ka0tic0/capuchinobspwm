#!/usr/bin/env bash
# ==============================================================================
#  ARCH LINUX BSPWM AUTOMATED INSTALLER & CONFIGURATION SCRIPT
#  Aesthetics: Catppuccin Mocha
# ==============================================================================
#  Este script automatiza la instalación y configuración completa de un
#  entorno de escritorio BSPWM modular, estético y listo para usar en Arch Linux.
# ==============================================================================

set -eo pipefail

# ------------------------------------------------------------------------------
# 0. DEFINICIÓN DE COLORES Y VARIABLES GLOBALES
# ------------------------------------------------------------------------------
# Paleta ANSI inspirada en Catppuccin Mocha
CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_BASE="\033[38;2;30;30;46m"
CLR_TEXT="\033[38;2;205;214;244m"
CLR_RED="\033[38;2;243;139;168m"      # Error
CLR_GREEN="\033[38;2;166;227;161m"   # Éxito
CLR_YELLOW="\033[38;2;249;226;175m"  # Advertencia / Info
CLR_BLUE="\033[38;2;137;180;250m"    # Acentos
CLR_MAUVE="\033[38;2;203;166;247m"   # Títulos
CLR_CYAN="\033[38;2;148;226;213m"

# Detección del usuario real y directorios destino
if [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER="$(id -un)"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
CONFIG_DIR="$TARGET_HOME/.config"
BIN_DIR="$TARGET_HOME/.local/bin"
PICTURES_DIR="$TARGET_HOME/Pictures"
WALLPAPERS_DIR="$PICTURES_DIR/wallpapers"
BACKUP_DIR="$TARGET_HOME/.config_backup_$(date +%Y%m%d_%H%M%S)"

# ------------------------------------------------------------------------------
# FUNCIONES DE INTERFAZ Y REGISTRO
# ------------------------------------------------------------------------------
print_banner() {
    clear
    echo -e "${CLR_MAUVE}${CLR_BOLD}"
    cat << "EOF"
  ____  ____  ______        ____  __  __   ____       _               
 | __ )/ ___||  _ \ \      / /  \/  | \ |  _ \  ___| |_ _   _ _ __  
 |  _ \\___ \| |_) \ \ /\ / /| |\/| |  \| |_) |/ _ \ __| | | | '_ \ 
 | |_) |___) |  __/ \ V  V / | |  | |   |  __/|  __/ |_| |_| | |_) |
 |____/|____/|_|     \_/\_/  |_|  |_|   |_|    \___|\__|\__,_| .__/ 
                                                              |_|    
    -> Arch Linux Base to Beautiful Catppuccin Mocha BSPWM
EOF
    echo -e "${CLR_RESET}"
    echo -e "${CLR_BLUE}==============================================================================${CLR_RESET}"
    echo -e "${CLR_CYAN} Usuario destino : ${CLR_TEXT}${TARGET_USER}${CLR_RESET}"
    echo -e "${CLR_CYAN} Directorio HOME : ${CLR_TEXT}${TARGET_HOME}${CLR_RESET}"
    echo -e "${CLR_BLUE}==============================================================================${CLR_RESET}\n"
}

log_info() {
    echo -e "${CLR_BLUE}[INFO]${CLR_RESET} ${CLR_TEXT}$1${CLR_RESET}"
}

log_success() {
    echo -e "${CLR_GREEN}[✓ ÉXITO]${CLR_RESET} ${CLR_TEXT}$1${CLR_RESET}"
}

log_warning() {
    echo -e "${CLR_YELLOW}[! AVISO]${CLR_RESET} ${CLR_TEXT}$1${CLR_RESET}"
}

log_error() {
    echo -e "${CLR_RED}[✗ ERROR]${CLR_RESET} ${CLR_TEXT}$1${CLR_RESET}"
}

pause_step() {
    echo ""
    log_info "Paso completado: $1"
    echo -e "${CLR_YELLOW}Presiona ENTER para continuar...${CLR_RESET}"
    read -r
    echo ""
}

# Ejecutar un comando como el usuario normal (no root)
run_as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "$TARGET_USER" "$@"
    else
        "$@"
    fi
}

# Ejecutar un comando con privilegios elevados (sudo/root)
run_as_root() {
    if [ "$(id -u)" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

# Manejador de errores para rollback o aviso
error_handler() {
    local exit_code=$?
    local line_no=$1
    echo ""
    log_error "Ocurrió un error crítico en la línea $line_no (Código de salida: $exit_code)."
    if [ -d "$BACKUP_DIR" ]; then
        log_warning "Los respaldos de tus configuraciones previas están seguros en: $BACKUP_DIR"
    fi
    log_error "La instalación no pudo completarse con éxito."
    exit "$exit_code"
}
trap 'error_handler $LINENO' ERR

# ------------------------------------------------------------------------------
# 1. VERIFICACIÓN INICIAL
# ------------------------------------------------------------------------------
initial_checks() {
    print_banner
    log_info "1. Iniciando verificaciones preliminares..."

    # Verificar que no se intente compilar yay puramente como root sin usuario destino válido
    if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" = "root" ]; then
        log_error "No se recomienda ejecutar este instalador directamente como usuario 'root' puro."
        log_warning "Arch Linux y herramientas AUR (como yay/makepkg) prohíben compilar como root."
        log_warning "Por favor ejecuta el script como tu usuario normal con sudo: './install.sh'"
        exit 1
    fi

    # Verificar privilegios sudo
    if ! command -v sudo &>/dev/null; then
        log_error "'sudo' no está instalado. Instálalo como root: 'pacman -S sudo' y añade tu usuario al grupo wheel."
        exit 1
    fi

    # Verificar conexión a Internet
    log_info "Comprobando conexión a internet..."
    if ping -c 1 -W 3 1.1.1.1 &>/dev/null || curl -s --head https://archlinux.org &>/dev/null; then
        log_success "Conexión a internet verificada con éxito."
    else
        log_error "No se detectó conexión a internet activa. Conéctate a una red antes de continuar."
        exit 1
    fi

    # Actualización del sistema
    log_info "Actualizando base de datos de paquetes y sistema completo (pacman -Syu)..."
    run_as_root pacman -Syu --noconfirm
    log_success "Sistema actualizado correctamente."

    echo ""
    echo -e "${CLR_YELLOW}¿Deseas continuar con la instalación de paquetes y configuración de BSPWM? [S/n]${CLR_RESET}"
    read -r response
    if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
        log_warning "Instalación cancelada por el usuario."
        exit 0
    fi
}

# ------------------------------------------------------------------------------
# 2. INSTALACIÓN DE PAQUETES OFICIALES (PACMAN)
# ------------------------------------------------------------------------------
install_official_packages() {
    log_info "2. Instalando paquetes base requeridos desde repositorios oficiales..."

    local PACKAGES=(
        # Servidor X & utilidades de display
        xorg-server
        xorg-xinit
        xorg-xrandr
        xorg-xsetroot
        xorg-xprop
        xorg-xev

        # Window Manager & Hotkeys
        bspwm
        sxhkd

        # Terminal & Shell Utils
        kitty
        bash-completion

        # Barra, Lanzador & Compositor
        polybar
        rofi
        picom

        # Notificaciones & Capturas
        dunst
        libnotify
        scrot

        # Gestor de fondos de pantalla e imágenes
        feh

        # Gestor de archivos & thumbnails
        thunar
        thunar-volman
        thunar-archive-plugin
        tumbler
        gvfs

        # Red
        networkmanager
        network-manager-applet

        # Audio (Pipewire stack)
        pipewire
        pipewire-pulse
        pipewire-alsa
        wireplumber
        pavucontrol
        alsa-utils

        # Fuentes tipográficas
        ttf-jetbrains-mono-nerd
        noto-fonts
        noto-fonts-emoji
        ttf-font-awesome
        ttf-nerd-fonts-symbols

        # Apariencia y motores GTK
        lxappearance 
        xsettingsd

        # Display Manager
        sddm

        # Utilidades del sistema & compilación
        git
        curl
        wget
        base-devel
        polkit-gnome
        xdg-user-dirs
        bc
        jq
        pacman-contrib
    )

    log_info "Instalando paquetes requeridos via pacman (esto puede tomar unos minutos)..."
    run_as_root pacman -S --needed --noconfirm "${PACKAGES[@]}"
    log_success "Todos los paquetes oficiales se instalaron correctamente."
}

# ------------------------------------------------------------------------------
# 3. GESTOR AUR (YAY) Y PAQUETES OPCIONALES
# ------------------------------------------------------------------------------
install_yay() {
    log_info "3. Verificando gestor AUR (yay)..."

    if command -v yay &>/dev/null; then
        log_success "yay ya se encuentra instalado en el sistema."
    else
        log_info "Instalando yay desde el repositorio oficial de AUR..."
        local YAY_BUILD_DIR="/tmp/yay_build_$$"
        run_as_user mkdir -p "$YAY_BUILD_DIR"
        run_as_user git clone https://aur.archlinux.org/yay.git "$YAY_BUILD_DIR"
        
        # Compilar e instalar como el usuario normal
        (
            cd "$YAY_BUILD_DIR"
            run_as_user makepkg -si --noconfirm
        )
        rm -rf "$YAY_BUILD_DIR"
        log_success "yay ha sido instalado con éxito."
    fi
}

install_optional_packages() {
    echo ""
    log_info "¿Deseas instalar paquetes adicionales y temas de personalización AUR? (Recomendado)"
    echo -e "${CLR_CYAN}Los paquetes opcionales incluyen:${CLR_RESET}"
    echo -e "  - ${CLR_MAUVE}brave-origin${CLR_RESET} (Navegador web rápido y privado)"
    echo -e "  - ${CLR_MAUVE}neovim${CLR_RESET} (Editor de texto moderno)"
    echo -e "  - ${CLR_MAUVE}htop & fastfetch${CLR_RESET} (Monitor del sistema e información estética)"
    echo -e "  - ${CLR_MAUVE}catppuccin-gtk-theme-mocha${CLR_RESET} (Tema GTK oficial Catppuccin Mocha)"
    echo -e "  - ${CLR_MAUVE}tela-circle-icon-theme-nord / tela-circle-icon-theme${CLR_RESET} (Paquete de iconos Tela Circle)"
    echo -e "  - ${CLR_MAUVE}sddm-catppuccin / sddm-silent-theme${CLR_RESET} (Tema Catppuccin para SDDM)"
    echo ""
    echo -e "${CLR_YELLOW}¿Instalar paquetes opcionales? [S/n]${CLR_RESET}"
    read -r opt_response

    if [[ ! "$opt_response" =~ ^([nN][oO]|[nN])$ ]]; then
        local AUR_PKGS=()
        local PAC_PKGS=()

        # Neovim, htop, fastfetch están en repos oficiales
        PAC_PKGS+=(neovim htop fastfetch)

        # AUR packages
        AUR_PKGS+=(
            brave-origin
            catppuccin-gtk-theme-mocha
            tela-circle-icon-theme
        )

        log_info "Instalando utilidades adicionales desde repos oficiales..."
        run_as_root pacman -S --needed --noconfirm "${PAC_PKGS[@]}" || true

        log_info "Instalando temas y paquetes desde AUR via yay..."
        run_as_user yay -S --needed --noconfirm "${AUR_PKGS[@]}" || {
            log_warning "Algunos paquetes opcionales AUR pudieron requerir interacción o fallaron. Se continuará con la configuración."
        }
        log_success "Instalación de paquetes opcionales concluida."
    else
        log_info "Saltando paquetes opcionales a petición del usuario."
    fi
}

# ------------------------------------------------------------------------------
# 4. ESTRUCTURA DE DIRECTORIOS Y BACKUP
# ------------------------------------------------------------------------------
setup_directories_and_backup() {
    log_info "4. Creando estructura de directorios en $TARGET_HOME..."

    local DIRS=(
        "$CONFIG_DIR/bspwm"
        "$CONFIG_DIR/sxhkd"
        "$CONFIG_DIR/polybar"
        "$CONFIG_DIR/polybar/styles"
        "$CONFIG_DIR/picom"
        "$CONFIG_DIR/dunst"
        "$CONFIG_DIR/rofi"
        "$CONFIG_DIR/kitty"
        "$CONFIG_DIR/gtk-3.0"
        "$CONFIG_DIR/gtk-4.0"
        "$BIN_DIR"
        "$WALLPAPERS_DIR"
    )

    # Si existen configuraciones previas, respaldarlas
    local BACKUP_NEEDED=false
    for d in "${DIRS[@]}"; do
        if [ -d "$d" ] && [ "$(ls -A "$d" 2>/dev/null)" ]; then
            BACKUP_NEEDED=true
            break
        fi
    done

    if [ "$BACKUP_NEEDED" = true ]; then
        log_info "Creando respaldo de configuraciones existentes en: $BACKUP_DIR"
        run_as_user mkdir -p "$BACKUP_DIR"
        for conf in bspwm sxhkd polybar picom dunst rofi kitty gtk-3.0 gtk-4.0; do
            if [ -d "$CONFIG_DIR/$conf" ]; then
                run_as_user cp -r "$CONFIG_DIR/$conf" "$BACKUP_DIR/" 2>/dev/null || true
            fi
        done
        log_success "Respaldo completado."
    fi

    # Crear todas las carpetas con propiedad del usuario destino
    for d in "${DIRS[@]}"; do
        run_as_user mkdir -p "$d"
    done

    # Generar directorios estándar XDG
    run_as_user xdg-user-dirs-update || true

    log_success "Directorios inicializados correctamente."
}

# ------------------------------------------------------------------------------
# 5. CONFIGURACIONES DETALLADAS (CATPPUCCIN MOCHA THEMED)
# ------------------------------------------------------------------------------

configure_bspwm() {
    log_info "Configurando BSPWM (~/.config/bspwm/bspwmrc)..."
    local BSPWMRC="$CONFIG_DIR/bspwm/bspwmrc"

    cat << 'EOF' > "$BSPWMRC"
#!/usr/bin/env bash
# ==============================================================================
# BSPWM CONFIGURATION - CATPPUCCIN MOCHA
# ==============================================================================

# --- Variables de Colores Catppuccin Mocha ---
COLOR_BASE="#1e1e2e"
COLOR_SURFACE="#313244"
COLOR_MAUVE="#cba6f7"
COLOR_BLUE="#89b4fa"
COLOR_RED="#f38ba8"
COLOR_TEXT="#cdd6f4"

# --- 1. Autostart de Servicios y Utilidades ---
# Hotkey daemon
pgrep -x sxhkd > /dev/null || sxhkd &

# Compositor (Picom)
killall -q picom
while pgrep -u $UID -x picom >/dev/null; do sleep 0.1; done
picom --config ~/.config/picom/picom.conf -b &

# Notificaciones (Dunst)
killall -q dunst
dunst -config ~/.config/dunst/dunstrc &

# Applet de Red
pgrep -x nm-applet > /dev/null || nm-applet &

# Polkit Authentication Agent
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Gestor de cursor
xsetroot -cursor_name left_ptr &

# Restaurar o aplicar Wallpaper aleatorio
if [ -f "$HOME/.local/bin/random_wallpaper" ]; then
    "$HOME/.local/bin/random_wallpaper" &
fi

# Iniciar Polybar (Multi-monitor)
if [ -f "$HOME/.local/bin/launch_polybar" ]; then
    "$HOME/.local/bin/launch_polybar" &
fi

# --- 2. Configuración de Pantalla y Escritorios (Workspaces) ---
# Detección de monitores
MONITORS=($(xrandr --query | grep " connected" | cut -d" " -f1))
if [ "${#MONITORS[@]}" -gt 0 ]; then
    for monitor in "${MONITORS[@]}"; do
        bspc monitor "$monitor" -d I II III IV
    done
else
    bspc monitor -d I II III IV
fi

# --- 3. Configuración de Ventanas y Gaps ---
bspc config border_width         2
bspc config window_gap           10
bspc config top_padding          32
bspc config bottom_padding       6
bspc config left_padding         6
bspc config right_padding        6

bspc config split_ratio          0.52
bspc config borderless_monocle   true
bspc config gapless_monocle      true
bspc config focus_follows_pointer true
bspc config pointer_follows_focus false
bspc config center_pseudo_tiled  true

# --- 4. Colores de Bordes (Catppuccin Mocha) ---
bspc config normal_border_color   "$COLOR_SURFACE"
bspc config active_border_color   "$COLOR_BASE"
bspc config focused_border_color  "$COLOR_MAUVE"
bspc config presel_feedback_color "$COLOR_BLUE"

# --- 5. Reglas de Ventanas (Window Rules) ---
bspc rule -r *:*
bspc rule -a Pavucontrol state=floating center=true follow=on
bspc rule -a Lxappearance state=floating center=true follow=on
bspc rule -a Thunar state=floating center=true
bspc rule -a Viewnior state=floating center=true
bspc rule -a feh state=floating center=true
bspc rule -a Rofi state=floating center=true
bspc rule -a GParted state=floating center=true
bspc rule -a File-roller state=floating center=true

EOF

    chown "$TARGET_USER:$TARGET_USER" "$BSPWMRC"
    chmod +x "$BSPWMRC"
    log_success "bspwmrc configurado y con permisos de ejecución."
}

configure_sxhkd() {
    log_info "Configurando SXHKD (~/.config/sxhkd/sxhkdrc)..."
    local SXHKDRC="$CONFIG_DIR/sxhkd/sxhkdrc"

    cat << 'EOF' > "$SXHKDRC"
# ==============================================================================
# SXHKD HOTKEY BINDINGS - BSPWM
# Modkey = Super (Windows Key)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. APLICACIONES Y SISTEMA
# ------------------------------------------------------------------------------
# Terminal (Kitty)
super + Return
    kitty

# Cerrar o forzar cierre de ventana
super + q
    bspc node -c
super + shift + q
    bspc node -k

# Recargar bspwm y sxhkd
super + Escape
    bspc wm -r; notify-send "BSPWM" "Configuración recargada"
super + shift + Escape
    pkill -USR1 -x sxhkd; notify-send "SXHKD" "Atajos recargados"

# Bloquear pantalla / Cerrar sesión
super + shift + e
    bspc quit

# ------------------------------------------------------------------------------
# 2. LANZADORES (ROFI)
# ------------------------------------------------------------------------------
# Lanzador de aplicaciones (drun)
super + d
    rofi -show drun -theme ~/.config/rofi/config.rasi

# Ejecutar comandos (run)
super + r
    rofi -show run -theme ~/.config/rofi/config.rasi

# Selector de ventanas activas
super + w
    rofi -show window -theme ~/.config/rofi/config.rasi

# Selector de estilos de Polybar
super + p
    ~/.local/bin/polybar_theme_selector

# Cambiar fondo de pantalla aleatorio
super + b
    ~/.local/bin/random_wallpaper

# ------------------------------------------------------------------------------
# 3. CONTROL DE VENTANAS Y LAYOUTS
# ------------------------------------------------------------------------------
# Alternar layouts (tiled, monocle, fullscreen)
super + t
    bspc node -t tiled
super + m
    bspc node -t monocle
super + f
    bspc node -t fullscreen
super + space
    bspc node -t ~floating

# Navegar entre ventanas (Vim keys: j=abajo, k=arriba, h/l=izq/der o ;)
super + {h,j,k,l}
    bspc node -f {west,south,north,east}
super + {Left,Down,Up,Right}
    bspc node -f {west,south,north,east}

# Mover ventanas de posición
super + shift + {h,j,k,l}
    bspc node -s {west,south,north,east}
super + shift + {Left,Down,Up,Right}
    bspc node -s {west,south,north,east}

# Ajustar Gaps dinámicamente
super + ctrl + h
    bspc config window_gap $(( $(bspc config window_gap) - 2 ))
super + ctrl + l
    bspc config window_gap $(( $(bspc config window_gap) + 2 ))

# ------------------------------------------------------------------------------
# 4. WORKSPACES (ESCRITORIOS 1-4)
# ------------------------------------------------------------------------------
# Cambiar a escritorio {1-4}
super + {1-4}
    bspc desktop -f '^{1-4}'

# Mover ventana a escritorio {1-4}
super + shift + {1-4}
    bspc node -d '^{1-4}' --follow

# ------------------------------------------------------------------------------
# 5. CONTROL MULTIMEDIA Y AUDIO (PIPEWIRE / PACTL)
# ------------------------------------------------------------------------------
XF86AudioRaiseVolume
    pactl set-sink-volume @DEFAULT_SINK@ +5% && ~/.local/bin/notify_volume
XF86AudioLowerVolume
    pactl set-sink-volume @DEFAULT_SINK@ -5% && ~/.local/bin/notify_volume
XF86AudioMute
    pactl set-sink-mute @DEFAULT_SINK@ toggle && ~/.local/bin/notify_volume

# Brillo de pantalla (si aplica)
XF86MonBrightnessUp
    brightnessctl set +10% || xbacklight -inc 10
XF86MonBrightnessDown
    brightnessctl set 10%- || xbacklight -dec 10

# ------------------------------------------------------------------------------
# 6. CAPTURAS DE PANTALLA (SCROT)
# ------------------------------------------------------------------------------
# Pantalla completa
Print
    scrot ~/Pictures/Screenshot_%Y-%m-%d_%H-%M-%S.png -e 'notify-send "Captura" "Guardada en $f"'
# Seleccionar área
super + Print
    scrot -s ~/Pictures/Screenshot_%Y-%m-%d_%H-%M-%S.png -e 'notify-send "Captura de Área" "Guardada en $f"'
EOF

    chown "$TARGET_USER:$TARGET_USER" "$SXHKDRC"
    log_success "sxhkdrc configurado exitosamente."
}

configure_polybar() {
    log_info "Configurando Polybar con 6 estilos modulares (Catppuccin Mocha, Wabri Minimal Nord, Floating, Material, Nordish Mac, Gloom Onedark)..."
    
    # --------------------------------------------------------------------------
    # ESTILO 1: CATPPUCCIN MOCHA (DEFAULT FULL WIDTH)
    # --------------------------------------------------------------------------
    local POLYBAR_CONF="$CONFIG_DIR/polybar/config.ini"

    cat << 'EOF' > "$POLYBAR_CONF"
; ==============================================================================
; POLYBAR CONFIGURATION - CATPPUCCIN MOCHA (DEFAULT)
; ==============================================================================

[colors]
base       = #1e1e2e
mantle     = #181825
crust      = #11111b
text       = #cdd6f4
subtext0   = #a6adc8
surface0   = #313244
surface1   = #45475a
surface2   = #585b70
blue       = #89b4fa
lavender   = #b4befe
sapphire   = #74c7ec
sky        = #89dceb
teal       = #94e2d5
green      = #a6e3a1
yellow     = #f9e2af
peach      = #fab387
maroon     = #eba0ac
red        = #f38ba8
mauve      = #cba6f7
pink       = #f5c2e7
transparent= #00000000

[bar/main]
monitor = ${env:MONITOR:}
width = 100%
height = 30pt
radius = 0
fixed-center = true

background = ${colors.base}
foreground = ${colors.text}

line-size = 2pt
line-color = ${colors.mauve}

padding-left = 1
padding-right = 1
module-margin = 1

separator = |
separator-foreground = ${colors.surface1}

font-0 = "JetBrainsMono Nerd Font:size=10:weight=bold;3"
font-1 = "Font Awesome 6 Free Solid:size=10;3"
font-2 = "Noto Color Emoji:scale=10;3"

modules-left = bspwm xwindow
modules-center = date
modules-right = cpu memory filesystem pulseaudio network battery sysmenu

cursor-click = pointer
cursor-scroll = ns-resize
enable-ipc = true
wm-restack = bspwm

[module/bspwm]
type = internal/bspwm
pin-workspaces = true
label-focused = %name%
label-focused-background = ${colors.surface0}
label-focused-foreground = ${colors.mauve}
label-focused-underline = ${colors.mauve}
label-focused-padding = 2

label-occupied = %name%
label-occupied-foreground = ${colors.blue}
label-occupied-padding = 2

label-urgent = %name%
label-urgent-background = ${colors.red}
label-urgent-foreground = ${colors.base}
label-urgent-padding = 2

label-empty = %name%
label-empty-foreground = ${colors.surface2}
label-empty-padding = 2

[module/xwindow]
type = internal/xwindow
label = %title:0:36:...%
label-foreground = ${colors.subtext0}
label-empty = " Arch Linux BSPWM"
label-empty-foreground = ${colors.surface2}

[module/date]
type = internal/date
interval = 1.0
time = %H:%M
date = %A, %d %b
date-alt = %Y-%m-%d %H:%M:%S
label = "󰃰 %date%  󱑂 %time%"
label-foreground = ${colors.mauve}

[module/pulseaudio]
type = internal/pulseaudio
use-ui-max = true
interval = 5
format-volume = <ramp-volume> <label-volume>
format-volume-foreground = ${colors.green}
label-volume = %percentage%%
label-volume-foreground = ${colors.text}
ramp-volume-0 = 
ramp-volume-1 = 
ramp-volume-2 = 
format-muted = <label-muted>
label-muted = "󰝟 Muted"
label-muted-foreground = ${colors.red}
click-right = pavucontrol

[module/network]
type = internal/network
interface-type = wired,wireless
interval = 3.0
format-connected = <label-connected>
format-connected-foreground = ${colors.blue}
label-connected = "󰤨 %essid%"
format-disconnected = <label-disconnected>
label-disconnected = "󰤭 Disconnected"
label-disconnected-foreground = ${colors.surface2}

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = " "
format-prefix-foreground = ${colors.yellow}
label = %percentage:2%%
label-foreground = ${colors.text}

[module/memory]
type = internal/memory
interval = 2
format-prefix = "󰍛 "
format-prefix-foreground = ${colors.pink}
label = %percentage_used:2%%
label-foreground = ${colors.text}

[module/filesystem]
type = internal/fs
interval = 25
mount-0 = /
label-mounted = "󰋊 %percentage_used%%"
label-mounted-foreground = ${colors.teal}

[module/battery]
type = internal/battery
full-at = 99
low-at = 15
battery = BAT0
adapter = AC
poll-interval = 5
format-charging = <animation-charging> <label-charging>
format-discharging = <ramp-capacity> <label-discharging>
format-full = <ramp-capacity> <label-full>
label-charging = %percentage%%
label-discharging = %percentage%%
label-full = 100%
ramp-capacity-0 = 
ramp-capacity-1 = 
ramp-capacity-2 = 
ramp-capacity-3 = 
ramp-capacity-4 = 
ramp-capacity-foreground = ${colors.green}
animation-charging-0 = 
animation-charging-1 = 
animation-charging-2 = 
animation-charging-3 = 
animation-charging-4 = 
animation-charging-framerate = 750
animation-charging-foreground = ${colors.yellow}

[module/sysmenu]
type = custom/text
label = " ⏻ "
label-foreground = ${colors.red}
label-padding = 1
click-left = ~/.local/bin/powermenu_rofi
EOF

    # --------------------------------------------------------------------------
    # ESTILO 2: WABRI MINIMAL NORD / PILLS THEME
    # Referencia: https://github.com/Wabri/polybar-minimal-nord-theme
    # --------------------------------------------------------------------------
    local POLYBAR_MINIMAL="$CONFIG_DIR/polybar/styles/minimal_nord.ini"
    cat << 'EOF' > "$POLYBAR_MINIMAL"
; ==============================================================================
; POLYBAR STYLE - MINIMAL NORD / CAPSULE PILLS (Inspirado en Wabri)
; ==============================================================================
[colors]
background = #2e3440
background-alt = #3b4252
foreground = #eceff4
foreground-alt = #e5e9f0
nord-blue = #88c0d0
nord-frost = #81a1c1
nord-green = #a3be8c
nord-yellow = #ebcb8b
nord-red = #bf616a
nord-magenta = #b48ead
transparent = #00000000

[bar/main]
monitor = ${env:MONITOR:}
width = 100%
height = 26pt
radius = 0
fixed-center = true

background = ${colors.background}
foreground = ${colors.foreground}

line-size = 2pt
line-color = ${colors.nord-blue}

padding-left = 1
padding-right = 1
module-margin = 0

font-0 = "JetBrainsMono Nerd Font:size=9:weight=bold;3"
font-1 = "Font Awesome 6 Free Solid:size=9;3"

modules-left = bspwm sep-pill xwindow
modules-center = date
modules-right = cpu-pill memory-pill volume-pill battery-pill sysmenu

enable-ipc = true
wm-restack = bspwm

[module/bspwm]
type = internal/bspwm
pin-workspaces = true
label-focused = " %name% "
label-focused-background = ${colors.nord-frost}
label-focused-foreground = ${colors.background}
label-occupied = " %name% "
label-occupied-foreground = ${colors.nord-blue}
label-empty = " %name% "
label-empty-foreground = ${colors.background-alt}

[module/sep-pill]
type = custom/text
label = "  "

[module/xwindow]
type = internal/xwindow
label = " %title:0:30:...% "
label-foreground = ${colors.nord-blue}

[module/date]
type = internal/date
interval = 1.0
time = %H:%M
date = %A %d %b
label = "  %date% - %time% "
label-background = ${colors.background-alt}
label-foreground = ${colors.nord-yellow}

[module/cpu-pill]
type = internal/cpu
interval = 2
label = "  %percentage%% "
label-background = ${colors.background-alt}
label-foreground = ${colors.nord-frost}

[module/memory-pill]
type = internal/memory
interval = 2
label = " 󰍛 %percentage_used%% "
label-background = ${colors.background-alt}
label-foreground = ${colors.nord-magenta}

[module/volume-pill]
type = internal/pulseaudio
label-volume = " 󰕾 %percentage%% "
label-volume-background = ${colors.background-alt}
label-volume-foreground = ${colors.nord-green}
label-muted = " 󰝟 Mute "
label-muted-background = ${colors.background-alt}
label-muted-foreground = ${colors.nord-red}

[module/battery-pill]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = " 󰂄 %percentage%% "
label-charging-background = ${colors.background-alt}
label-charging-foreground = ${colors.nord-green}
label-discharging = " 󰁹 %percentage%% "
label-discharging-background = ${colors.background-alt}
label-discharging-foreground = ${colors.nord-yellow}

[module/sysmenu]
type = custom/text
label = " ⏻ "
label-background = ${colors.nord-red}
label-foreground = ${colors.background}
click-left = ~/.local/bin/powermenu_rofi
EOF

    # --------------------------------------------------------------------------
    # ESTILO 3: FLOATING DOCK CATPPUCCIN
    # --------------------------------------------------------------------------
    local POLYBAR_FLOATING="$CONFIG_DIR/polybar/styles/floating.ini"
    cat << 'EOF' > "$POLYBAR_FLOATING"
; ==============================================================================
; POLYBAR STYLE - FLOATING ROUNDED CATPPUCCIN
; ==============================================================================
[colors]
base       = #1e1e2e
text       = #cdd6f4
surface0   = #313244
surface1   = #45475a
blue       = #89b4fa
green      = #a6e3a1
yellow     = #f9e2af
red        = #f38ba8
mauve      = #cba6f7
transparent= #00000000

[bar/main]
monitor = ${env:MONITOR:}
width = 98%
height = 28pt
offset-x = 1%
offset-y = 6px
radius = 10
fixed-center = true

background = ${colors.base}
foreground = ${colors.text}

border-size = 2pt
border-color = ${colors.surface0}

padding-left = 2
padding-right = 2
module-margin = 1

font-0 = "JetBrainsMono Nerd Font:size=10:weight=bold;3"
font-1 = "Font Awesome 6 Free Solid:size=10;3"

modules-left = bspwm
modules-center = date
modules-right = pulseaudio memory cpu battery sysmenu

enable-ipc = true
wm-restack = bspwm

[module/bspwm]
type = internal/bspwm
pin-workspaces = true
label-focused = %name%
label-focused-background = ${colors.mauve}
label-focused-foreground = ${colors.base}
label-focused-padding = 2

label-occupied = %name%
label-occupied-foreground = ${colors.blue}
label-occupied-padding = 2

label-empty = %name%
label-empty-foreground = ${colors.surface1}
label-empty-padding = 2

[module/date]
type = internal/date
interval = 1.0
time = %H:%M
date = %A, %d %b
label = "󰃰 %date% %time%"
label-foreground = ${colors.yellow}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <label-volume>
label-volume = "󰕾 %percentage%%"
label-volume-foreground = ${colors.green}
label-muted = "󰝟 Mute"
label-muted-foreground = ${colors.red}

[module/cpu]
type = internal/cpu
interval = 2
label = " %percentage%%"
label-foreground = ${colors.blue}

[module/memory]
type = internal/memory
interval = 2
label = "󰍛 %percentage_used%%"
label-foreground = ${colors.mauve}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "󰂄 %percentage%%"
label-discharging = "󰁹 %percentage%%"

[module/sysmenu]
type = custom/text
label = " ⏻"
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu_rofi
EOF

    # --------------------------------------------------------------------------
    # ESTILO 4: MATERIAL BLOCKS THEME
    # Referencia: the-anonymous-raven/polybar-themes (material_theme)
    # --------------------------------------------------------------------------
    local POLYBAR_MATERIAL="$CONFIG_DIR/polybar/styles/material_blocks.ini"
    cat << 'EOF' > "$POLYBAR_MATERIAL"
; ==============================================================================
; POLYBAR STYLE - MATERIAL BLOCKS (the-anonymous-raven/material_theme)
; ==============================================================================
[colors]
bg = #263238
fg = #eceff1
mat-red = #e53935
mat-pink = #d81b60
mat-purple = #8e24aa
mat-blue = #1e88e5
mat-teal = #00897b
mat-green = #43a047
mat-amber = #ffb300
mat-orange = #fb8c00

[bar/main]
monitor = ${env:MONITOR:}
width = 100%
height = 28pt
radius = 0
fixed-center = true
background = ${colors.bg}
foreground = ${colors.fg}

font-0 = "JetBrainsMono Nerd Font:size=10:weight=bold;3"
font-1 = "Font Awesome 6 Free Solid:size=10;3"

modules-left = bspwm title
modules-center = time
modules-right = cpu memory volume sysmenu

enable-ipc = true
wm-restack = bspwm

[module/bspwm]
type = internal/bspwm
label-focused = " %name% "
label-focused-background = ${colors.mat-blue}
label-focused-foreground = ${colors.fg}
label-occupied = " %name% "
label-occupied-background = ${colors.mat-teal}
label-occupied-foreground = ${colors.fg}
label-empty = " %name% "
label-empty-foreground = #78909c

[module/title]
type = internal/xwindow
label = " %title:0:25:...% "
label-foreground = ${colors.fg}

[module/time]
type = internal/date
interval = 1
time = %I:%M %p
date = %a, %d %b
label = "  %date% - %time% "
label-background = ${colors.mat-purple}
label-foreground = ${colors.fg}

[module/cpu]
type = internal/cpu
interval = 2
label = "  %percentage%% "
label-background = ${colors.mat-amber}
label-foreground = #212121

[module/memory]
type = internal/memory
interval = 2
label = " 󰍛 %percentage_used%% "
label-background = ${colors.mat-green}
label-foreground = ${colors.fg}

[module/volume]
type = internal/pulseaudio
label-volume = " 󰕾 %percentage%% "
label-volume-background = ${colors.mat-pink}
label-volume-foreground = ${colors.fg}
label-muted = " 󰝟 MUTE "
label-muted-background = ${colors.mat-red}
label-muted-foreground = ${colors.fg}

[module/sysmenu]
type = custom/text
label = " ⏻ "
label-background = ${colors.mat-red}
label-foreground = ${colors.fg}
click-left = ~/.local/bin/powermenu_rofi
EOF

    # --------------------------------------------------------------------------
    # ESTILO 5: NORDISH MAC THEME
    # Referencia: the-anonymous-raven/polybar-themes (nordish_mac)
    # --------------------------------------------------------------------------
    local POLYBAR_NORDMAC="$CONFIG_DIR/polybar/styles/nordish_mac.ini"
    cat << 'EOF' > "$POLYBAR_NORDMAC"
; ==============================================================================
; POLYBAR STYLE - NORDISH MAC (the-anonymous-raven/nordish_mac)
; ==============================================================================
[colors]
bg = #1f232a
fg = #abb2bf
accent = #81a1c1
frost = #88c0d0
green = #a3be8c
orange = #d08770
red = #bf616a
yellow = #ebcb8b

[bar/main]
monitor = ${env:MONITOR:}
width = 100%
height = 24pt
fixed-center = true
background = ${colors.bg}
foreground = ${colors.fg}
font-0 = "JetBrainsMono Nerd Font:size=9:weight=bold;3"

modules-left = apple bspwm
modules-center = date
modules-right = cpu memory pulseaudio battery power

enable-ipc = true
wm-restack = bspwm

[module/apple]
type = custom/text
label = " 󰀵  "
label-foreground = ${colors.frost}
click-left = rofi -show drun -theme ~/.config/rofi/config.rasi

[module/bspwm]
type = internal/bspwm
label-focused = "● "
label-focused-foreground = ${colors.accent}
label-occupied = "○ "
label-occupied-foreground = ${colors.fg}
label-empty = "· "
label-empty-foreground = #4c566a

[module/date]
type = internal/date
interval = 1
time = %H:%M
date = %a %b %d
label = "%date%  %time%"
label-foreground = ${colors.fg}

[module/cpu]
type = internal/cpu
label = " %percentage%% "
label-foreground = ${colors.yellow}

[module/memory]
type = internal/memory
label = "󰍛 %percentage_used%% "
label-foreground = ${colors.green}

[module/pulseaudio]
type = internal/pulseaudio
label-volume = "󰕾 %percentage%% "
label-volume-foreground = ${colors.frost}
label-muted = "󰝟 0% "
label-muted-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "󰂄 %percentage%% "
label-discharging = "󰁹 %percentage%% "
label-charging-foreground = ${colors.green}
label-discharging-foreground = ${colors.yellow}

[module/power]
type = custom/text
label = "⏻ "
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu_rofi
EOF

    # --------------------------------------------------------------------------
    # ESTILO 6: GLOOM ONEDARK THEME
    # Referencia: the-anonymous-raven/polybar-themes (Gloom-Oned-Theme)
    # --------------------------------------------------------------------------
    local POLYBAR_GLOOM="$CONFIG_DIR/polybar/styles/gloom_onedark.ini"
    cat << 'EOF' > "$POLYBAR_GLOOM"
; ==============================================================================
; POLYBAR STYLE - GLOOM ONEDARK (the-anonymous-raven/Gloom-Oned-Theme)
; ==============================================================================
[colors]
bg = #1e222a
fg = #abb2bf
alt-bg = #282c34
red = #e06c75
green = #98c379
yellow = #e5c07b
blue = #61afef
purple = #c678dd
cyan = #56b6c2

[bar/main]
monitor = ${env:MONITOR:}
width = 100%
height = 28pt
radius = 0
fixed-center = true
background = ${colors.bg}
foreground = ${colors.fg}
line-size = 2pt
line-color = ${colors.blue}
font-0 = "JetBrainsMono Nerd Font:size=10:weight=bold;3"

modules-left = bspwm title
modules-center = date
modules-right = cpu memory volume battery sysmenu

enable-ipc = true
wm-restack = bspwm

[module/bspwm]
type = internal/bspwm
label-focused = %name%
label-focused-foreground = ${colors.blue}
label-focused-underline = ${colors.blue}
label-focused-padding = 2
label-occupied = %name%
label-occupied-foreground = ${colors.purple}
label-occupied-padding = 2
label-empty = %name%
label-empty-foreground = #5c6370
label-empty-padding = 2

[module/title]
type = internal/xwindow
label = " %title:0:30:...%"
label-foreground = ${colors.cyan}

[module/date]
type = internal/date
time = %I:%M %p
date = %a, %d %b
label = "󰃰 %date% %time%"
label-foreground = ${colors.yellow}

[module/cpu]
type = internal/cpu
label = " %percentage%% "
label-foreground = ${colors.red}

[module/memory]
type = internal/memory
label = "󰍛 %percentage_used%% "
label-foreground = ${colors.green}

[module/volume]
type = internal/pulseaudio
label-volume = "󰕾 %percentage%% "
label-volume-foreground = ${colors.blue}
label-muted = "󰝟 Mute "
label-muted-foreground = ${colors.red}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
label-charging = "󰂄 %percentage%% "
label-discharging = "󰁹 %percentage%% "
label-charging-foreground = ${colors.green}

[module/sysmenu]
type = custom/text
label = " ⏻ "
label-foreground = ${colors.red}
click-left = ~/.local/bin/powermenu_rofi
EOF

    chown -R "$TARGET_USER:$TARGET_USER" "$CONFIG_DIR/polybar"
    log_success "6 estilos de Polybar instalados y configurados correctamente."
}

configure_picom() {
    log_info "Configurando Compositor Picom (~/.config/picom/picom.conf)..."
    local PICOM_CONF="$CONFIG_DIR/picom/picom.conf"

    cat << 'EOF' > "$PICOM_CONF"
# ==============================================================================
# PICOM COMPOSITOR CONFIGURATION - CATPPUCCIN MOCHA
# ==============================================================================

# --- Backend y Rendimiento ---
backend = "xrender";
vsync = true;
mark-wmwin-focused = true;
mark-ovredir-focused = true;
detect-rounded-corners = true;
detect-client-opacity = true;
detect-transient = true;
use-damage = true;

# --- Sombras (Shadows) ---
shadow = true;
shadow-radius = 7;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-opacity = 0.5;
shadow-exclude = [
  "name = 'Notification'",
  "class_g = 'Polybar'",
  "class_g ?= 'Notify-osd'",
  "_GTK_FRAME_EXTENTS@"
];

# --- Transparencias y Opacidad ---
active-opacity = 1.0;
inactive-opacity = 0.8;
frame-opacity = 1.0;
inactive-opacity-override = false;

opacity-rule = [
  "85:class_g = 'kitty' && focused",
  "75:class_g = 'kitty' && !focused",
  "90:class_g = 'Rofi'",
  "95:class_g = 'Thunar'",
  "100:class_g = 'Brave-origin'",
  "100:class_g = 'feh'"
];

# --- Esquinas Redondeadas (Corner Radius) ---
corner-radius = 10;
rounded-corners-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "class_g = 'Polybar'"
];

# --- Fading (Transiciones suaves) ---
fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
fade-delta = 5;

EOF

    chown "$TARGET_USER:$TARGET_USER" "$PICOM_CONF"
    log_success "Picom configurado correctamente."
}

configure_dunst() {
    log_info "Configurando Dunst (~/.config/dunst/dunstrc)..."
    local DUNSTRC="$CONFIG_DIR/dunst/dunstrc"

    cat << 'EOF' > "$DUNSTRC"
# ==============================================================================
# DUNST NOTIFICATION DAEMON - CATPPUCCIN MOCHA
# ==============================================================================

[global]
    monitor = 0
    follow = mouse
    width = 320
    height = 100
    origin = top-right
    offset = 12x42
    scale = 0
    notification_limit = 5

    progress_bar = true
    progress_bar_height = 8
    progress_bar_frame_width = 1
    progress_bar_min_width = 150
    progress_bar_max_width = 300

    indicate_hidden = yes
    transparency = 20
    separator_height = 2
    padding = 12
    horizontal_padding = 14
    text_icon_padding = 12
    frame_width = 2
    gap_size = 8

    # Colores base Catppuccin Mocha
    frame_color = "#89b4fa"
    separator_color = frame
    sort = yes
    idle_threshold = 120

    # Fuentes y formato
    font = JetBrainsMono Nerd Font 11
    line_height = 0
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    show_age_threshold = 60
    ellipsize = middle
    corner_radius = 10

    # Iconos
    icon_position = left
    min_icon_size = 24
    max_icon_size = 48

[urgency_low]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#89b4fa"
    timeout = 4

[urgency_normal]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#cba6f7"
    timeout = 6

[urgency_critical]
    background = "#1e1e2e"
    foreground = "#f38ba8"
    frame_color = "#f38ba8"
    timeout = 0
EOF

    chown "$TARGET_USER:$TARGET_USER" "$DUNSTRC"
    log_success "Dunst configurado correctamente."
}

configure_kitty() {
    log_info "Configurando Kitty Terminal (~/.config/kitty/kitty.conf)..."
    local KITTY_CONF="$CONFIG_DIR/kitty/kitty.conf"

    cat << 'EOF' > "$KITTY_CONF"
# ==============================================================================
# KITTY CONFIGURATION - CATPPUCCIN MOCHA
# ==============================================================================

# --- Fuente ---
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        12.0

# --- Ventana y Padding ---
window_padding_width 10
background_opacity   0.85
hide_window_decorations yes
confirm_os_window_close 0

# --- Scrollback & Mouse ---
scrollback_lines 10000
mouse_hide_wait  3.0

# --- Catppuccin Mocha Color Palette ---
foreground            #cdd6f4
background            #1e1e2e
selection_foreground  #1e1e2e
selection_background  #f5e0dc

# Cursor
cursor                #f5e0dc
cursor_text_color     #1e1e2e

# URL
url_color             #f5e0dc

# Border
active_border_color   #b4befe
inactive_border_color #6c7086
bell_border_color     #f9e2af

# Tab bar
active_tab_foreground   #11111b
active_tab_background   #cba6f7
inactive_tab_foreground #cdd6f4
inactive_tab_background #181825

# 16 Terminal Colors
# black
color0 #45475a
color8 #585b70

# red
color1 #f38ba8
color9 #f38ba8

# green
color2  #a6e3a1
color10 #a6e3a1

# yellow
color3  #f9e2af
color11 #f9e2af

# blue
color4  #89b4fa
color12 #89b4fa

# magenta
color5  #cba6f7
color13 #cba6f7

# cyan
color6  #94e2d5
color14 #94e2d5

# white
color7  #bac2de
color15 #a6adc8
EOF

    chown "$TARGET_USER:$TARGET_USER" "$KITTY_CONF"
    log_success "Kitty configurado con Catppuccin Mocha."
}

configure_rofi() {
    log_info "Configurando Rofi Launcher (~/.config/rofi/config.rasi)..."
    local ROFI_CONF="$CONFIG_DIR/rofi/config.rasi"

    cat << 'EOF' > "$ROFI_CONF"
/* ==============================================================================
 * ROFI THEME - CATPPUCCIN MOCHA
 * ============================================================================== */

configuration {
    modi: "drun,run,window";
    lines: 7;
    font: "JetBrainsMono Nerd Font 11";
    show-icons: true;
    icon-theme: "Tela-circle-dark";
    terminal: "kitty";
    drun-display-format: "{icon} {name}";
    location: 0;
    disable-history: false;
    hide-scrollbar: true;
    display-drun: "   Apps ";
    display-run: "   Run ";
    display-window: "   Windows ";
    sidebar-mode: true;
}

* {
    bg-col:  #1e1e2e;
    bg-col-light: #313244;
    border-col: #cba6f7;
    selected-col: #313244;
    blue: #89b4fa;
    fg-col: #cdd6f4;
    fg-col2: #f38ba8;
    grey: #6c7086;

    width: 580;
    font: "JetBrainsMono Nerd Font 11";
}

element-text, element-icon , mode-switcher {
    background-color: inherit;
    text-color:       inherit;
}

window {
    height: 360px;
    border: 2px;
    border-radius: 12px;
    border-color: @border-col;
    background-color: @bg-col;
}

mainbox {
    background-color: @bg-col;
}

inputbar {
    children: [prompt,entry];
    background-color: @bg-col;
    border-radius: 6px;
    padding: 2px;
}

prompt {
    background-color: @blue;
    padding: 6px;
    text-color: @bg-col;
    border-radius: 6px;
    margin: 10px 0px 0px 10px;
}

textbox-prompt-colon {
    expand: false;
    str: ":";
}

entry {
    padding: 6px;
    margin: 10px 10px 0px 10px;
    text-color: @fg-col;
    background-color: @bg-col-light;
    border-radius: 6px;
}

listview {
    border: 0px 0px 0px;
    padding: 6px 0px 0px;
    margin: 10px 10px 0px 10px;
    columns: 1;
    background-color: @bg-col;
}

element {
    padding: 6px;
    background-color: @bg-col;
    text-color: @fg-col;
    border-radius: 6px;
}

element-icon {
    size: 24px;
    margin: 0 8px 0 0;
}

element selected {
    background-color:  @selected-col ;
    text-color: @fg-col2  ;
}

mode-switcher {
    spacing: 0;
}

button {
    padding: 10px;
    background-color: @bg-col-light;
    text-color: @grey;
    vertical-align: 0.5; 
    horizontal-align: 0.5;
}

button selected {
    background-color: @bg-col;
    text-color: @blue;
}
EOF

    chown "$TARGET_USER:$TARGET_USER" "$ROFI_CONF"
    log_success "Rofi configurado correctamente."
}

configure_gtk() {
    log_info "Configurando temas GTK 3 y GTK 4 (~/.config/gtk-*/settings.ini)..."
    
    local GTK_CONTENT="[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Mauve-Dark
gtk-icon-theme-name=Tela-circle-dark
gtk-font-name=JetBrains Mono Nerd Font 11
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
gtk-application-prefer-dark-theme=1
"

    echo "$GTK_CONTENT" > "$CONFIG_DIR/gtk-3.0/settings.ini"
    echo "$GTK_CONTENT" > "$CONFIG_DIR/gtk-4.0/settings.ini"
    chown -R "$TARGET_USER:$TARGET_USER" "$CONFIG_DIR/gtk-3.0" "$CONFIG_DIR/gtk-4.0"
    log_success "Configuraciones GTK generadas."
}

configure_xinit_and_xresources() {
    log_info "Configurando ~/.xinitrc y ~/.Xresources..."

    # ~/.xinitrc
    local XINITRC="$TARGET_HOME/.xinitrc"
    cat << 'EOF' > "$XINITRC"
#!/usr/bin/env bash
# ==============================================================================
# XINITRC - INICIAR BSPWM
# ==============================================================================

# Cargar recursos de X11
[ -f ~/.Xresources ] && xrdb -merge -I$HOME ~/.Xresources

# Cargar configuraciones de usuario
if [ -d /etc/X11/xinit/xinitrc.d ] ; then
    for f in /etc/X11/xinit/xinitrc.d/?*.sh ; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi

# Iniciar BSPWM
exec bspwm
EOF
    chown "$TARGET_USER:$TARGET_USER" "$XINITRC"
    chmod +x "$XINITRC"

    # ~/.Xresources (Colores Catppuccin Mocha para terminales X11)
    local XRESOURCES="$TARGET_HOME/.Xresources"
    cat << 'EOF' > "$XRESOURCES"
! Catppuccin Mocha Xresources
*.foreground: #cdd6f4
*.background: #1e1e2e
*.cursorColor: #f5e0dc

! Black
*.color0: #45475a
*.color8: #585b70

! Red
*.color1: #f38ba8
*.color9: #f38ba8

! Green
*.color2: #a6e3a1
*.color10: #a6e3a1

! Yellow
*.color3: #f9e2af
*.color11: #f9e2af

! Blue
*.color4: #89b4fa
*.color12: #89b4fa

! Magenta
*.color5: #cba6f7
*.color13: #cba6f7

! Cyan
*.color6: #94e2d5
*.color14: #94e2d5

! White
*.color7: #bac2de
*.color15: #a6adc8
EOF
    chown "$TARGET_USER:$TARGET_USER" "$XRESOURCES"

    # Aliases útiles en ~/.bashrc
    local BASHRC="$TARGET_HOME/.bashrc"
    if ! grep -q "BSPWM Custom Aliases" "$BASHRC" 2>/dev/null; then
        cat << 'EOF' >> "$BASHRC"

# --- BSPWM Custom Aliases ---
alias ll='ls -la --color=auto'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias update='sudo pacman -Syu'
alias yayupdate='yay -Syu'
alias fast='fastfetch'
alias polyreload='~/.local/bin/launch_polybar'
alias wall='~/.local/bin/random_wallpaper'
EOF
        chown "$TARGET_USER:$TARGET_USER" "$BASHRC"
    fi

    log_success ".xinitrc, .Xresources y .bashrc actualizados."
}

# ------------------------------------------------------------------------------
# 6. SCRIPTS PERSONALIZADOS EN ~/.local/bin/
# ------------------------------------------------------------------------------
setup_custom_scripts() {
    log_info "6. Creando scripts de utilidad en $BIN_DIR..."

    # Script: launch_polybar (Detecta monitores y lanza el estilo activo o default)
    local LAUNCH_POLY="$BIN_DIR/launch_polybar"
    cat << 'EOF' > "$LAUNCH_POLY"
#!/usr/bin/env bash
# Terminar instancias previas de Polybar
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.1; done

# Leer tema activo o usar el default
CURRENT_THEME="$HOME/.config/polybar/config.ini"
if [ -f "$HOME/.config/polybar/current_style" ]; then
    SAVED_THEME="$(cat "$HOME/.config/polybar/current_style")"
    [ -f "$SAVED_THEME" ] && CURRENT_THEME="$SAVED_THEME"
fi

# Lanzar en cada monitor conectado
if type "xrandr" > /dev/null 2>&1; then
    for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
        MONITOR=$m polybar --reload main -c "$CURRENT_THEME" &
    done
else
    polybar --reload main -c "$CURRENT_THEME" &
fi
EOF

    # Script: random_wallpaper (Aplica un fondo aleatorio con feh)
    local WALL_SCRIPT="$BIN_DIR/random_wallpaper"
    cat << 'EOF' > "$WALL_SCRIPT"
#!/usr/bin/env bash
WALL_DIR="$HOME/Pictures/wallpapers"

if [ -d "$WALL_DIR" ]; then
    IMG=$(find "$WALL_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" -o -iname "*.webp" \) | shuf -n 1)
    if [ -n "$IMG" ]; then
        feh --bg-fill "$IMG"
        notify-send -u low "Wallpaper" "Fondo aplicado: $(basename "$IMG")"
    fi
fi
EOF

    # Script: polybar_theme_selector (Selector interactivo Rofi para los 6 temas)
    local THEME_SELECT="$BIN_DIR/polybar_theme_selector"
    cat << 'EOF' > "$THEME_SELECT"
#!/usr/bin/env bash
MENU_OPTIONS="1. Catppuccin Mocha (Full Width Default)\n2. Wabri Minimal Nord (Pills & Badges)\n3. Floating Dock Rounded (Catppuccin)\n4. Material Blocks (the-anonymous-raven)\n5. Nordish Mac (the-anonymous-raven)\n6. Gloom Onedark (the-anonymous-raven)\n7. 🔄 Recargar Barra Actual"

CHOSEN=$(echo -e "$MENU_OPTIONS" | rofi -dmenu -i -p "Seleccionar Estilo Polybar:" -theme ~/.config/rofi/config.rasi)

set_theme() {
    local target_cfg="$1"
    local theme_name="$2"
    echo "$target_cfg" > "$HOME/.config/polybar/current_style"
    "$HOME/.local/bin/launch_polybar"
    notify-send "Polybar" "Estilo aplicado: $theme_name"
}

case "$CHOSEN" in
    *1.*)
        set_theme "$HOME/.config/polybar/config.ini" "Catppuccin Mocha Default"
        ;;
    *2.*)
        set_theme "$HOME/.config/polybar/styles/minimal_nord.ini" "Wabri Minimal Nord"
        ;;
    *3.*)
        set_theme "$HOME/.config/polybar/styles/floating.ini" "Floating Dock Rounded"
        ;;
    *4.*)
        set_theme "$HOME/.config/polybar/styles/material_blocks.ini" "Material Blocks"
        ;;
    *5.*)
        set_theme "$HOME/.config/polybar/styles/nordish_mac.ini" "Nordish Mac"
        ;;
    *6.*)
        set_theme "$HOME/.config/polybar/styles/gloom_onedark.ini" "Gloom Onedark"
        ;;
    *7.*)
        "$HOME/.local/bin/launch_polybar"
        notify-send "Polybar" "Polybar recargada exitosamente"
        ;;
esac
EOF

    # Script CLI: polytheme (Cambio rápido por terminal estilo repo)
    local POLYTHEME_CLI="$BIN_DIR/polytheme"
    cat << 'EOF' > "$POLYTHEME_CLI"
#!/usr/bin/env bash
# CLI Selector para Polybar Themes
show_help() {
    echo "Uso: polytheme [opción]"
    echo "Opciones disponibles:"
    echo "  -1 : Catppuccin Mocha Default"
    echo "  -2 : Wabri Minimal Nord (Pills)"
    echo "  -3 : Floating Dock Rounded"
    echo "  -4 : Material Blocks (the-anonymous-raven)"
    echo "  -5 : Nordish Mac (the-anonymous-raven)"
    echo "  -6 : Gloom Onedark (the-anonymous-raven)"
    echo "  -r : Recargar barra actual"
    echo "  -h : Mostrar esta ayuda"
}

case "$1" in
    -1|1)
        echo "$HOME/.config/polybar/config.ini" > "$HOME/.config/polybar/current_style"
        "$HOME/.local/bin/launch_polybar"
        echo "✓ Aplicado: Catppuccin Mocha Default"
        ;;
    -2|2)
        echo "$HOME/.config/polybar/styles/minimal_nord.ini" > "$HOME/.config/polybar/current_style"
        "$HOME/.local/bin/launch_polybar"
        echo "✓ Aplicado: Wabri Minimal Nord"
        ;;
    -3|3)
        echo "$HOME/.config/polybar/styles/floating.ini" > "$HOME/.config/polybar/current_style"
        "$HOME/.local/bin/launch_polybar"
        echo "✓ Aplicado: Floating Dock Rounded"
        ;;
    -4|4)
        echo "$HOME/.config/polybar/styles/material_blocks.ini" > "$HOME/.config/polybar/current_style"
        "$HOME/.local/bin/launch_polybar"
        echo "✓ Aplicado: Material Blocks"
        ;;
    -5|5)
        echo "$HOME/.config/polybar/styles/nordish_mac.ini" > "$HOME/.config/polybar/current_style"
        "$HOME/.local/bin/launch_polybar"
        echo "✓ Aplicado: Nordish Mac"
        ;;
    -6|6)
        echo "$HOME/.config/polybar/styles/gloom_onedark.ini" > "$HOME/.config/polybar/current_style"
        "$HOME/.local/bin/launch_polybar"
        echo "✓ Aplicado: Gloom Onedark"
        ;;
    -r|r)
        "$HOME/.local/bin/launch_polybar"
        echo "✓ Polybar recargada"
        ;;
    *)
        ~/.local/bin/polybar_theme_selector
        ;;
esac
EOF

    # Script: powermenu_rofi
    local POWERMENU="$BIN_DIR/powermenu_rofi"
    cat << 'EOF' > "$POWERMENU"
#!/usr/bin/env bash
OPTIONS="⏻ Apagar\n🔄 Reiniciar\n🚪 Cerrar Sesión\n🔒 Bloquear"
CHOSEN=$(echo -e "$OPTIONS" | rofi -dmenu -i -p "Sistema:" -theme ~/.config/rofi/config.rasi)

case "$CHOSEN" in
    *Apagar*)
        systemctl poweroff
        ;;
    *Reiniciar*)
        systemctl reboot
        ;;
    *Cerrar*)
        bspc quit
        ;;
    *Bloquear*)
        slock || xlock || notify-send "Lock" "Instala un bloqueador como slock o i3lock"
        ;;
esac
EOF

    # Script: notify_volume (Para retroalimentación visual de volumen con Dunst)
    local NOTIFY_VOL="$BIN_DIR/notify_volume"
    cat << 'EOF' > "$NOTIFY_VOL"
#!/usr/bin/env bash
VOL=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -Po '[0-9]+(?=%)' | head -1)
MUTE=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')

if [ "$MUTE" = "yes" ]; then
    dunstify -a "VOLUME" -r 2593 -u low -i audio-volume-muted "Volumen: Muteado"
else
    dunstify -a "VOLUME" -r 2593 -u low -h int:value:"$VOL" -i audio-volume-high "Volumen: ${VOL}%"
fi
EOF

    # Script: statusbar_launcher
    local STATUSBAR_LAUNCH="$BIN_DIR/statusbar_launcher"
    cat << 'EOF' > "$STATUSBAR_LAUNCH"
#!/usr/bin/env bash
~/.local/bin/launch_polybar &
EOF

    chmod +x "$LAUNCH_POLY" "$WALL_SCRIPT" "$THEME_SELECT" "$POLYTHEME_CLI" "$POWERMENU" "$NOTIFY_VOL" "$STATUSBAR_LAUNCH"
    chown -R "$TARGET_USER:$TARGET_USER" "$BIN_DIR"
    log_success "Scripts personalizados y CLI polytheme creados con permisos de ejecución."
}

# ------------------------------------------------------------------------------
# 7. DESCARGA DEL REPOSITORIO DE WALLPAPERS
# ------------------------------------------------------------------------------
download_wallpapers() {
    log_info "7. Descargando colección de wallpapers desde https://github.com/dharmx/walls.git..."
    
    if [ ! -d "$WALLPAPERS_DIR/.git" ]; then
        run_as_user git clone --depth 1 https://github.com/dharmx/walls.git "$WALLPAPERS_DIR" || {
            log_warning "No se pudo clonar el repositorio de wallpapers. Se creará un fondo predeterminado."
        }
    else
        log_info "El repositorio de wallpapers ya existe. Actualizando..."
        (
            cd "$WALLPAPERS_DIR"
            run_as_user git pull || true
        )
    fi

    # Aplicar un wallpaper inicial inmediatamente si feh y X están activos, o generar cache
    if [ -x "$BIN_DIR/random_wallpaper" ]; then
        run_as_user "$BIN_DIR/random_wallpaper" || true
    fi
    log_success "Colección de wallpapers lista en $WALLPAPERS_DIR."
}

# ------------------------------------------------------------------------------
# 8. POST-INSTALACIÓN Y SERVICIOS DEL SISTEMA
# ------------------------------------------------------------------------------
post_installation() {
    log_info "8. Configurando servicios del sistema, Display Manager y grupos de usuario..."

    # 1. Agregar usuario a los grupos recomendados
    log_info "Añadiendo a '$TARGET_USER' a grupos audio, video, network, storage, wheel, input..."
    run_as_root usermod -aG audio,video,network,storage,wheel,input "$TARGET_USER" || true

    # 2. Habilitar NetworkManager
    log_info "Habilitando servicio NetworkManager..."
    run_as_root systemctl enable NetworkManager --now || true

    # 3. Habilitar Display Manager (SDDM)
    log_info "Habilitando Display Manager SDDM..."
    run_as_root systemctl enable sddm || true

    # Crear entrada de sesión X11 para BSPWM en SDDM si no existe
    run_as_root mkdir -p /usr/share/xsessions
    cat << 'EOF' | run_as_root tee /usr/share/xsessions/bspwm.desktop > /dev/null
[Desktop Entry]
Name=bspwm
Comment=Binary Space Partitioning Window Manager
Exec=bspwm
Type=XSession
EOF

    # 4. Servicios de audio Pipewire a nivel de usuario
    log_info "Habilitando servicios de usuario para Pipewire & Wireplumber..."
    run_as_user systemctl --user enable pipewire wireplumber pipewire-pulse 2>/dev/null || true

    log_success "Servicios y configuraciones del sistema completados con éxito."
}

# ------------------------------------------------------------------------------
# 9. RESUMEN FINAL Y FINALIZACIÓN
# ------------------------------------------------------------------------------
finish_installation() {
    clear
    echo -e "${CLR_GREEN}${CLR_BOLD}"
    cat << "EOF"
  _   _ _____ _     _     ___     ____  _   _  ____ ____ _____ ____ ____  
 | | | | ____| |   | |   / _ \   / ___|| | | |/ ___/ ___| ____/ ___/ ___| 
 | |_| |  _| | |   | |  | | | |  \___ \| | | | |  | |   |  _| \___ \___ \ 
 |  _  | |___| |___| |___ |_| |   ___) | |_| | |__| |___| |___ ___) |__) |
 |_| |_|_____|_____|_____|\___/  |____/ \___/ \____\____|_____|____/____/  
EOF
    echo -e "${CLR_RESET}"
    echo -e "${CLR_BLUE}==============================================================================${CLR_RESET}"
    echo -e "${CLR_GREEN} ✓ INSTALACIÓN Y CONFIGURACIÓN DE BSPWM COMPLETADA CON ÉXITO${CLR_RESET}"
    echo -e "${CLR_BLUE}==============================================================================${CLR_RESET}"
    echo -e "${CLR_CYAN}Resumen de Componentes Instalados y Configurados:${CLR_RESET}"
    echo -e " • ${CLR_MAUVE}Window Manager:${CLR_RESET}   bspwm + sxhkd (Catppuccin Mocha border & gap rules)"
    echo -e " • ${CLR_MAUVE}Barra de Estado:${CLR_RESET}   Polybar (Multi-monitor + selector de temas)"
    echo -e " • ${CLR_MAUVE}Lanzador:${CLR_RESET}          Rofi (drun, run, window con tema Catppuccin)"
    echo -e " • ${CLR_MAUVE}Compositor:${CLR_RESET}        Picom (Bordes redondeados, sombras y transparencia)"
    echo -e " • ${CLR_MAUVE}Terminal:${CLR_RESET}          Kitty (JetBrains Mono Nerd Font 12px + Mocha)"
    echo -e " • ${CLR_MAUVE}Notificaciones:${CLR_RESET}    Dunst (Notificaciones estéticas)"
    echo -e " • ${CLR_MAUVE}Display Manager:${CLR_RESET}   SDDM (Inicia automáticamente al reiniciar)"
    echo -e " • ${CLR_MAUVE}Wallpapers:${CLR_RESET}        Colección dharmx/walls en ~/Pictures/wallpapers/"
    echo ""
    echo -e "${CLR_CYAN}Atajos de Teclado Principales:${CLR_RESET}"
    echo -e " • ${CLR_YELLOW}Super + Enter${CLR_RESET}        -> Abrir Terminal Kitty"
    echo -e " • ${CLR_YELLOW}Super + d${CLR_RESET}            -> Lanzador de aplicaciones Rofi"
    echo -e " • ${CLR_YELLOW}Super + q${CLR_RESET}            -> Cerrar ventana activa"
    echo -e " • ${CLR_YELLOW}Super + {1-4}${CLR_RESET}        -> Cambiar de escritorio (Workspaces)"
    echo -e " • ${CLR_YELLOW}Super + Shift + {1-4}${CLR_RESET}-> Mover ventana a escritorio"
    echo -e " • ${CLR_YELLOW}Super + {h,j,k,l}${CLR_RESET}    -> Navegar entre ventanas (Vim keys)"
    echo -e " • ${CLR_YELLOW}Super + p${CLR_RESET}            -> Selector de estilos de Polybar"
    echo -e " • ${CLR_YELLOW}Super + b${CLR_RESET}            -> Cambiar fondo de pantalla al azar"
    echo -e " • ${CLR_YELLOW}Print / Super+Print${CLR_RESET}  -> Capturas de pantalla con Scrot"
    echo -e "${CLR_BLUE}==============================================================================${CLR_RESET}"
    echo ""
    echo -e "${CLR_YELLOW}¿Deseas reiniciar el sistema ahora para iniciar en el nuevo entorno? [s/N]${CLR_RESET}"
    read -r reboot_resp

    if [[ "$reboot_resp" =~ ^([sS][iI]|[sS])$ ]]; then
        log_info "Reiniciando el sistema..."
        run_as_root reboot
    else
        log_info "Instalación finalizada. Puedes iniciar el entorno reiniciando o ejecutando 'startx'."
    fi
}

# ------------------------------------------------------------------------------
# FLUJO PRINCIPAL DE EJECUCIÓN
# ------------------------------------------------------------------------------
main() {
    initial_checks
    install_official_packages
    install_yay
    install_optional_packages
    setup_directories_and_backup
    configure_bspwm
    configure_sxhkd
    configure_polybar
    configure_picom
    configure_dunst
    configure_kitty
    configure_rofi
    configure_gtk
    configure_xinit_and_xresources
    setup_custom_scripts
    download_wallpapers
    post_installation
    finish_installation
}

main "$@"
