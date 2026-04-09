#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USERDIR="$HOME/.config/lite-xl"

echo "==> Installing Lighter..."

# 1. Check for Lite XL
if ! ls /Applications/Lite\ XL*.app &>/dev/null 2>&1; then
  echo "==> Lite XL not found. Installing via Homebrew..."
  if command -v brew &>/dev/null; then
    brew install --cask lite-xl
  else
    echo "ERROR: Homebrew not found. Please install Lite XL manually."
    echo "  https://lite-xl.com"
    exit 1
  fi
fi

# 2. Back up existing config
if [ -d "$USERDIR" ] && [ ! -L "$USERDIR" ]; then
  BACKUP="$USERDIR.bak.$(date +%s)"
  echo "==> Backing up existing config to $BACKUP"
  mv "$USERDIR" "$BACKUP"
elif [ -L "$USERDIR" ]; then
  echo "==> Removing existing symlink"
  rm "$USERDIR"
fi

# 3. Symlink this repo as the user config
echo "==> Linking $SCRIPT_DIR -> $USERDIR"
ln -sf "$SCRIPT_DIR" "$USERDIR"

# 4. Install lpm if not available
if ! command -v lpm &>/dev/null; then
  echo "==> Installing lpm (Lite XL Plugin Manager)..."
  LPM_DIR="$HOME/.local/bin"
  mkdir -p "$LPM_DIR"

  ARCH=$(uname -m)
  if [ "$ARCH" = "arm64" ]; then
    LPM_ARCH="aarch64"
  else
    LPM_ARCH="x86_64"
  fi

  LPM_URL="https://github.com/lite-xl/lite-xl-plugin-manager/releases/latest/download/lpm.${LPM_ARCH}-darwin"
  curl -L "$LPM_URL" -o "$LPM_DIR/lpm" 2>/dev/null
  chmod +x "$LPM_DIR/lpm"
  export PATH="$LPM_DIR:$PATH"
  echo "==> lpm installed to $LPM_DIR/lpm"
  echo "    Add to PATH: export PATH=\"$LPM_DIR:\$PATH\""
fi

# 5. Download font if not present
FONT_DIR="$SCRIPT_DIR/fonts"
if ! ls "$FONT_DIR"/*.ttf &>/dev/null 2>&1; then
  echo "==> Downloading MesloLGS Nerd Font..."
  mkdir -p "$FONT_DIR"
  FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip"
  curl -L "$FONT_URL" -o /tmp/meslo-nf.zip 2>/dev/null
  unzip -qo /tmp/meslo-nf.zip -d /tmp/meslo-nf
  cp /tmp/meslo-nf/*.ttf "$FONT_DIR/" 2>/dev/null || true
  rm -rf /tmp/meslo-nf /tmp/meslo-nf.zip
  echo "==> Fonts installed"
fi

# 6. Health check
echo ""
echo "==> Checking dependencies..."
TOOLS=(
  "lua-language-server:LSP (Lua)"
  "pyright-langserver:LSP (Python)"
  "typescript-language-server:LSP (TypeScript)"
  "bash-language-server:LSP (Bash)"
  "stylua:Formatter (Lua)"
  "black:Formatter (Python)"
  "prettier:Formatter (JS/TS/HTML/CSS)"
  "shfmt:Formatter (Shell)"
  "ruff:Linter (Python)"
  "shellcheck:Linter (Shell)"
  "claude:AI (Claude Code CLI)"
)

for entry in "${TOOLS[@]}"; do
  IFS=':' read -r tool desc <<< "$entry"
  if command -v "$tool" &>/dev/null; then
    printf "  %-35s ✓\n" "$desc"
  else
    printf "  %-35s ✗ (not found)\n" "$desc"
  fi
done

echo ""
echo "==> Lighter installed! Launch Lite XL to start."
echo "    Theme: tokyonight | Modal: space leader | Escape for normal mode"
