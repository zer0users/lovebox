#!/usr/bin/env bash
# LoveBox – quick installer with ♥
#   Installs the LoveBox CLI, QEMU and desktop integration on most major
#   Linux distributions.  Tested on Arch, Debian/Ubuntu, Fedora, and openSUSE.
# -----------------------------------------------------------------------------
set -euo pipefail

############################
#  Helper / UX functions  #
############################
info()  { printf "\e[1;34m› %s\e[0m\n" "$*"; }
success(){ printf "\e[1;32m✔ %s\e[0m\n" "$*"; }
warn()  { printf "\e[1;33m⚠ %s\e[0m\n" "$*"; }
error() { printf "\e[1;31m✖ %s\e[0m\n" "$*" >&2; exit 1; }

# Ask the user an interactive Y/N question with a default answer (y)
confirm() {
  local prompt="${2:-y}" _reply
  while true; do
    read -rp "${1} [y/N]: " _reply </dev/tty || true
    _reply=${_reply:-$prompt}
    case "${_reply,,}" in
      y|yes) return 0;;
      n|no)  return 1;;
    esac
  done
}

#################################
#  Ensure running with elevated  #
#################################
if (( EUID != 0 )); then
  warn "This installer needs root privileges. Re‑executing with sudo…"
  exec sudo -E "$0" "$@"
fi

#################################
#  Detect package manager       #
#################################
PM=""
install_pkgs() { :; } # stub – replaced below per‑PM

. /etc/os-release || error "Cannot read /etc/os-release – unsupported system?"
case "$ID" in
  arch|manjaro|endeavouros)
    PM="pacman" ; install_pkgs(){ pacman -Sy --noconfirm "$@"; } ;;
  debian|ubuntu|linuxmint|pop|elementary)
    PM="apt"    ; install_pkgs(){ apt-get update -y && apt-get install -y "$@"; } ;;
  fedora)
    PM="dnf"    ; install_pkgs(){ dnf install -y "$@"; } ;;
  opensuse*|suse|sles)
    PM="zypper" ; install_pkgs(){ zypper --non-interactive install "$@"; } ;;
  *)
    warn "Unsupported distro – attempting best‑effort install with whichever PM is available."
    for c in pacman apt dnf zypper; do command -v $c >/dev/null && { PM=$c; break; }; done
    [[ -n $PM ]] || error "No known package manager found."
    ;;
esac
info "Detected distribution: $PRETTY_NAME (package manager: $PM)"

#################################
#  Check existing installation  #
#################################
if command -v lovebox >/dev/null 2>&1; then
  warn "You have already installed LoveBox!"
  if ! confirm "Would you like to reinstall it with love?" y ; then
    success "Leaving existing installation untouched. Have a lovely day! 💚"
    exit 0
  fi
fi

#################################
#  Install dependencies         #
#################################
info "Installing QEMU and Python 3…"
case "$PM" in
  pacman)  install_pkgs qemu-full python ;;
  apt)     install_pkgs qemu-system-x86 qemu-utils python3 python3-venv ;;
  dnf)     install_pkgs @virtualization python3 ;;
  zypper)  install_pkgs qemu-full python3 ;;
  *)       error "Package logic for $PM not implemented." ;;
esac
success "Dependencies installed."

#################################
#  Install LoveBox CLI          #
#################################
SCRIPT_SRC="$(dirname "$(readlink -f "$0")")/lovebox"
[[ -f $SCRIPT_SRC ]] || error "Could not find lovebox script next to installer at: $SCRIPT_SRC"

install -Dm755 "$SCRIPT_SRC" /usr/local/bin/lovebox
success "Installed LoveBox CLI to /usr/local/bin/lovebox"

#################################
#  Desktop integration (MIME + .desktop)
#################################
info "Setting up desktop integration…"
# MIME type XML
a="/usr/share/mime/packages/lovebox.xml"
cat > "$a" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-lovebox">
    <comment>LoveBox virtual machine package</comment>
    <icon name="virtualbox"/>
    <glob pattern="*.box"/>
  </mime-type>
</mime-info>
XML
update-mime-database /usr/share/mime >/dev/null 2>&1 || true

# .desktop launcher
b="/usr/share/applications/lovebox.desktop"
cat > "$b" <<'DESK'
[Desktop Entry]
Type=Application
Name=LoveBox
Comment=Run LoveBox virtual machines with love ♥
Exec=lovebox %f
Icon=virtualbox
MimeType=application/x-lovebox;
Terminal=false
Categories=System;Emulator;
DESK
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
success "Desktop launcher created (lovebox.desktop)"

#################################
#  Finish line!                 #
#################################
success "LoveBox is installed with love! Try opening a .box file from your file manager, or run: lovebox run MyBox.box 💖"
