#!/usr/bin/env bash
# ==============================================================================
# Script de Instalación y Configuración Automatizada de BSPWM (Versión 2 - Multi-Rice)
# Inspirado en zoddDev/dotfiles con soporte Theme-Swap Dinámico
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
    TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")

# ==============================================================================
# FUNCIONES DE LOGGING Y CONTROL
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

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "El instalador finalizó con código de salida: $exit_code"
        if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
            log_warn "Se creó un respaldo de tus configuraciones en: $BACKUP_DIR"
        fi
    fi
}
trap cleanup_on_error EXIT

# ==============================================================================
# 1. VERIFICACIÓN INICIAL DEL SISTEMA
# ==============================================================================

check_prerequisites() {
    log_header "1. Verificación Inicial del Entorno"

    if [[ $EUID -ne 0 ]]; then
        log_error "Este instalador debe ejecutarse con privilegios root (usa sudo ./install_bspwm_v2.sh)."
        exit 1
    fi
    log_success "Ejecutando como usuario con privilegios (root)."

    if [[ -z "$TARGET_USER" || ! -d "$TARGET_HOME" ]]; then
        log_error "No se pudo determinar el usuario normal del sistema."
        read -rp "Ingresa el nombre de usuario de tu cuenta normal: " TARGET_USER
        TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
        TARGET_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")
        if [[ ! -d "$TARGET_HOME" ]]; then
            log_error "El directorio home $TARGET_HOME no existe."
            exit 1
        fi
    fi
    log_info "Usuario objetivo: ${CLR_ACCENT}${TARGET_USER}${CLR_RESET} (Home: $TARGET_HOME)"

    log_info "Comprobando conexión a Internet..."
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null && ! ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        log_error "No se detectó conexión a Internet. Conéctate a la red e inténtalo de nuevo."
        exit 1
    fi
    log_success "Conexión a Internet confirmada."

    BACKUP_DIR="$TARGET_HOME/.config/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
    log_info "Directorio de respaldo configurado en: $BACKUP_DIR"

    if ask_yes_no "¿Deseas sincronizar y actualizar el sistema completo con 'pacman -Syu'?" "Y"; then
        log_info "Actualizando repositorios y paquetes del sistema..."
        pacman -Syu --noconfirm
        log_success "Sistema actualizado correctamente."
    else
        log_warn "Se omitió la actualización de pacman. Continuando..."
    fi
}

# ==============================================================================
# 2. INSTALACIÓN DE PAQUETES OFICIALES (PACMAN)
# ==============================================================================

install_packages() {
    log_header "2. Instalación de Paquetes Base y Entorno BSPWM Multi-Rice"

    local base_packages=(
        # Servidor X y utilidades gráficas
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

        # Lanzador, menús y compositor
        rofi
        picom

        # Notificaciones, wallpapers y capturas
        dunst
        libnotify
        feh
        scrot

        # Gestor de archivos
        thunar
        thunar-volman
        thunar-archive-plugin
        tumbler
        file-roller
        gvfs

        # Red
        networkmanager
        network-manager-applet

        # Audio (Pipewire stack completo)
        pipewire
        pipewire-pulse
        pipewire-alsa
        pipewire-jack
        wireplumber
        pavucontrol
        alsa-utils
        pamixer

        # Fuentes tipográficas completas (Nerd Fonts & Glyphs)
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

        # Herramientas de sistema y utilidades de scripts
        base-devel
        git
        curl
        wget
        unzip
        bc
        jq
        rsync
        sed
        gawk
        xdg-user-dirs
        xdg-utils
    )

    log_info "Instalando paquetes principales mediante pacman (${#base_packages[@]} paquetes)..."
    pacman -S --needed --noconfirm "${base_packages[@]}"
    log_success "Paquetes oficiales instalados con éxito."
}

# ==============================================================================
# 3. INSTALACIÓN DE AUR HELPER (YAY-BIN) Y EXTRAS
# ==============================================================================

install_yay_and_aur() {
    log_header "3. Configuración de AUR Helper (yay-bin) y Paquetes Opcionales"

    local install_yay=false
    if command -v yay &>/dev/null; then
        log_success "yay ya está instalado en el sistema."
        install_yay=true
    else
        if ask_yes_no "¿Deseas instalar el helper de AUR 'yay' (versión optimizada yay-bin)?" "Y"; then
            log_info "Preparando empaquetado de yay-bin para usuario '$TARGET_USER'..."

            local tmp_yay_dir="/tmp/yay_build_$$"
            rm -rf "$tmp_yay_dir"
            mkdir -p "$tmp_yay_dir"
            chown -R "$TARGET_USER:$TARGET_GROUP" "$tmp_yay_dir"

            if sudo -u "$TARGET_USER" git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp_yay_dir"; then
                log_info "Empaquetando yay-bin (sin compilar desde fuente)..."
                (
                    cd "$tmp_yay_dir"
                    PKGDEST="$tmp_yay_dir" sudo -u "$TARGET_USER" makepkg -s --noconfirm --nocheck --skippgpcheck
                )

                local pkg_file
                pkg_file=$(find "$tmp_yay_dir" -maxdepth 1 -name "yay-bin-*.pkg.tar.*" | head -n 1)

                if [[ -n "$pkg_file" && -f "$pkg_file" ]]; then
                    log_info "Instalando paquete: $(basename "$pkg_file")..."
                    pacman -U --noconfirm "$pkg_file"
                fi
            fi
            rm -rf "$tmp_yay_dir"

            if command -v yay &>/dev/null; then
                log_success "yay instalado y verificado exitosamente."
                install_yay=true
            else
                log_warn "No se pudo instalar yay-bin. Continuando con el flujo base."
            fi
        fi
    fi

    # Paquetes opcionales
    log_info "Opciones de software adicional:"
    local aur_packages=()

    if ask_yes_no "• ¿Instalar temas GTK e Iconos Catppuccin / Tela Circle?" "Y"; then
        if [[ "$install_yay" == true ]]; then
            aur_packages+=(catppuccin-gtk-theme-mocha tela-circle-icon-theme)
        fi
    fi

    if ask_yes_no "• ¿Instalar navegador web Firefox?" "Y"; then
        pacman -S --needed --noconfirm firefox
    fi

    if ask_yes_no "• ¿Instalar navegador web Brave (vía AUR)?" "N"; then
        if [[ "$install_yay" == true ]]; then
            aur_packages+=(brave-bin)
        fi
    fi

    if ask_yes_no "• ¿Instalar Neovim (editor de código)?" "Y"; then
        pacman -S --needed --noconfirm neovim
    fi

    if ask_yes_no "• ¿Instalar herramientas CLI (fastfetch, htop, btop)?" "Y"; then
        pacman -S --needed --noconfirm fastfetch htop btop
    fi

    if [[ ${#aur_packages[@]} -gt 0 && "$install_yay" == true ]]; then
        log_info "Instalando paquetes AUR seleccionados: ${aur_packages[*]}"
        sudo -u "$TARGET_USER" yay -S --needed --noconfirm --nocheck "${aur_packages[@]}" || log_warn "Algunos paquetes AUR no pudieron completarse."
    fi
}

# ==============================================================================
# 4. CREACIÓN DE LA ESTRUCTURA DE DIRECTORIOS MULTI-RICE
# ==============================================================================

create_directory_structure() {
    log_header "4. Creación de Estructura de Directorios Multi-Rice"

    local dirs=(
        "$TARGET_HOME/.config/bspwm"
        "$TARGET_HOME/.config/bspwm/rices"
        "$TARGET_HOME/.config/sxhkd"
        "$TARGET_HOME/.config/polybar"
        "$TARGET_HOME/.config/polybar/scripts"
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

    for d in "${dirs[@]}"; do
        if [[ -d "$d" ]]; then
            mkdir -p "$BACKUP_DIR"
            cp -ra "$d" "$BACKUP_DIR/" 2>/dev/null || true
        fi
        mkdir -p "$d"
    done

    sudo -u "$TARGET_USER" xdg-user-dirs-update 2>/dev/null || true
    log_success "Estructura de directorios generada."
}

# ==============================================================================
# 5. GENERACIÓN DEL MOTOR MULTI-RICE (TEMAS Y DEFINICIONES)
# ==============================================================================

setup_rices_engine() {
    log_header "5. Configuración del Motor Multi-Rice (Catppuccin, Nord, Dracula, Gruvbox, Doombox, Forest)"

    local rices_dir="$TARGET_HOME/.config/bspwm/rices"
    local wallpapers_dir="$TARGET_HOME/Pictures/wallpapers"

    # Lista de Rices disponibles
    local available_themes=(
        "CatppuccinMocha"
        "Nord"
        "Dracula"
        "Gruvbox"
        "Doombox"
        "Forest"
        "Horizon"
    )

    echo "${available_themes[*]}" | tr ' ' '\n' > "$TARGET_HOME/.config/bspwm/available_themes"

    # --------------------------------------------------------------------------
    # 5.1 Definición de cada Rice
    # --------------------------------------------------------------------------

    # --- 1. CATPPUCCIN MOCHA ---
    mkdir -p "$rices_dir/CatppuccinMocha"
    cat << 'EOF' > "$rices_dir/CatppuccinMocha/theme.env"
RICE_NAME="CatppuccinMocha"
BORDER_NORMAL="#45475a"
BORDER_ACTIVE="#585b70"
BORDER_FOCUSED="#89b4fa"
BORDER_PRESEL="#cba6f7"
BG_COLOR="#1e1e2e"
FG_COLOR="#cdd6f4"
ACCENT_COLOR="#89b4fa"
ALT_ACCENT="#cba6f7"
WALLPAPER_URL="https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/misc/cat_leaves.png"
EOF

    # --- 2. NORD ---
    mkdir -p "$rices_dir/Nord"
    cat << 'EOF' > "$rices_dir/Nord/theme.env"
RICE_NAME="Nord"
BORDER_NORMAL="#3b4252"
BORDER_ACTIVE="#434c5e"
BORDER_FOCUSED="#88c0d0"
BORDER_PRESEL="#81a1c1"
BG_COLOR="#2e3440"
FG_COLOR="#eceff4"
ACCENT_COLOR="#88c0d0"
ALT_ACCENT="#81a1c1"
# Colección de Wallpapers de zoddDev/Nord
WALLPAPER_URL="https://raw.githubusercontent.com/zoddDev/Nord/d6f3766b7d44ecc8622654d11ae1109f5c1cabc7/.wallpapers/nord-theme/arch-nord.png"
WALLPAPER_FALLBACK_URL="https://raw.githubusercontent.com/zoddDev/Nord/d6f3766b7d44ecc8622654d11ae1109f5c1cabc7/.wallpapers/nord-theme/nord-forest.png"
EOF

    # --- 3. DRACULA ---
    mkdir -p "$rices_dir/Dracula"
    cat << 'EOF' > "$rices_dir/Dracula/theme.env"
RICE_NAME="Dracula"
BORDER_NORMAL="#44475a"
BORDER_ACTIVE="#6272a4"
BORDER_FOCUSED="#bd93f9"
BORDER_PRESEL="#ff79c6"
BG_COLOR="#282a36"
FG_COLOR="#f8f8f2"
ACCENT_COLOR="#bd93f9"
ALT_ACCENT="#ff79c6"
WALLPAPER_URL="https://raw.githubusercontent.com/dracula/wallpaper/master/dracula-lake.png"
EOF

    # --- 4. GRUVBOX ---
    mkdir -p "$rices_dir/Gruvbox"
    cat << 'EOF' > "$rices_dir/Gruvbox/theme.env"
RICE_NAME="Gruvbox"
BORDER_NORMAL="#3c3836"
BORDER_ACTIVE="#504945"
BORDER_FOCUSED="#d79921"
BORDER_PRESEL="#fe8019"
BG_COLOR="#282828"
FG_COLOR="#ebdbb2"
ACCENT_COLOR="#d79921"
ALT_ACCENT="#b8bb26"
WALLPAPER_URL="https://raw.githubusercontent.com/AngelJumbo/gruvbox-wallpapers/main/wallpapers/anime-girl-gruvbox.png"
EOF

    # --- 5. DOOMBOX ---
    mkdir -p "$rices_dir/Doombox"
    cat << 'EOF' > "$rices_dir/Doombox/theme.env"
RICE_NAME="Doombox"
BORDER_NORMAL="#282c34"
BORDER_ACTIVE="#3f444a"
BORDER_FOCUSED="#ff6c6b"
BORDER_PRESEL="#c678dd"
BG_COLOR="#1c1f24"
FG_COLOR="#bbc2cf"
ACCENT_COLOR="#ff6c6b"
ALT_ACCENT="#51afef"
WALLPAPER_URL="https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/landscapes/mountains.png"
EOF

    # --- 6. FOREST ---
    mkdir -p "$rices_dir/Forest"
    cat << 'EOF' > "$rices_dir/Forest/theme.env"
RICE_NAME="Forest"
BORDER_NORMAL="#2d353b"
BORDER_ACTIVE="#343f44"
BORDER_FOCUSED="#a7c080"
BORDER_PRESEL="#83c092"
BG_COLOR="#232a2e"
FG_COLOR="#d3c6aa"
ACCENT_COLOR="#a7c080"
ALT_ACCENT="#dbbc7f"
WALLPAPER_URL="https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/misc/cat_leaves.png"
EOF

    # --- 7. HORIZON ---
    mkdir -p "$rices_dir/Horizon"
    cat << 'EOF' > "$rices_dir/Horizon/theme.env"
RICE_NAME="Horizon"
BORDER_NORMAL="#232530"
BORDER_ACTIVE="#2e303e"
BORDER_FOCUSED="#e95678"
BORDER_PRESEL="#fab795"
BG_COLOR="#1a1c23"
FG_COLOR="#fadad1"
ACCENT_COLOR="#e95678"
ALT_ACCENT="#26bbd9"
WALLPAPER_URL="https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/landscapes/mountains.png"
EOF

    # Establecer tema inicial
    echo "CatppuccinMocha" > "$TARGET_HOME/.config/bspwm/current_rice"

    # Descargar galería de wallpapers de Catppuccin y Nord (desde repositorio zoddDev)
    log_info "Descargando galería de wallpapers temáticos..."
    local nord_wp_base="https://raw.githubusercontent.com/zoddDev/Nord/d6f3766b7d44ecc8622654d11ae1109f5c1cabc7/.wallpapers/nord-theme"
    local nord_wp_dir="$wallpapers_dir/nord"
    mkdir -p "$nord_wp_dir"

    local nord_wallpapers=(
        "arch-nord.png"
        "nord-forest.png"
        "cyberpunk-cafe.png"
        "guts_wallpaper.png"
        "japanese-street.png"
        "norse_arch.png"
        "80s-nord.png"
        "cyberpunk-girl-nord-wallpaper.png"
    )

    for wp in "${nord_wallpapers[@]}"; do
        curl -sL "$nord_wp_base/$wp" -o "$nord_wp_dir/$wp" || true
    done

    # Copiar fondo principal de Nord y Catppuccin
    cp "$nord_wp_dir/arch-nord.png" "$wallpapers_dir/Nord.png" 2>/dev/null || true
    curl -sL "https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/misc/cat_leaves.png" -o "$wallpapers_dir/CatppuccinMocha.png" || true
    cp "$wallpapers_dir/CatppuccinMocha.png" "$wallpapers_dir/current_wallpaper.png" 2>/dev/null || true

    log_success "Colección de Rices y galería de Wallpapers de Nord descargada con éxito."
}

# ==============================================================================
# 6. CONFIGURACIÓN DEL SCRIPT THEME-SWAP Y SCRIPTS DE PRODUCTIVIDAD
# ==============================================================================

setup_productivity_scripts() {
    log_header "6. Instalación de Scripts de Productividad y Theme-Swap (~/.local/bin/)"

    # --------------------------------------------------------------------------
    # 6.1 theme-swap: Motor dinámico de cambio de estilo
    # --------------------------------------------------------------------------
    local theme_swap_script="$TARGET_HOME/.local/bin/theme-swap"
    cat << 'EOF' > "$theme_swap_script"
#!/usr/bin/env bash
# ==============================================================================
# Theme-Swap: Cambio dinámico de Rices en BSPWM
# ==============================================================================

RICES_DIR="$HOME/.config/bspwm/rices"
CURRENT_RICE_FILE="$HOME/.config/bspwm/current_rice"
AVAILABLE_THEMES_FILE="$HOME/.config/bspwm/available_themes"
WALLPAPER_DIR="$HOME/Pictures/wallpapers"

CURRENT_RICE=$(cat "$CURRENT_RICE_FILE" 2>/dev/null || echo "CatppuccinMocha")

# Función para selector interactivo de Rofi
rofi_selector() {
    local themes
    themes=$(cat "$AVAILABLE_THEMES_FILE")
    echo "$themes" | rofi -dmenu -i -p "  Rice Selector " -font "JetBrains Mono Nerd Font 12"
}

# Procesamiento de argumentos
TARGET_THEME="$1"
if [[ -z "$TARGET_THEME" || "$TARGET_THEME" == "-r" || "$TARGET_THEME" == "--rofi" ]]; then
    TARGET_THEME=$(rofi_selector)
fi

[[ -z "$TARGET_THEME" ]] && exit 0

if [[ ! -d "$RICES_DIR/$TARGET_THEME" ]]; then
    notify-send -u critical "Theme Swap" "El tema '$TARGET_THEME' no existe."
    exit 1
fi

if [[ "$TARGET_THEME" == "$CURRENT_RICE" && "$2" != "--force" ]]; then
    notify-send -u low "Theme Swap" "Ya estás usando el tema '$TARGET_THEME'."
    exit 0
fi

# Cargar variables del nuevo Rice
source "$RICES_DIR/$TARGET_THEME/theme.env"

# 1. Actualizar colores de BSPWM en caliente
bspc config normal_border_color   "$BORDER_NORMAL"
bspc config active_border_color   "$BORDER_ACTIVE"
bspc config focused_border_color  "$BORDER_FOCUSED"
bspc config presel_feedback_color "$BORDER_PRESEL"

# 2. Actualizar wallpaper
mkdir -p "$WALLPAPER_DIR"
WP_FILE="$WALLPAPER_DIR/${TARGET_THEME}.png"
if [[ ! -f "$WP_FILE" && -n "$WALLPAPER_URL" ]]; then
    notify-send -u low "Theme Swap" "Descargando wallpaper para $TARGET_THEME..."
    curl -sL "$WALLPAPER_URL" -o "$WP_FILE" || true
fi

if [[ -f "$WP_FILE" && -s "$WP_FILE" ]]; then
    feh --no-fehbg --bg-fill "$WP_FILE"
    cp "$WP_FILE" "$WALLPAPER_DIR/current_wallpaper.png" 2>/dev/null || true
else
    xsetroot -solid "$BG_COLOR"
fi

# 3. Guardar estado actual
echo "$TARGET_THEME" > "$CURRENT_RICE_FILE"

# 4. Regenerar configuraciones dinámicas de Kitty, Dunst y Polybar
~/.local/bin/apply_theme_configs "$TARGET_THEME"

# 5. Reiniciar Polybar y Dunst
~/.local/bin/launch_polybar &
pkill -x dunst; dunst &

notify-send -u normal "Theme Swap" "Tema cambiado con éxito a: $TARGET_THEME"
EOF
    chmod +x "$theme_swap_script"

    # --------------------------------------------------------------------------
    # 6.2 apply_theme_configs: Genera configs en base al tema activo
    # --------------------------------------------------------------------------
    local apply_configs_script="$TARGET_HOME/.local/bin/apply_theme_configs"
    cat << 'EOF' > "$apply_configs_script"
#!/usr/bin/env bash
THEME_NAME="${1:-$(cat $HOME/.config/bspwm/current_rice 2>/dev/null || echo 'CatppuccinMocha')}"
THEME_ENV="$HOME/.config/bspwm/rices/$THEME_NAME/theme.env"

[[ -f "$THEME_ENV" ]] && source "$THEME_ENV"

# 1. Kitty config
cat << EOKITTY > "$HOME/.config/kitty/kitty.conf"
font_family      JetBrains Mono Nerd Font
bold_font        auto
italic_font      auto
font_size        12.0

background_opacity 0.88
window_padding_width 12
hide_window_decorations yes
confirm_os_window_close 0

foreground              $FG_COLOR
background              $BG_COLOR
cursor                  $ACCENT_COLOR
cursor_text_color       $BG_COLOR
selection_background    $BORDER_ACTIVE
selection_foreground    $FG_COLOR

active_border_color     $BORDER_FOCUSED
inactive_border_color   $BORDER_NORMAL

# ANSI Colors
color0  $BORDER_NORMAL
color8  $BORDER_ACTIVE
color1  #f38ba8
color9  #f38ba8
color2  #a6e3a1
color10 #a6e3a1
color3  #f9e2af
color11 #f9e2af
color4  $ACCENT_COLOR
color12 $ACCENT_COLOR
color5  $ALT_ACCENT
color13 $ALT_ACCENT
color6  #94e2d5
color14 #94e2d5
color7  $FG_COLOR
color15 #ffffff
EOKITTY

# 2. Dunst config
cat << EODUNST > "$HOME/.config/dunst/dunstrc"
[global]
    monitor = 0
    follow = mouse
    width = 320
    height = 100
    origin = top-right
    offset = 15x45
    transparency = 15
    padding = 12
    horizontal_padding = 12
    frame_width = 2
    frame_color = "$ACCENT_COLOR"
    gap_size = 10
    font = JetBrains Mono Nerd Font 11
    corner_radius = 10
    icon_position = left
    min_icon_size = 24
    max_icon_size = 48

[urgency_low]
    background = "$BG_COLOR"
    foreground = "$FG_COLOR"
    frame_color = "$ACCENT_COLOR"
    timeout = 5

[urgency_normal]
    background = "$BG_COLOR"
    foreground = "$FG_COLOR"
    frame_color = "$ACCENT_COLOR"
    timeout = 8

[urgency_critical]
    background = "$BG_COLOR"
    foreground = "#f38ba8"
    frame_color = "#f38ba8"
    timeout = 0
EODUNST
EOF
    chmod +x "$apply_configs_script"

    # --------------------------------------------------------------------------
    # 6.3 floating-term: Terminal flotante centrado rápido
    # --------------------------------------------------------------------------
    local float_term_script="$TARGET_HOME/.local/bin/floating-term"
    cat << 'EOF' > "$float_term_script"
#!/usr/bin/env bash
kitty --class floating_kitty -e bash -c "fastfetch 2>/dev/null || true; bash"
EOF
    chmod +x "$float_term_script"

    # --------------------------------------------------------------------------
    # 6.4 screenshot-tool: Capturas de pantalla enriquecidas
    # --------------------------------------------------------------------------
    local sc_script="$TARGET_HOME/.local/bin/screenshot-tool"
    cat << 'EOF' > "$sc_script"
#!/usr/bin/env bash
SC_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SC_DIR"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
FILE="$SC_DIR/Screenshot_${TIMESTAMP}.png"

case "$1" in
    full)
        scrot "$FILE"
        xclip -selection clipboard -t image/png < "$FILE"
        notify-send -u low "Captura completa" "Guardada en $FILE y copiada al portapapeles."
        ;;
    area|select)
        scrot -s "$FILE"
        xclip -selection clipboard -t image/png < "$FILE"
        notify-send -u low "Captura de región" "Copiada al portapapeles y guardada en $FILE."
        ;;
    window)
        scrot -u "$FILE"
        xclip -selection clipboard -t image/png < "$FILE"
        notify-send -u low "Captura de ventana" "Copiada al portapapeles."
        ;;
    *)
        scrot "$FILE"
        ;;
esac
EOF
    chmod +x "$sc_script"

    # --------------------------------------------------------------------------
    # 6.5 rofi-power: Menú de energía Rofi
    # --------------------------------------------------------------------------
    local power_script="$TARGET_HOME/.local/bin/rofi-power"
    cat << 'EOF' > "$power_script"
#!/usr/bin/env bash
chosen=$(echo -e "󰐥 Apagar\n󰜉 Reiniciar\n󰗽 Cerrar Sesión\n󰌾 Bloquear\n󰤄 Suspender" | rofi -dmenu -i -p " 󰐥 Power Menu " -font "JetBrains Mono Nerd Font 12")

case "$chosen" in
    "󰐥 Apagar") systemctl poweroff ;;
    "󰜉 Reiniciar") systemctl reboot ;;
    "󰗽 Cerrar Sesión") bspc quit ;;
    "󰌾 Bloquear") xsetroot -solid "#11111b" ;;
    "󰤄 Suspender") systemctl suspend ;;
esac
EOF
    chmod +x "$power_script"

    # --------------------------------------------------------------------------
    # 6.6 launch_polybar: Detección multi-monitor y recarga
    # --------------------------------------------------------------------------
    local poly_script="$TARGET_HOME/.local/bin/launch_polybar"
    cat << 'EOF' > "$poly_script"
#!/usr/bin/env bash
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.3; done

if type "xrandr" > /dev/null; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload --config=~/.config/polybar/config.ini main &
  done
else
  polybar --reload --config=~/.config/polybar/config.ini main &
fi
EOF
    chmod +x "$poly_script"

    # --------------------------------------------------------------------------
    # 6.8 wallpaper-menu: Selector visual de wallpapers con Rofi
    # --------------------------------------------------------------------------
    local wp_menu_script="$TARGET_HOME/.local/bin/wallpaper-menu"
    cat << 'EOF' > "$wp_menu_script"
#!/usr/bin/env bash
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
WALLPAPERS=$(find "$WALLPAPER_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -exec basename {} \;)

CHOSEN=$(echo "$WALLPAPERS" | rofi -dmenu -i -p " 󰸉 Wallpaper Selector " -font "JetBrains Mono Nerd Font 12")

if [[ -n "$CHOSEN" ]]; then
    FULL_PATH=$(find "$WALLPAPER_DIR" -type f -name "$CHOSEN" | head -n 1)
    if [[ -f "$FULL_PATH" ]]; then
        feh --no-fehbg --bg-fill "$FULL_PATH"
        cp "$FULL_PATH" "$WALLPAPER_DIR/current_wallpaper.png" 2>/dev/null || true
        notify-send -u low "Wallpaper" "Fondo de pantalla actualizado: $CHOSEN"
    fi
fi
EOF
    chmod +x "$wp_menu_script"

    log_success "Scripts de productividad instalados en ~/.local/bin/."
}

# ==============================================================================
# 7. CONFIGURACIÓN DE BSPWM, SXHKD Y POLYBAR
# ==============================================================================

configure_bspwm_sxhkd_polybar() {
    log_header "7. Configuración de BSPWM, SXHKD y Polybar Dinámica"

    # 7.1 bspwmrc
    local bspwmrc_path="$TARGET_HOME/.config/bspwm/bspwmrc"
    cat << 'EOF' > "$bspwmrc_path"
#!/usr/bin/env bash
# ==============================================================================
# BSPWM Principal - Soporte Multi-Rice Dinámico
# ==============================================================================

# 1. Iniciar gestor de atajos sxhkd
pgrep -x sxhkd > /dev/null || sxhkd &

# 2. Configurar escritorios / Workspaces
if xrandr -q | grep " connected" | grep -q "primary"; then
    PRIMARY_MONITOR=$(xrandr -q | grep " connected" | grep "primary" | awk '{print $1}')
    bspc monitor "$PRIMARY_MONITOR" -d "I:Web" "II:Term" "III:Code" "IV:Misc"
else
    for monitor in $(xrandr --query | grep " connected" | cut -d" " -f1); do
        bspc monitor "$monitor" -d "I:Web" "II:Term" "III:Code" "IV:Misc"
    done
fi

# 3. Cargar colores del tema activo
CURRENT_RICE=$(cat ~/.config/bspwm/current_rice 2>/dev/null || echo "CatppuccinMocha")
THEME_ENV="$HOME/.config/bspwm/rices/$CURRENT_RICE/theme.env"
[[ -f "$THEME_ENV" ]] && source "$THEME_ENV"

bspc config border_width         2
bspc config window_gap          10
bspc config split_ratio          0.52

bspc config normal_border_color   "${BORDER_NORMAL:-#45475a}"
bspc config active_border_color   "${BORDER_ACTIVE:-#585b70}"
bspc config focused_border_color  "${BORDER_FOCUSED:-#89b4fa}"
bspc config presel_feedback_color "${BORDER_PRESEL:-#cba6f7}"

bspc config focus_follows_pointer true
bspc config pointer_modifier      mod4
bspc config pointer_action1       move
bspc config pointer_action2       resize_side
bspc config pointer_action3       resize_corner

bspc config top_padding           32
bspc config bottom_padding        4
bspc config left_padding          4
bspc config right_padding         4

# 4. Reglas de Ventanas
bspc rule -a Rofi state=floating center=true
bspc rule -a floating_kitty state=floating center=true rectangle=900x550+0+0
bspc rule -a Lxappearance state=floating center=true
bspc rule -a Pavucontrol state=floating center=true
bspc rule -a Thunar state=floating center=true
bspc rule -a File-roller state=floating center=true
bspc rule -a Feh state=floating center=true

bspc rule -a firefox desktop='^1' follow=on
bspc rule -a Brave-browser desktop='^1' follow=on
bspc rule -a Code desktop='^3' follow=on

# 5. Programas de Autostart
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
pgrep -x picom > /dev/null || picom --config ~/.config/picom/picom.conf -b
pgrep -x dunst > /dev/null || dunst &
pgrep -x nm-applet > /dev/null || nm-applet &

# Fondo de pantalla y Polybar
~/.local/bin/wallpaper_setup &
~/.local/bin/launch_polybar &
xsetroot -cursor_name left_ptr &
EOF
    chmod +x "$bspwmrc_path"

    # 7.2 sxhkdrc
    local sxhkdrc_path="$TARGET_HOME/.config/sxhkd/sxhkdrc"
    cat << 'EOF' > "$sxhkdrc_path"
# ==============================================================================
# SXHKD Keybindings - BSPWM Multi-Rice
# Modkey: Super (Windows)
# ==============================================================================

# --- Aplicaciones & Terminal ---
super + Return
    kitty

# Terminal flotante rápido
super + shift + Return
    ~/.local/bin/floating-term

# Lanzadores Rofi
super + d
    rofi -show drun -show-icons

super + r
    rofi -show run

super + w
    rofi -show window

# Gestor de archivos
super + e
    thunar

# --- Theme Swap, Wallpapers & Power Menu ---
# Cambiar de Rice al vuelo con selector visual Rofi
super + shift + t
    ~/.local/bin/theme-swap -r

# Selector de Wallpapers con Rofi
super + ctrl + w
    ~/.local/bin/wallpaper-menu

# Menú de Apagado / Energía
super + x
    ~/.local/bin/rofi-power

# --- Gestión de Ventanas & Layouts ---
super + q
    bspc node -c

super + shift + q
    bspc node -k

super + alt + r
    bspc wm -r; pkill -USR1 -x sxhkd

super + m
    bspc desktop -l next

super + t
    bspc node -t tiled

super + f
    bspc node -t fullscreen

super + space
    bspc node -t ~floating

# Navegación y movimiento (Vim Keys)
super + {h,j,k,l}
    bspc node -f {west,south,north,east}

super + shift + {h,j,k,l}
    bspc node -s {west,south,north,east}

# Workspaces {1-4}
super + {1,2,3,4}
    bspc desktop -f '^{1,2,3,4}'

super + shift + {1,2,3,4}
    bspc node -d '^{1,2,3,4}' --follow

# Gaps dinámicos
super + ctrl + l
    bspc config window_gap $(( $(bspc config window_gap) + 2 ))

super + ctrl + h
    bspc config window_gap $(( $(bspc config window_gap) > 2 ? $(bspc config window_gap) - 2 : 0 ))

# --- Multimedia (Pipewire / Pulse) ---
XF86AudioRaiseVolume
    pactl set-sink-volume @DEFAULT_SINK@ +5%

XF86AudioLowerVolume
    pactl set-sink-volume @DEFAULT_SINK@ -5%

XF86AudioMute
    pactl set-sink-mute @DEFAULT_SINK@ toggle

# --- Capturas de Pantalla ---
Print
    ~/.local/bin/screenshot-tool full

super + shift + s
    ~/.local/bin/screenshot-tool area

super + Print
    ~/.local/bin/screenshot-tool window
EOF

    # 7.3 Polybar config con módulo Theme-Swap (icono del pincel)
    local polybar_config="$TARGET_HOME/.config/polybar/config.ini"
    cat << 'EOF' > "$polybar_config"
; ==============================================================================
; Polybar Configuration - Multi-Rice Adaptable
; ==============================================================================

[colors]
base        = #1e1e2e
surface0    = #313244
surface1    = #45475a
surface2    = #585b70
text        = #cdd6f4
subtext0    = #a6adc8
blue        = #89b4fa
mauve       = #cba6f7
green       = #a6e3a1
yellow      = #f9e2af
red         = #f38ba8
peach       = #fab387
teal        = #94e2d5
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

modules-left = theme_swap xworkspaces xwindow
modules-center = date
modules-right = pulseaudio memory cpu network battery powermenu tray

cursor-click = pointer
cursor-scroll = ns-resize
enable-ipc = true
wm-restack = bspwm

; ------------------------------------------------------------------------------
; MÓDULO THEME SWAP (Icono de Brocha / Pincel)
; ------------------------------------------------------------------------------
[module/theme_swap]
type = custom/text
format = "  "
format-foreground = ${colors:mauve}
format-background = ${colors:surface0}
format-padding = 1
click-left = ~/.local/bin/theme-swap -r &

[module/powermenu]
type = custom/text
format = " 󰐥 "
format-foreground = ${colors:red}
click-left = ~/.local/bin/rofi-power &

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
label-urgent-foreground = ${colors:base}
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

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "󰻠 "
format-prefix-foreground = ${colors:yellow}
label = %percentage:2%%

[module/network]
type = internal/network
interface-type = wired,wireless
interval = 3.0
format-connected-prefix = "󰤨 "
format-connected-prefix-foreground = ${colors:teal}
format-connected = <label-connected>
label-connected = %netspeed%

format-disconnected-prefix = "󰤭 "
format-disconnected-prefix-foreground = ${colors:red}
label-disconnected = "Off"

[module/date]
type = internal/date
interval = 1
date = %a %d %b
time = %H:%M:%S
format-prefix = "󰥔 "
format-prefix-foreground = ${colors:mauve}
label = %date% %time%

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

    log_success "BSPWM, SXHKD y Polybar configurados."
}

# ==============================================================================
# 8. CONFIGURACIÓN DE PICOM, ROFI Y GTK
# ==============================================================================

configure_picom_rofi_gtk() {
    log_header "8. Configuración de Picom, Rofi y GTK"

    # 8.1 Picom
    local picom_path="$TARGET_HOME/.config/picom/picom.conf"
    cat << 'EOF' > "$picom_path"
backend = "glx";
glx-no-stencil = true;
glx-copy-from-front = false;
vsync = true;

shadow = true;
shadow-radius = 8;
shadow-offset-x = -8;
shadow-offset-y = -8;
shadow-opacity = 0.5;
shadow-exclude = [
  "name = 'Notification'",
  "class_g = 'Polybar'",
  "_GTK_FRAME_EXTENTS@:c"
];

active-opacity = 1.0;
inactive-opacity = 0.88;
frame-opacity = 1.0;

opacity-rule = [
  "85:class_g = 'kitty'",
  "90:class_g = 'Rofi'",
  "90:class_g = 'Thunar'",
  "100:fullscreen"
];

corner-radius = 10;
rounded-corners-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "class_g = 'Polybar'"
];

fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
fade-delta = 4;
EOF

    # 8.2 Rofi Theme
    local rofi_path="$TARGET_HOME/.config/rofi/config.rasi"
    cat << 'EOF' > "$rofi_path"
configuration {
    modi: "drun,run,window";
    lines: 7;
    font: "JetBrains Mono Nerd Font 12";
    show-icons: true;
    icon-theme: "Tela-circle";
    terminal: "kitty";
    drun-display-format: "{icon} {name}";
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
    grey: #6c7086;
    background-color: @bg-col;
}

element-text, element-icon , mode-switcher {
    background-color: inherit;
    text-color:       inherit;
}

window {
    width: 620px;
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
    padding: 6px;
    background-color: @bg-col;
    text-color: @fg-col;
    border-radius: 6px;
}

element-icon {
    size: 24px;
    margin: 0 10px 0 0;
}

element selected {
    background-color: @selected-col;
    text-color: @blue;
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

    # 8.3 GTK & xinitrc
    local gtk3_path="$TARGET_HOME/.config/gtk-3.0/settings.ini"
    local gtk4_path="$TARGET_HOME/.config/gtk-4.0/settings.ini"
    local gtk_content="[Settings]
gtk-theme-name=Catppuccin-Mocha
gtk-icon-theme-name=Tela-circle
gtk-font-name=JetBrains Mono Nerd Font 11
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
"
    echo "$gtk_content" > "$gtk3_path"
    echo "$gtk_content" > "$gtk4_path"

    local xinitrc_path="$TARGET_HOME/.xinitrc"
    cat << 'EOF' > "$xinitrc_path"
#!/bin/sh
[[ -f ~/.Xresources ]] && xrdb -merge -I$HOME ~/.Xresources
exec dbus-launch --exit-with-session bspwm
EOF
    chmod +x "$xinitrc_path"

    # Generar configs iniciales del tema
    sudo -u "$TARGET_USER" "$TARGET_HOME/.local/bin/apply_theme_configs" "CatppuccinMocha"

    log_success "Picom, Rofi y GTK configurados."
}

# ==============================================================================
# 9. POST-INSTALACIÓN, SERVICIOS Y SDDM
# ==============================================================================

post_install() {
    log_header "9. Habilitación de Servicios, Usuarios y Display Manager (SDDM)"

    log_info "Habilitando NetworkManager..."
    systemctl enable NetworkManager.service --now || true

    log_info "Configurando sesión BSPWM para SDDM..."
    mkdir -p /usr/share/xsessions
    cat << 'EOF' > /usr/share/xsessions/bspwm.desktop
[Desktop Entry]
Name=bspwm
Comment=Binary space partitioning window manager
Exec=bspwm
Type=Application
EOF

    mkdir -p /etc/sddm.conf.d
    cat << 'EOF' > /etc/sddm.conf.d/10-theme.conf
[Theme]
Current=
[General]
Numlock=on
EOF
    systemctl enable sddm.service || true
    log_success "SDDM y NetworkManager configurados."

    log_info "Configurando grupos de usuario..."
    local user_groups=(wheel audio video input storage optical network)
    for g in "${user_groups[@]}"; do
        if getent group "$g" >/dev/null 2>&1; then
            usermod -aG "$g" "$TARGET_USER"
        fi
    done

    log_info "Aplicando permisos a dotfiles en $TARGET_HOME..."
    chown -R "$TARGET_USER:$TARGET_GROUP" \
        "$TARGET_HOME/.config" \
        "$TARGET_HOME/.local" \
        "$TARGET_HOME/Pictures" \
        "$TARGET_HOME/.bashrc" \
        "$TARGET_HOME/.xinitrc" 2>/dev/null || true

    log_header "¡Instalación Versión 2 Multi-Rice Completada!"
    echo -e "${CLR_SUCCESS}El entorno BSPWM Multi-Rice está listo para usar.${CLR_RESET}\n"
    echo -e "Características principales instaladas:"
    echo -e " • ${CLR_ACCENT}Theme-Swap Dinámico${CLR_RESET}   : Presiona ${CLR_ACCENT}Super + Shift + t${CLR_RESET} o haz click en el icono  de Polybar."
    echo -e " • ${CLR_ACCENT}Rices Incluidos${CLR_RESET}        : CatppuccinMocha, Nord, Dracula, Gruvbox, Doombox, Forest, Horizon."
    echo -e " • ${CLR_ACCENT}Terminal Flotante${CLR_RESET}      : ${CLR_ACCENT}Super + Shift + Return${CLR_RESET} (Kitty centrado)."
    echo -e " • ${CLR_ACCENT}Menú de Apagado${CLR_RESET}        : ${CLR_ACCENT}Super + x${CLR_RESET} (Rofi power menu)."
    echo -e " • ${CLR_ACCENT}Capturas de Pantalla${CLR_RESET}   : ${CLR_ACCENT}Print${CLR_RESET} (Completa), ${CLR_ACCENT}Super + Shift + s${CLR_RESET} (Selección)."
    echo -e " • ${CLR_ACCENT}Lanzador de Apps${CLR_RESET}       : ${CLR_ACCENT}Super + d${CLR_RESET} (Rofi drun)."
    echo -e " • ${CLR_ACCENT}Display Manager${CLR_RESET}        : SDDM habilitado al inicio.\n"

    if ask_yes_no "¿Deseas reiniciar el sistema ahora para acceder al nuevo entorno?" "N"; then
        log_info "Reiniciando el sistema en 3 segundos..."
        sleep 3
        reboot
    else
        log_info "Puedes iniciar sesión iniciando SDDM con 'sudo systemctl start sddm' o con 'startx'."
    fi
}

# ==============================================================================
# FLUJO PRINCIPAL
# ==============================================================================

main() {
    clear
    echo -e "${CLR_HEADER}"
    cat << "EOF"
  ____  ____  ______        ____  __  __   __     ______  
 | __ )/ ___||  _ \ \      / /  \/  |  \ \   / /___ \ 
 |  _ \\___ \| |_) \ \ /\ / /| |\/| |   \ \ / /  __) |
 | |_) |___) |  __/ \ V  V / | |  | |    \ V /  / __/ 
 |____/|____/|_|     \_/\_/  |_|  |_|     \_/  |_____|
   BSPWM Multi-Rice Automated Installer - Arch Linux
EOF
    echo -e "${CLR_RESET}"

    check_prerequisites
    install_packages
    install_yay_and_aur
    create_directory_structure
    setup_rices_engine
    setup_productivity_scripts
    configure_bspwm_sxhkd_polybar
    configure_picom_rofi_gtk
    post_install
}

main "$@"
