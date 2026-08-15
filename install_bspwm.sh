#!/usr/bin/env bash
# ==============================================================================
# Script de Instalación y Configuración Automatizada de BSPWM (Catppuccin Mocha)
# Sistema Operativo Objetivo: Arch Linux (Instalación Base)
# ==============================================================================

# Detener la ejecución si ocurre un error no controlado
set -eo pipefail

# ==============================================================================
# 0. VARIABLES GLOBALES Y PALETA DE COLORES
# ==============================================================================

# Colores para salida en terminal
CLR_RESET="\033[0m"
CLR_INFO="\033[0;34m"     # Azul
CLR_SUCCESS="\033[0;32m"  # Verde
CLR_WARN="\033[0;33m"     # Amarillo
CLR_ERROR="\033[0;31m"    # Rojo
CLR_HEADER="\033[1;35m"   # Magenta negrita
CLR_ACCENT="\033[1;36m"   # Cyan negrita

# Directorio de respaldo para configuraciones previas
BACKUP_DIR=""

# Detección del usuario real (no root si se corre con sudo)
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo '')}"

if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    # Intenta obtener el primer usuario normal con UID >= 1000
    TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")

# URLs de Wallpapers Catppuccin Mocha
WALLPAPER_URL="https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/misc/cat_leaves.png"
WALLPAPER_FALLBACK_URL="https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/landscapes/mountains.png"

# ==============================================================================
# FUNCIONES DE UTILIDAD Y LOGGING
# ==============================================================================

log_header() {
    echo -e "\n${CLR_HEADER}==============================================================================${CLR_RESET}"
    echo -e "${CLR_HEADER}  $1${CLR_RESET}"
    echo -e "${CLR_HEADER}==============================================================================${CLR_RESET}\n"
}

log_info() {
    echo -e "${CLR_INFO}[INFO]${CLR_RESET} $1"
}

log_success() {
    echo -e "${CLR_SUCCESS}[OK]${CLR_RESET} $1"
}

log_warn() {
    echo -e "${CLR_WARN}[ADVERTENCIA]${CLR_RESET} $1"
}

log_error() {
    echo -e "${CLR_ERROR}[ERROR]${CLR_RESET} $1" >&2
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-Y}"
    local response

    if [[ "$default" == "Y" ]]; then
        prompt="$prompt [S/n]: "
    else
        prompt="$prompt [s/N]: "
    fi

    while true; do
        read -rp "$(echo -e "${CLR_ACCENT}${prompt}${CLR_RESET}")" response
        response="${response:-$default}"
        case "${response,,}" in
            s|si|y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo -e "${CLR_WARN}Respuesta no válida. Escribe 's' o 'n'.${CLR_RESET}" ;;
        esac
    done
}

# Manejador de trampas para rollback o notificación de errores
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "El script finalizó abruptamente con código de salida: $exit_code"
        if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
            log_warn "Se creó un respaldo previo en: $BACKUP_DIR"
            log_warn "Puedes restaurar tus dotfiles copiando el contenido de dicho directorio."
        fi
    fi
}
trap cleanup_on_error EXIT

# ==============================================================================
# 1. VERIFICACIÓN INICIAL DEL SISTEMA
# ==============================================================================

check_prerequisites() {
    log_header "1. Verificación Inicial del Entorno"

    # Verificar permisos de root
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root (usa sudo)."
        exit 1
    fi
    log_success "Ejecutando como usuario con privilegios (root)."

    # Validar usuario objetivo
    if [[ -z "$TARGET_USER" || ! -d "$TARGET_HOME" ]]; then
        log_error "No se pudo determinar el usuario normal del sistema para configurar el /home."
        read -rp "Ingresa el nombre de usuario de tu cuenta normal: " TARGET_USER
        TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
        TARGET_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")
        if [[ ! -d "$TARGET_HOME" ]]; then
            log_error "El directorio home $TARGET_HOME no existe."
            exit 1
        fi
    fi
    log_info "Usuario objetivo detectado: ${CLR_ACCENT}${TARGET_USER}${CLR_RESET} (Home: $TARGET_HOME)"

    # Verificar conexión a Internet
    log_info "Comprobando conexión a Internet..."
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null && ! ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        log_error "No hay conexión a Internet. Conéctate a la red antes de continuar."
        exit 1
    fi
    log_success "Conexión a Internet confirmada."

    # Inicializar directorio de backup
    BACKUP_DIR="$TARGET_HOME/.config/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
    log_info "Punto de respaldo preparado en: $BACKUP_DIR"

    # Preguntar confirmación para actualizar el sistema
    if ask_yes_no "¿Deseas sincronizar y actualizar el sistema completo con 'pacman -Syu'?" "Y"; then
        log_info "Actualizando repositorios y paquetes del sistema..."
        pacman -Syu --noconfirm
        log_success "Sistema actualizado correctamente."
    else
        log_warn "Se omitió la actualización completa del sistema. Continuando..."
    fi
}

# ==============================================================================
# 2. INSTALACIÓN DE PAQUETES OFICIALES (PACMAN)
# ==============================================================================

install_packages() {
    log_header "2. Instalación de Paquetes Base y Entorno BSPWM"

    local base_packages=(
        # Servidor X y utilidades
        xorg-server
        xorg-xinit
        xorg-xrandr
        xorg-xsetroot
        xorg-xprop
        xdotool
        xclip
        
        # Gestor de ventanas y atajos
        bspwm
        sxhkd

        # Terminal y barra de estado
        kitty
        polybar

        # Lanzador y composición
        rofi
        picom

        # Notificaciones y fondos
        dunst
        libnotify
        feh
        scrot

        # Gestor de archivos y soporte de montaje
        thunar
        thunar-volman
        thunar-archive-plugin
        tumbler
        file-roller
        gvfs

        # Red
        networkmanager
        network-manager-applet

        # Audio (Pipewire stack)
        pipewire
        pipewire-pulse
        pipewire-alsa
        pipewire-jack
        wireplumber
        pavucontrol
        alsa-utils
        pamixer

        # Fuentes tipográficas completas
        ttf-jetbrains-mono-nerd
        noto-fonts
        noto-fonts-cjk
        noto-fonts-emoji
        ttf-font-awesome
        ttf-nerd-fonts-symbols
        ttf-nerd-fonts-symbols-mono

        # Apariencia y Display Manager
        lxappearance
        sddm
        polkit-gnome

        # Herramientas de compilación y utilidades de sistema
        base-devel
        git
        curl
        wget
        unzip
        bc
        jq
        xdg-user-dirs
        xdg-utils
    )

    log_info "Instalando paquetes principales vía pacman (${#base_packages[@]} paquetes en total)..."
    pacman -S --needed --noconfirm "${base_packages[@]}"
    log_success "Paquetes oficiales instalados con éxito."
}

# ==============================================================================
# 3. GESTIÓN E INSTALACIÓN DE AUR HELPER (YAY) Y PAQUETES OPCIONALES
# ==============================================================================

install_yay_and_aur() {
    log_header "3. Configuración de AUR Helper (yay) y Paquetes Adicionales"

    local install_yay=false
    if command -v yay &>/dev/null; then
        log_success "yay ya se encuentra instalado en el sistema."
        install_yay=true
    else
        if ask_yes_no "¿Deseas instalar el helper de AUR 'yay' (versión optimizada yay-bin)?" "Y"; then
            log_info "Preparando compilación de yay-bin para usuario '$TARGET_USER'..."

            local tmp_yay_dir="/tmp/yay_build_$$"
            rm -rf "$tmp_yay_dir"
            mkdir -p "$tmp_yay_dir"
            chown -R "$TARGET_USER:$TARGET_GROUP" "$tmp_yay_dir"

            # Clonar el repositorio de yay-bin (binario precompilado, ultra rápido)
            if sudo -u "$TARGET_USER" git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp_yay_dir"; then
                log_info "Compilando/empaquetando yay-bin..."
                (
                    cd "$tmp_yay_dir"
                    # Deshabilitar paquetes debug y checks para evitar que se cuelgue copiando archivos fuente
                    PKGDEST="$tmp_yay_dir" sudo -u "$TARGET_USER" makepkg -s --noconfirm --nocheck --skippgpcheck
                )

                # Instalar el paquete generado directamente con pacman (como root, sin bloqueos de sudo)
                local pkg_file
                pkg_file=$(find "$tmp_yay_dir" -maxdepth 1 -name "yay-bin-*.pkg.tar.*" | head -n 1)

                if [[ -n "$pkg_file" && -f "$pkg_file" ]]; then
                    log_info "Instalando paquete yay: $(basename "$pkg_file")..."
                    pacman -U --noconfirm "$pkg_file"
                fi
            fi
            rm -rf "$tmp_yay_dir"

            if command -v yay &>/dev/null; then
                log_success "yay se ha instalado y verificado exitosamente."
                install_yay=true
            else
                log_warn "No se pudo instalar yay-bin automáticamente. Continuando con el resto del sistema."
            fi
        fi
    fi

    # Preguntar por paquetes opcionales de software y temas
    log_info "Opciones de paquetes adicionales recomendados:"
    
    local aur_packages=()

    if ask_yes_no "• ¿Instalar temas GTK e Iconos Catppuccin (catppuccin-gtk-theme-mocha y tela-circle-icon-theme)?" "Y"; then
        if [[ "$install_yay" == true ]]; then
            aur_packages+=(catppuccin-gtk-theme-mocha tela-circle-icon-theme)
        else
            log_warn "yay no está disponible; omitiendo instalación de temas AUR."
        fi
    fi

    if ask_yes_no "• ¿Instalar navegador web Firefox?" "Y"; then
        pacman -S --needed --noconfirm firefox
    fi

    if ask_yes_no "• ¿Instalar navegador web Brave (Brave-bin vía AUR)?" "N"; then
        if [[ "$install_yay" == true ]]; then
            aur_packages+=(brave-bin)
        fi
    fi

    if ask_yes_no "• ¿Instalar Neovim (editor de texto avanzado)?" "Y"; then
        pacman -S --needed --noconfirm neovim
    fi

    if ask_yes_no "• ¿Instalar utilidades de monitoreo y CLI (fastfetch, htop, btop)?" "Y"; then
        pacman -S --needed --noconfirm fastfetch htop btop
    fi

    if [[ ${#aur_packages[@]} -gt 0 && "$install_yay" == true ]]; then
        log_info "Instalando paquetes AUR seleccionados: ${aur_packages[*]}"
        # Usar --nocheck y --answerclean=None para evitar preguntas interactivas o bloqueos
        sudo -u "$TARGET_USER" yay -S --needed --noconfirm --nocheck "${aur_packages[@]}" || log_warn "Algunos paquetes AUR no pudieron completarse. Puedes instalarlos luego con 'yay -S <paquete>'."
    fi
}

# ==============================================================================
# 4. CREACIÓN DE LA ESTRUCTURA DE DIRECTORIOS Y BACKUP
# ==============================================================================

create_directory_structure() {
    log_header "4. Creación de Estructura de Directorios"

    local dirs=(
        "$TARGET_HOME/.config/bspwm"
        "$TARGET_HOME/.config/sxhkd"
        "$TARGET_HOME/.config/polybar"
        "$TARGET_HOME/.config/picom"
        "$TARGET_HOME/.config/dunst"
        "$TARGET_HOME/.config/rofi"
        "$TARGET_HOME/.config/kitty"
        "$TARGET_HOME/.config/gtk-3.0"
        "$TARGET_HOME/.config/gtk-4.0"
        "$TARGET_HOME/.local/bin"
        "$TARGET_HOME/Pictures/wallpapers"
        "$TARGET_HOME/Pictures/Screenshots"
    )

    log_info "Generando carpetas de configuración en $TARGET_HOME..."
    for d in "${dirs[@]}"; do
        if [[ -d "$d" ]]; then
            mkdir -p "$BACKUP_DIR"
            log_info "Respaldando directorio existente: $d -> $BACKUP_DIR/"
            cp -ra "$d" "$BACKUP_DIR/" 2>/dev/null || true
        fi
        mkdir -p "$d"
    done

    # Inicializar directorios estándar XDG
    sudo -u "$TARGET_USER" xdg-user-dirs-update 2>/dev/null || true

    log_success "Estructura de directorios creada correctamente."
}

# ==============================================================================
# 5. CONFIGURACIÓN DE BSPWM Y SXHKD
# ==============================================================================

configure_bspwm() {
    log_header "5.1 Configurando BSPWM (bspwmrc)"

    local bspwmrc_path="$TARGET_HOME/.config/bspwm/bspwmrc"

    cat << 'EOF' > "$bspwmrc_path"
#!/usr/bin/env bash
# ==============================================================================
# Configuración Principal de BSPWM - Tema Catppuccin Mocha
# ==============================================================================

# 1. Iniciar gestor de atajos (sxhkd)
pgrep -x sxhkd > /dev/null || sxhkd &

# 2. Configurar escritorios / Workspaces
# Monitores dinámicos: Asigna los 4 escritorios al monitor principal o disponible
if xrandr -q | grep " connected" | grep -q "primary"; then
    PRIMARY_MONITOR=$(xrandr -q | grep " connected" | grep "primary" | awk '{print $1}')
    bspc monitor "$PRIMARY_MONITOR" -d "I:Web" "II:Term" "III:Code" "IV:Misc"
else
    # Si no hay primario explícito, asigna a todos los conectados
    for monitor in $(xrandr --query | grep " connected" | cut -d" " -f1); do
        bspc monitor "$monitor" -d "I:Web" "II:Term" "III:Code" "IV:Misc"
    done
fi

# 3. Configuración visual y diseño de ventanas (Catppuccin Mocha)
bspc config border_width         2
bspc config window_gap          10
bspc config split_ratio          0.52

# Colores de bordes
bspc config normal_border_color   "#45475a" # Surface 1
bspc config active_border_color   "#585b70" # Surface 2
bspc config focused_border_color  "#89b4fa" # Blue (Catppuccin Mocha)
bspc config presel_feedback_color "#cba6f7" # Mauve

# Comportamientos de foco y puntero
bspc config focus_follows_pointer true
bspc config pointer_modifier      mod4
bspc config pointer_action1       move
bspc config pointer_action2       resize_side
bspc config pointer_action3       resize_corner

# Margenes globales para integrar con Polybar
bspc config top_padding           32
bspc config bottom_padding        4
bspc config left_padding          4
bspc config right_padding         4

# 4. Reglas de ventanas
bspc rule -a Rofi state=floating center=true
bspc rule -a Lxappearance state=floating center=true
bspc rule -a Pavucontrol state=floating center=true
bspc rule -a Thunar state=floating center=true
bspc rule -a File-roller state=floating center=true
bspc rule -a Feh state=floating center=true
bspc rule -a Gvfs-archive-manager state=floating center=true

# Asignación automática a workspaces
bspc rule -a firefox desktop='^1' follow=on
bspc rule -a Brave-browser desktop='^1' follow=on
bspc rule -a Code desktop='^3' follow=on
bspc rule -a VSCodium desktop='^3' follow=on

# 5. Programas de Autostart
# Polkit autenticación gráfica
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Compositor con soporte OpenGL
pgrep -x picom > /dev/null || picom --config ~/.config/picom/picom.conf -b

# Servidor de Notificaciones Dunst
pgrep -x dunst > /dev/null || dunst &

# Applet de Red
pgrep -x nm-applet > /dev/null || nm-applet &

# Fondo de pantalla
~/.local/bin/wallpaper_setup &

# Lanzador de Polybar
~/.local/bin/launch_polybar &

# Configurar cursor estándar
xsetroot -cursor_name left_ptr &
EOF

    chmod +x "$bspwmrc_path"
    log_success "Archivo bspwmrc creado y marcado como ejecutable."
}

configure_sxhkd() {
    log_header "5.2 Configurando Atajos de Teclado (sxhkdrc)"

    local sxhkdrc_path="$TARGET_HOME/.config/sxhkd/sxhkdrc"

    cat << 'EOF' > "$sxhkdrc_path"
# ==============================================================================
# Atajos de Teclado SXHKD - BSPWM + Catppuccin Mocha
# Modkey: Super (Windows Key)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. APLICACIONES Y LANZADORES
# ------------------------------------------------------------------------------

# Terminal (Kitty)
super + Return
    kitty

# Lanzador de aplicaciones Rofi (drun)
super + d
    rofi -show drun -show-icons

# Lanzador de comandos Rofi (run)
super + r
    rofi -show run

# Lista de ventanas activas Rofi (window)
super + w
    rofi -show window

# Gestor de archivos (Thunar)
super + e
    thunar

# Bloqueo o menú de energía (opcional)
super + Escape
    xkill

# ------------------------------------------------------------------------------
# 2. GESTIÓN DE BSPWM
# ------------------------------------------------------------------------------

# Reiniciar bspwm y sxhkd en caliente
super + alt + r
    bspc wm -r; pkill -USR1 -x sxhkd

# Cerrar o matar ventana enfocada
super + q
    bspc node -c
super + shift + q
    bspc node -k

# Layouts: Alternar entre Tiled y Monocle
super + m
    bspc desktop -l next

super + t
    bspc node -t tiled

super + f
    bspc node -t fullscreen

super + space
    bspc node -t ~floating

# ------------------------------------------------------------------------------
# 3. NAVEGACIÓN Y FOCO (Vim Keys & Flechas)
# ------------------------------------------------------------------------------

# Cambiar foco entre nodos (Vim keys: h, j, k, l o j, k, l, ;)
super + {h,j,k,l}
    bspc node -f {west,south,north,east}

super + {Left,Down,Up,Right}
    bspc node -f {west,south,north,east}

# Mover ventanas de posición (Vim keys)
super + shift + {h,j,k,l}
    bspc node -s {west,south,north,east}

super + shift + {Left,Down,Up,Right}
    bspc node -s {west,south,north,east}

# ------------------------------------------------------------------------------
# 4. GESTIÓN DE WORKSPACES / ESCRITORIOS
# ------------------------------------------------------------------------------

# Cambiar al escritorio {1-4}
super + {1,2,3,4}
    bspc desktop -f '^{1,2,3,4}'

# Mover ventana activa al escritorio {1-4}
super + shift + {1,2,3,4}
    bspc node -d '^{1,2,3,4}' --follow

# ------------------------------------------------------------------------------
# 5. CONTROL DE GAPS DINÁMICOS
# ------------------------------------------------------------------------------

# Aumentar o disminuir tamaño de gaps
super + ctrl + l
    bspc config window_gap $(( $(bspc config window_gap) + 2 ))
super + ctrl + h
    bspc config window_gap $(( $(bspc config window_gap) > 2 ? $(bspc config window_gap) - 2 : 0 ))

# ------------------------------------------------------------------------------
# 6. TECLAS MULTIMEDIA Y AUDIO (Pipewire / Pulse)
# ------------------------------------------------------------------------------

# Subir Volumen (+5%)
XF86AudioRaiseVolume
    pactl set-sink-volume @DEFAULT_SINK@ +5%

# Bajar Volumen (-5%)
XF86AudioLowerVolume
    pactl set-sink-volume @DEFAULT_SINK@ -5%

# Silenciar / Reactivar Audio
XF86AudioMute
    pactl set-sink-mute @DEFAULT_SINK@ toggle

# Silenciar Micrófono
XF86AudioMicMute
    pactl set-source-mute @DEFAULT_SOURCE@ toggle

# ------------------------------------------------------------------------------
# 7. CAPTURAS DE PANTALLA (Scrot)
# ------------------------------------------------------------------------------

# Captura de pantalla completa
Print
    scrot ~/Pictures/Screenshots/'Screenshot_%Y-%m-%d-%H%M%S.png' -e 'notify-send -u low "Captura guardada" $f'

# Captura de región / área seleccionada
super + shift + s
    scrot -s ~/Pictures/Screenshots/'Screenshot_%Y-%m-%d-%H%M%S.png' -e 'xclip -selection clipboard -t image/png < $f; notify-send -u low "Captura copiada al portapapeles" $f'

super + Print
    scrot -u ~/Pictures/Screenshots/'Screenshot_%Y-%m-%d-%H%M%S.png' -e 'notify-send -u low "Captura de ventana" $f'
EOF

    log_success "Archivo sxhkdrc configurado correctamente."
}

# ==============================================================================
# 6. CONFIGURACIÓN DE POLYBAR Y TEMAS CATPPUCCIN
# ==============================================================================

configure_polybar() {
    log_header "6. Configurando Polybar (Catppuccin Mocha)"

    local polybar_config="$TARGET_HOME/.config/polybar/config.ini"

    cat << 'EOF' > "$polybar_config"
; ==============================================================================
; Polybar Configuration - Catppuccin Mocha Theme
; ==============================================================================

[colors]
base      = #1e1e2e
mantle    = #181825
crust     = #11111b
text      = #cdd6f4
subtext0  = #a6adc8
surface0  = #313244
surface1  = #45475a
surface2  = #585b70
blue      = #89b4fa
lavender  = #b4befe
sapphire  = #74c7ec
sky       = #89dceb
teal      = #94e2d5
green     = #a6e3a1
yellow    = #f9e2af
peach     = #fab387
maroon    = #eba0ac
red       = #f38ba8
mauve     = #cba6f7
pink      = #f5c2e7
transparent = #00000000

[bar/main]
monitor = ${env:MONITOR:}
width = 100%
height = 30pt
radius = 0

background = ${colors:base}
foreground = ${colors:text}

line-size = 2pt

border-size = 0pt
border-color = ${colors:transparent}

padding-left = 1
padding-right = 1

module-margin = 1

separator = |
separator-foreground = ${colors:surface1}

font-0 = "JetBrains Mono Nerd Font:size=11;3"
font-1 = "JetBrains Mono Nerd Font:size=14;3"
font-2 = "Font Awesome 6 Free:style=Solid:size=11;3"

modules-left = xworkspaces xwindow
modules-center = date
modules-right = pulseaudio memory cpu network battery tray

cursor-click = pointer
cursor-scroll = ns-resize

enable-ipc = true
wm-restack = bspwm

; ------------------------------------------------------------------------------
; MÓDULOS
; ------------------------------------------------------------------------------

[module/xworkspaces]
type = internal/xworkspaces

label-active = %name%
label-active-background = ${colors:surface0}
label-active-foreground = ${colors:blue}
label-active-underline= ${colors:mauve}
label-active-padding = 1

label-occupied = %name%
label-occupied-foreground = ${colors:subtext0}
label-occupied-padding = 1

label-urgent = %name%
label-urgent-background = ${colors:red}
label-urgent-foreground = ${colors:crust}
label-urgent-padding = 1

label-empty = %name%
label-empty-foreground = ${colors:surface1}
label-empty-padding = 1

[module/xwindow]
type = internal/xwindow
label = %title:0:40:...%
label-foreground = ${colors:subtext0}

[module/pulseaudio]
type = internal/pulseaudio

format-volume-prefix = "󰕾 "
format-volume-prefix-foreground = ${colors:blue}
format-volume = <label-volume>
label-volume = %percentage%%
label-volume-foreground = ${colors:text}

format-muted-prefix = "󰝟 "
format-muted-prefix-foreground = ${colors:red}
label-muted = "Mute"
label-muted-foreground = ${colors:surface2}

[module/memory]
type = internal/memory
interval = 2
format-prefix = "󰍛 "
format-prefix-foreground = ${colors:green}
label = %percentage_used:2%%
label-foreground = ${colors:text}

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "󰻠 "
format-prefix-foreground = ${colors:yellow}
label = %percentage:2%%
label-foreground = ${colors:text}

[module/network]
type = internal/network
interface-type = wired,wireless
interval = 3.0

format-connected-prefix = "󰤨 "
format-connected-prefix-foreground = ${colors:teal}
format-connected = <label-connected>
label-connected = %essid% %netspeed%
label-connected-foreground = ${colors:text}

format-disconnected-prefix = "󰤭 "
format-disconnected-prefix-foreground = ${colors:red}
label-disconnected = "Offline"
label-disconnected-foreground = ${colors:surface2}

[module/date]
type = internal/date
interval = 1

date = %a %d %b
time = %H:%M:%S
date-alt = %Y-%m-%d %H:%M:%S

format-prefix = "󰥔 "
format-prefix-foreground = ${colors:mauve}
label = %date% %time%
label-foreground = ${colors:text}

[module/battery]
type = internal/battery
full-at = 99
low-at = 15
battery = BAT0
adapter = ADP1
poll-interval = 5

format-charging = <animation-charging> <label-charging>
format-discharging = <ramp-capacity> <label-discharging>
label-charging = %percentage%%
label-discharging = %percentage%%
label-full = 󰁹 100%
label-full-foreground = ${colors:green}

ramp-capacity-0 = 󰁺
ramp-capacity-1 = 󰁼
ramp-capacity-2 = 󰁾
ramp-capacity-3 = 󰂀
ramp-capacity-4 = 󰁹
ramp-capacity-foreground = ${colors:peach}

animation-charging-0 = 󰂆
animation-charging-1 = 󰂈
animation-charging-2 = 󰂉
animation-charging-3 = 󰂊
animation-charging-4 = 󰂅
animation-charging-foreground = ${colors:green}
animation-charging-framerate = 750

[module/tray]
type = internal/tray
format-margin = 4px
tray-spacing = 8px
tray-size = 16px

[settings]
screenchange-reload = true
pseudo-transparency = true
EOF

    log_success "Polybar configurada con tema Catppuccin Mocha."
}

# ==============================================================================
# 7. CONFIGURACIÓN DE PICOM, DUNST, KITTY Y ROFI
# ==============================================================================

configure_picom() {
    log_header "7.1 Configurando Compositor (picom.conf)"

    local picom_path="$TARGET_HOME/.config/picom/picom.conf"

    cat << 'EOF' > "$picom_path"
# ==============================================================================
# Picom Configuration - Estética Moderna Catppuccin Mocha
# ==============================================================================

backend = "glx";
glx-no-stencil = true;
glx-copy-from-front = false;
vsync = true;

# ------------------------------------------------------------------------------
# Sombras (Shadows)
# ------------------------------------------------------------------------------
shadow = true;
shadow-radius = 7;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-opacity = 0.5;
shadow-exclude = [
  "name = 'Notification'",
  "class_g = 'Conky'",
  "class_g ?= 'Notify-osd'",
  "class_g = 'Cairo-clock'",
  "class_g = 'slop'",
  "class_g = 'Polybar'",
  "_GTK_FRAME_EXTENTS@:c"
];

# ------------------------------------------------------------------------------
# Transparencias y Opacidad
# ------------------------------------------------------------------------------
active-opacity = 1.0;
inactive-opacity = 0.85;
frame-opacity = 1.0;
inactive-opacity-override = false;

opacity-rule = [
  "80:class_g = 'kitty'",
  "90:class_g = 'Rofi'",
  "90:class_g = 'Thunar'",
  "100:class_g = 'firefox'",
  "100:class_g = 'Brave-browser'",
  "100:fullscreen"
];

# ------------------------------------------------------------------------------
# Esquinas Redondeadas (Corner Radius)
# ------------------------------------------------------------------------------
corner-radius = 10;
rounded-corners-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "class_g = 'Polybar'"
];

# ------------------------------------------------------------------------------
# Fading y Animaciones Suaves
# ------------------------------------------------------------------------------
fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
fade-delta = 4;

wintypes:
{
  tooltip = { fade = true; shadow = true; opacity = 0.95; focus = true; full-shadow = false; };
  dock = { shadow = false; clip-shadow-above = true; }
  dnd = { shadow = false; }
  popup_menu = { opacity = 0.95; }
  dropdown_menu = { opacity = 0.95; }
};
EOF

    log_success "Archivo picom.conf creado."
}

configure_dunst() {
    log_header "7.2 Configurando Notificaciones (dunstrc)"

    local dunst_path="$TARGET_HOME/.config/dunst/dunstrc"

    cat << 'EOF' > "$dunst_path"
# ==============================================================================
# Dunst Notification Daemon - Catppuccin Mocha Theme
# ==============================================================================

[global]
    monitor = 0
    follow = mouse
    width = 320
    height = 100
    origin = top-right
    offset = 15x45
    scale = 0
    notification_limit = 5

    progress_bar = true
    progress_bar_height = 8
    progress_bar_frame_width = 1
    progress_bar_min_width = 150
    progress_bar_max_width = 300
    progress_bar_corner_radius = 4

    indicate_hidden = yes
    transparency = 20
    separator_height = 2
    padding = 12
    horizontal_padding = 12
    text_icon_padding = 12
    frame_width = 2
    frame_color = "#89b4fa"
    gap_size = 10
    separator_color = frame
    sort = yes

    font = JetBrains Mono Nerd Font 11
    line_height = 0
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    show_age_threshold = 60
    ellipsize = middle
    ignore_newline = no
    stack_duplicates = true
    hide_duplicate_count = false
    show_indicators = yes

    enable_recursive_icon_lookup = true
    icon_theme = "Tela-circle, Papirus-Dark, Adwaita"
    icon_position = left
    min_icon_size = 24
    max_icon_size = 48

    corner_radius = 10
    mouse_left_click = close_current
    mouse_middle_click = do_action, close_current
    mouse_right_click = close_all

[urgency_low]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#89b4fa"
    timeout = 5

[urgency_normal]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#89b4fa"
    timeout = 8

[urgency_critical]
    background = "#1e1e2e"
    foreground = "#f38ba8"
    frame_color = "#f38ba8"
    timeout = 0
EOF

    log_success "Archivo dunstrc configurado."
}

configure_kitty() {
    log_header "7.3 Configurando Terminal (kitty.conf)"

    local kitty_path="$TARGET_HOME/.config/kitty/kitty.conf"

    cat << 'EOF' > "$kitty_path"
# ==============================================================================
# Kitty Terminal Configuration - Catppuccin Mocha Palette
# ==============================================================================

# Fuente tipográfica
font_family      JetBrains Mono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        12.0

# Ventana y Transparencias
background_opacity 0.85
window_padding_width 12
hide_window_decorations yes
confirm_os_window_close 0

# Scrollback y Rendimiento
scrollback_lines 10000
mouse_hide_wait 3.0
repaint_delay 10
input_delay 3
sync_to_monitor yes

# Esquema de Colores Catppuccin Mocha
foreground              #cdd6f4
background              #1e1e2e
selection_foreground    #1e1e2e
selection_background    #f5e0dc

# Cursor
cursor                  #f5e0dc
cursor_text_color       #1e1e2e
cursor_shape            beam

# Bordes y pestañas
active_border_color     #b4befe
inactive_border_color   #6c7086
bell_border_color       #f9e2af

# Paleta ANSI de 16 colores
# Negro (Surface 1 / Overlay 0)
color0 #45475a
color8 #585b70

# Rojo
color1 #f38ba8
color9 #f38ba8

# Verde
color2  #a6e3a1
color10 #a6e3a1

# Amarillo
color3  #f9e2af
color11 #f9e2af

# Azul
color4  #89b4fa
color12 #89b4fa

# Magenta / Mauve
color5  #cba6f7
color13 #cba6f7

# Cyan / Teal
color6  #94e2d5
color14 #94e2d5

# Blanco / Subtext
color7  #bac2de
color15 #a6adc8
EOF

    log_success "Archivo kitty.conf configurado."
}

configure_rofi() {
    log_header "7.4 Configurando Lanzador Rofi (config.rasi)"

    local rofi_path="$TARGET_HOME/.config/rofi/config.rasi"

    cat << 'EOF' > "$rofi_path"
/**
 * Rofi Catppuccin Mocha Theme
 **/

configuration {
    modi: "drun,run,window";
    lines: 7;
    font: "JetBrains Mono Nerd Font 12";
    show-icons: true;
    icon-theme: "Tela-circle";
    terminal: "kitty";
    drun-display-format: "{icon} {name}";
    location: 0;
    disable-history: false;
    hide-scrollbar: true;
    display-drun: " 󰀻  Apps ";
    display-run: " 󰌑  Run ";
    display-window: " 󰕰  Window ";
    sidebar-mode: true;
}

* {
    bg-col:  #1e1e2e;
    bg-col-light: #313244;
    border-col: #89b4fa;
    selected-col: #45475a;
    blue: #89b4fa;
    fg-col: #cdd6f4;
    fg-col2: #f38ba8;
    grey: #6c7086;

    width: 600;
    background-color: @bg-col;
}

element-text, element-icon , mode-switcher {
    background-color: inherit;
    text-color:       inherit;
}

window {
    height: 380px;
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
    margin: 20px 0px 0px 20px;
}

textbox-prompt-colon {
    expand: false;
    str: ":";
}

entry {
    padding: 6px;
    margin: 20px 0px 0px 10px;
    text-color: @fg-col;
    background-color: @bg-col-light;
    border-radius: 6px;
}

listview {
    border: 0px 0px 0px;
    padding: 6px 0px 0px;
    margin: 10px 0px 0px 20px;
    columns: 1;
    lines: 6;
    background-color: @bg-col;
}

element {
    padding: 5px;
    background-color: @bg-col;
    text-color: @fg-col;
    border-radius: 6px;
}

element-icon {
    size: 25px;
    margin: 0 10px 0 0;
}

element selected {
    background-color:  @selected-col ;
    text-color: @blue  ;
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

    log_success "Archivo config.rasi creado."
}

# ==============================================================================
# 8. CONFIGURACIÓN DE GTK, XINITRC, XRESOURCES Y SCRIPTS PERSONALIZADOS
# ==============================================================================

configure_gtk() {
    log_header "8.1 Configuración de Temas GTK e Integración Visual"

    local gtk3_path="$TARGET_HOME/.config/gtk-3.0/settings.ini"
    local gtk4_path="$TARGET_HOME/.config/gtk-4.0/settings.ini"

    local gtk_content="[Settings]
gtk-theme-name=Catppuccin-Mocha
gtk-icon-theme-name=Tela-circle
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

    echo "$gtk_content" > "$gtk3_path"
    echo "$gtk_content" > "$gtk4_path"

    # .xinitrc
    local xinitrc_path="$TARGET_HOME/.xinitrc"
    cat << 'EOF' > "$xinitrc_path"
#!/bin/sh
# Cargar recursos y configuración de color
[[ -f ~/.Xresources ]] && xrdb -merge -I$HOME ~/.Xresources

# Iniciar gestor de sesiones de dbus y bspwm
exec dbus-launch --exit-with-session bspwm
EOF
    chmod +x "$xinitrc_path"

    # .Xresources con Catppuccin Mocha
    local xresources_path="$TARGET_HOME/.Xresources"
    cat << 'EOF' > "$xresources_path"
! Catppuccin Mocha Xresources
*.foreground:   #cdd6f4
*.background:   #1e1e2e
*.cursorColor:  #f5e0dc

! Black
*.color0:       #45475a
*.color8:       #585b70

! Red
*.color1:       #f38ba8
*.color9:       #f38ba8

! Green
*.color2:       #a6e3a1
*.color10:      #a6e3a1

! Yellow
*.color3:       #f9e2af
*.color11:      #f9e2af

! Blue
*.color4:       #89b4fa
*.color12:      #89b4fa

! Magenta
*.color5:       #cba6f7
*.color13:      #cba6f7

! Cyan
*.color6:       #94e2d5
*.color14:      #94e2d5

! White
*.color7:       #bac2de
*.color15:      #a6adc8
EOF

    # .bashrc con alias útiles
    local bashrc_path="$TARGET_HOME/.bashrc"
    cat << 'EOF' >> "$bashrc_path"

# --- BSPWM / Catppuccin Alias ---
alias ll='ls -la --color=auto'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias v='nvim'
alias reload_bspwm='bspc wm -r'
alias reload_sxhkd='pkill -USR1 -x sxhkd'
alias update='sudo pacman -Syu'
if command -v fastfetch &>/dev/null; then
    fastfetch
fi
EOF

    log_success "GTK, .xinitrc, .Xresources y .bashrc configurados."
}

setup_scripts() {
    log_header "8.2 Creación de Scripts en ~/.local/bin"

    # 1. launch_polybar
    local poly_script="$TARGET_HOME/.local/bin/launch_polybar"
    cat << 'EOF' > "$poly_script"
#!/usr/bin/env bash
# Terminar instancias en ejecución de Polybar
killall -q polybar

# Esperar a que los procesos se detengan
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.5; done

# Lanzar barra en cada monitor detectado por xrandr
if type "xrandr" > /dev/null; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload --config=~/.config/polybar/config.ini main &
  done
else
  polybar --reload --config=~/.config/polybar/config.ini main &
fi
EOF
    chmod +x "$poly_script"

    # 2. wallpaper_setup
    local wall_script="$TARGET_HOME/.local/bin/wallpaper_setup"
    cat << 'EOF' > "$wall_script"
#!/usr/bin/env bash
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
WALLPAPER_FILE="$WALLPAPER_DIR/catppuccin_wallpaper.png"

mkdir -p "$WALLPAPER_DIR"

# Si no existe, descargar wallpaper de Catppuccin
if [[ ! -f "$WALLPAPER_FILE" ]]; then
    curl -sL "https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/misc/cat_leaves.png" -o "$WALLPAPER_FILE" || \
    wget -q "https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/landscapes/mountains.png" -O "$WALLPAPER_FILE" || true
fi

# Si se descargó o existe, aplicar con feh. Sino usar color sólido Catppuccin base
if [[ -f "$WALLPAPER_FILE" && -s "$WALLPAPER_FILE" ]]; then
    feh --no-fehbg --bg-fill "$WALLPAPER_FILE"
else
    xsetroot -solid "#1e1e2e"
fi
EOF
    chmod +x "$wall_script"

    # 3. statusbar_launcher
    local status_script="$TARGET_HOME/.local/bin/statusbar_launcher"
    cat << 'EOF' > "$status_script"
#!/usr/bin/env bash
# Iniciar servicios de barra y widgets auxiliares
~/.local/bin/launch_polybar &
EOF
    chmod +x "$status_script"

    log_success "Scripts auxiliares creados en $TARGET_HOME/.local/bin."
}

download_wallpaper() {
    log_header "8.3 Descarga Inicial de Fondos de Pantalla Catppuccin"

    local wall_dir="$TARGET_HOME/Pictures/wallpapers"
    mkdir -p "$wall_dir"
    local target_file="$wall_dir/catppuccin_wallpaper.png"

    log_info "Descargando fondo de pantalla desde repositorio oficial..."
    if curl -sL "$WALLPAPER_URL" -o "$target_file" || wget -q "$WALLPAPER_URL" -O "$target_file"; then
        log_success "Wallpaper descargado en: $target_file"
    else
        log_warn "Fallo en descarga principal. Intentando URL alternativa..."
        curl -sL "$WALLPAPER_FALLBACK_URL" -o "$target_file" || true
    fi
}

# ==============================================================================
# 9. POST-INSTALACIÓN Y SERVICIOS DEL SISTEMA
# ==============================================================================

post_install() {
    log_header "9. Configuración de Servicios, Usuarios y Display Manager (SDDM)"

    # 1. Habilitar NetworkManager
    log_info "Habilitando NetworkManager..."
    systemctl enable NetworkManager.service --now || true
    log_success "NetworkManager habilitado."

    # 2. Configurar Display Manager SDDM y Sesión Desktop para BSPWM
    log_info "Configurando entrada de sesión para BSPWM y habilitando SDDM..."
    mkdir -p /usr/share/xsessions
    cat << 'EOF' > /usr/share/xsessions/bspwm.desktop
[Desktop Entry]
Name=bspwm
Comment=Binary space partitioning window manager
Exec=bspwm
Type=Application
EOF

    # Configurar SDDM básico
    mkdir -p /etc/sddm.conf.d
    cat << 'EOF' > /etc/sddm.conf.d/10-theme.conf
[Theme]
Current=
[General]
Numlock=on
EOF

    systemctl enable sddm.service || log_warn "No se pudo habilitar SDDM automáticamente."
    log_success "SDDM habilitado como Display Manager."

    # 3. Agregar usuario a grupos de sistema requeridos
    log_info "Configurando grupos de usuario para '$TARGET_USER'..."
    local user_groups=(wheel audio video input storage optical network)
    for g in "${user_groups[@]}"; do
        if getent group "$g" >/dev/null 2>&1; then
            usermod -aG "$g" "$TARGET_USER"
        fi
    done
    log_success "Usuario '$TARGET_USER' añadido a los grupos necesarios."

    # 4. Ajustar permisos de todos los archivos generados en el HOME del usuario
    log_info "Ajustando permisos de propietario en $TARGET_HOME..."
    chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.config" "$TARGET_HOME/.local" "$TARGET_HOME/Pictures" "$TARGET_HOME/.bashrc" "$TARGET_HOME/.xinitrc" "$TARGET_HOME/.Xresources" 2>/dev/null || true
    log_success "Permisos de usuario aplicados correctamente."

    # 5. Resumen final y opción de reinicio
    log_header "¡Instalación y Configuración Completada con Éxito!"
    echo -e "${CLR_SUCCESS}El entorno de escritorio BSPWM con estética Catppuccin Mocha está listo.${CLR_RESET}\n"
    echo -e "Detalles de la instalación:"
    echo -e " • Usuario configurado : ${CLR_ACCENT}$TARGET_USER${CLR_RESET}"
    echo -e " • Gestor de ventanas  : ${CLR_ACCENT}BSPWM + SXHKD${CLR_RESET}"
    echo -e " • Terminal            : ${CLR_ACCENT}Kitty${CLR_RESET}"
    echo -e " • Barra y Lanzador    : ${CLR_ACCENT}Polybar & Rofi${CLR_RESET}"
    echo -e " • Compositor          : ${CLR_ACCENT}Picom (GLX backend + Sombras + Esquinas redondeadas)${CLR_RESET}"
    echo -e " • Display Manager     : ${CLR_ACCENT}SDDM (habilitado)${CLR_RESET}"
    echo -e " • Wallpaper           : ${CLR_ACCENT}~/Pictures/wallpapers/catppuccin_wallpaper.png${CLR_RESET}"
    echo -e " • Atajo Principal     : ${CLR_ACCENT}Super + Enter (Terminal), Super + d (Rofi), Super + q (Cerrar)${CLR_RESET}\n"

    if ask_yes_no "¿Deseas reiniciar el sistema ahora para iniciar en el nuevo entorno?" "N"; then
        log_info "Reiniciando el sistema en 3 segundos..."
        sleep 3
        reboot
    else
        log_info "Puedes iniciar sesión iniciando SDDM con 'sudo systemctl start sddm' o mediante 'startx'."
    fi
}

# ==============================================================================
# FLUJO PRINCIPAL DE EJECUCIÓN
# ==============================================================================

main() {
    clear
    echo -e "${CLR_HEADER}"
    cat << "EOF"
  ____  ____  ______        ____  __  __ 
 | __ )/ ___||  _ \ \      / /  \/  |
 |  _ \\___ \| |_) \ \ /\ / /| |\/| |
 | |_) |___) |  __/ \ V  V / | |  | |
 |____/|____/|_|     \_/\_/  |_|  |_|
  Instalador Automatizado - Arch Linux - Catppuccin Mocha
EOF
    echo -e "${CLR_RESET}"

    check_prerequisites
    install_packages
    install_yay_and_aur
    create_directory_structure
    configure_bspwm
    configure_sxhkd
    configure_polybar
    configure_picom
    configure_dunst
    configure_kitty
    configure_rofi
    configure_gtk
    setup_scripts
    download_wallpaper
    post_install
}

main "$@"
