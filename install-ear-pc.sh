#!/usr/bin/env bash
# Ear PC — universal Linux installer (Debian, Ubuntu, Fedora, Arch, ...)
# Installs Omar's Ear PC build and its pieces on PATH + app menu:
#   ~/.local/share/ear-pc               app files (main.py, bluetooth.py, res/, ...)
#   ~/.local/bin/ear-pc                 launcher (cd's to the app dir, runs main.py in the venv)
#   ~/.local/share/applications/ear-pc.desktop  desktop entry ("Ear PC")
#
# Usage:
#   bash install-ear-pc.sh [--url URL] [--app-dir DIR] [--bin-dir DIR] \
#                          [--desktop-dir DIR] [--no-start]
#
# Options/env:
#   EAR_PC_TARBALL_URL — tarball URL (or local path). Required; no default yet.
#   --app-dir          — install location for the app (default ~/.local/share/ear-pc)
#   --bin-dir          — dir for the launcher (default ~/.local/bin)
#   --desktop-dir      — dir for the desktop entry (default ~/.local/share/applications)
#   --no-start         — install only, don't launch the app
#
# After install: run `ear-pc` to open the app, or find "Ear PC" in your app menu.
set -euo pipefail

TARBALL_URL="${EAR_PC_TARBALL_URL:-https://github.com/GFXOmar/Ear-Pc-Linux/releases/download/v1.0.6-linux/ear-pc-linux.tar.xz}"
APP_DIR="${EAR_PC_APP_DIR:-$HOME/.local/share/ear-pc}"
BIN_DIR="${EAR_PC_BIN_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="${EAR_PC_DESKTOP_DIR:-$HOME/.local/share/applications}"
NO_START=0

die() { printf 'install-ear-pc: error: %s\n' "$*" >&2; exit 1; }
note() { printf '== %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --url)        [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--url needs a value"; TARBALL_URL="$2"; shift 2 ;;
    --app-dir)    [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--app-dir needs a value"; APP_DIR="$2"; shift 2 ;;
    --bin-dir)    [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--bin-dir needs a value"; BIN_DIR="$2"; shift 2 ;;
    --desktop-dir) [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--desktop-dir needs a value"; DESKTOP_DIR="$2"; shift 2 ;;
    --no-start)   NO_START=1; shift ;;
    -h|--help)
      sed -n '1,31p' "$0"; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[ -n "$TARBALL_URL" ] || die "no tarball URL: set EAR_PC_TARBALL_URL or pass --url (e.g. https://github.com/<repo>/releases/download/v1.0.6-linux/ear-pc-linux.tar.xz)"

for t in python3 curl tar; do command -v "$t" >/dev/null || die "missing tool: $t"; done
python3 -c 'import sys, venv' >/dev/null 2>&1 || die "python3 venv module not available; install python3-venv (see distro hints below)"

detect_distro() {
  [ -r /etc/os-release ] || return 0
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu|pop|mint|kali|raspbian|linuxmint) D=debian ;;
    fedora|rhel|rocky|almalinux|amzn) D=fedora ;;
    arch|manjaro|endeavouros|garuda|cachyos|archarm) D=arch ;;
    *) D=other ;;
  esac
}

install_bluez() {
  command -v bluetoothctl >/dev/null && return 0
  note "Installing bluez (system Bluetooth stack)…"
  case "$D" in
    debian) sudo apt-get update -qq && sudo apt-get install -y -qq bluez ;;
    fedora) sudo dnf install -y bluez ;;
    arch)   sudo pacman -S --noclef --needed bluez ;;
    other)  die "couldn't detect a supported distro (debian/fedora/arch family); please install bluez manually:
               Debian/Ubuntu: sudo apt install bluez
               Fedora:        sudo dnf install bluez
               Arch:          sudo pacman -S bluez" ;;
  esac
  command -v bluetoothctl >/dev/null || die "bluetoothctl is still missing after install attempt (see above)"
}

install_venv() {
  python3 -c 'import venv' >/dev/null 2>&1 && return 0
  note "Installing venv support…"
  case "$D" in
    debian) sudo apt-get update -qq && sudo apt-get install -y -qq python3-venv python3-pip ;;
    fedora) sudo dnf install -y python3-venv python3-pip ;;
    arch)   sudo pacman -S --noclef --needed python-venv ;;
    other)  die "python3 venv module missing; install it:
               Debian/Ubuntu: sudo apt install python3-venv
               Fedora:        sudo dnf install python3-venv
               Arch:          sudo pacman -S python-venv" ;;
  esac
}

download_tarball() {
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  tarball="$tmp/ear-pc-linux.tar.xz"
  curl -fL "$TARBALL_URL" -o "$tarball"
  [ -s "$tarball" ] || die "downloaded tarball is empty: $TARBALL_URL"
}

extract() {
  mkdir -p "$APP_DIR"
  tar -xf "$tarball" -C "$APP_DIR"
  # accept tarballs with or without a top-level "ear-pc/" dir
  if [ -d "$APP_DIR/ear-pc" ] && ls "$APP_DIR" >/dev/null 2>&1; then
    for f in "$APP_DIR/ear-pc"/* "$APP_DIR/ear-pc"/.[!.]*; do
      [ -e "$f" ] && mv -n "$f" "$APP_DIR/" 2>/dev/null || true
    done
    rm -rf "$APP_DIR/ear-pc"
  fi
}

create_venv_and_install() {
  rm -rf "$APP_DIR/venv"
  python3 -m venv "$APP_DIR/venv" || die "python3 -m venv failed"
  "$APP_DIR/venv/bin/pip" --version >/dev/null 2>&1 || { "$APP_DIR/venv/bin/python" -m ensurepip --upgrade; }
  note "Installing Ear PC dependencies (python packages)…"
  "$APP_DIR/venv/bin/pip" install --disable-pip-version-check --no-input -q \
    -r "$APP_DIR/requirements.txt" || die "pip install of Ear PC dependencies failed; see output above"
}

create_launcher() {
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/ear-pc" <<'EOF'
#!/usr/bin/env bash
APP_DIR="${EAR_PC_APP_DIR:-$HOME/.local/share/ear-pc}"
cd "$APP_DIR" || exit 1
exec "$APP_DIR/venv/bin/python" main.py "$@"
EOF
  chmod +x "$BIN_DIR/ear-pc"
}

create_desktop_entry() {
  mkdir -p "$DESKTOP_DIR"
  cat > "$DESKTOP_DIR/ear-pc.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Ear PC
GenericName=Ear Buds control
Comment=Control Nothing / CMF earbuds from your PC (Ear PC — unofficial Nothing X port)
Exec=ear-pc
Icon=$APP_DIR/icon.png
Terminal=false
Categories=AudioVideo;AllGui;
EOF
}

main() {
  detect_distro
  install_bluez
  install_venv
  download_tarball
  extract
  create_venv_and_install
  create_launcher
  create_desktop_entry
  note "Installed Ear PC"
  [ -f "$APP_DIR/version.json" ] && printf '  version: %s\n' "$(grep -o '"[0-9][^"]*"' "$APP_DIR/version.json" | head -1)"
  printf '  app dir: %s\n  launcher: %s/ear-pc\n  desktop entry: %s/ear-pc.desktop\n' "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR"
  if [ "$NO_START" != 1 ]; then
    printf 'Starting the app… (Ctrl+C or close window to stop it)\n'
    "$BIN_DIR/ear-pc"
  fi
}

main "$@"
