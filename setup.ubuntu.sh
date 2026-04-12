#!/bin/bash
# Vacation Station 14 — Ubuntu developer environment setup
#
# Usage:
#   ./setup.ubuntu.sh              # full dev setup (server + client)
#   ./setup.ubuntu.sh --server     # server-only (no GPU/audio libs)
#   ./setup.ubuntu.sh --runtime    # runtime only (no SDK, for prebuilt server)
#
# Tested on Ubuntu 22.04, 24.04, 25.10.

set -euo pipefail

MODE="dev"
case "${1:-}" in
    --server) MODE="server" ;;
    --runtime) MODE="runtime" ;;
    --help|-h)
        grep '^#' "$0" | head -10
        exit 0
        ;;
esac

# --- Detect Ubuntu ---

if ! command -v apt-get &>/dev/null; then
    echo "Error: apt-get not found. This script is for Debian/Ubuntu." >&2
    exit 1
fi

. /etc/os-release
echo ">>> Ubuntu ${VERSION_ID:-unknown} detected (mode: $MODE)"
echo ""

# --- Base system packages ---

echo ">>> Updating apt and installing base packages..."
sudo apt-get update -qq
sudo apt-get install -y \
    git \
    python3 \
    curl \
    ca-certificates \
    file

# --- .NET SDK/Runtime via Microsoft feed ---

if [ "$MODE" = "runtime" ]; then
    DOTNET_PKG="dotnet-runtime-10.0 aspnetcore-runtime-10.0"
else
    DOTNET_PKG="dotnet-sdk-10.0"
fi

if ! dotnet --list-sdks 2>/dev/null | grep -q "^10\." \
   && ! dotnet --list-runtimes 2>/dev/null | grep -q "Microsoft.NETCore.App 10\."; then
    # Ubuntu 25.10+ ships .NET 10 natively in the archive; older releases
    # need the Microsoft feed.
    USE_MS_FEED=1
    case "$VERSION_ID" in
        22.04|24.04) USE_MS_FEED=1 ;;
        25.*|26.*|27.*|28.*|29.*|3*.*) USE_MS_FEED=0 ;;
    esac

    if [ "$USE_MS_FEED" = "1" ]; then
        echo ">>> Installing Microsoft apt feed for .NET 10 (Ubuntu $VERSION_ID)..."
        TMP_DEB=$(mktemp --suffix=.deb)
        curl -sSL -o "$TMP_DEB" \
            "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"
        sudo dpkg -i "$TMP_DEB"
        rm -f "$TMP_DEB"
        sudo apt-get update -qq
    else
        echo ">>> Ubuntu $VERSION_ID ships .NET 10 natively; skipping Microsoft feed."
    fi

    echo ">>> Installing $DOTNET_PKG..."
    sudo apt-get install -y $DOTNET_PKG
else
    echo ">>> .NET 10 already installed."
fi

# --- SS14 runtime system libraries ---

SERVER_LIBS="libsodium23 libssl3"
CLIENT_LIBS="libfreetype6 libglfw3 libopenal1 libfluidsynth3"

if [ "$MODE" = "dev" ]; then
    echo ">>> Installing server + client libraries..."
    sudo apt-get install -y $SERVER_LIBS $CLIENT_LIBS
elif [ "$MODE" = "server" ]; then
    echo ">>> Installing server-only libraries..."
    sudo apt-get install -y $SERVER_LIBS
elif [ "$MODE" = "runtime" ]; then
    echo ">>> Installing server runtime libraries..."
    sudo apt-get install -y $SERVER_LIBS
fi

# --- Repository bootstrap (only if we're in the repo root) ---

if [ -f "SpaceStation14.slnx" ] && [ -f "RUN_THIS.py" ]; then
    echo ""
    echo ">>> Detected VS14 repo root. Bootstrapping submodules..."
    python3 RUN_THIS.py || {
        echo "RUN_THIS.py failed. Falling back to manual submodule update..."
        git submodule update --init --recursive
    }

    if [ "$MODE" != "runtime" ]; then
        echo ""
        echo ">>> Running initial dotnet build..."
        echo "    (first build takes a few minutes while NuGet restores packages)"
        dotnet build
    fi
fi

# --- Summary ---

echo ""
echo "==============================================="
echo "  Setup complete ($MODE mode)"
echo "==============================================="
echo ""
echo "Installed:"
command -v git && git --version
command -v python3 && python3 --version
command -v dotnet && dotnet --version
echo ""

case "$MODE" in
    dev)
        cat <<'EOF'
Next steps:
  1. Run the server:  dotnet run --project Content.Server
  2. Run the client:  dotnet run --project Content.Client  (in another terminal)
  3. Connect via launcher to localhost, or use the client's Direct Connect

Recommended IDEs:
  - JetBrains Rider (free for non-commercial)
  - VS Code + C# extension (muhammad-sammy.csharp)
EOF
        ;;
    server)
        cat <<'EOF'
Next steps:
  1. Build: dotnet build
  2. Run server: dotnet run --project Content.Server
  3. Package for distribution:
       dotnet build Content.Packaging -c Release
       dotnet run --project Content.Packaging server --hybrid-acz --platform linux-x64
EOF
        ;;
    runtime)
        cat <<'EOF'
Next steps:
  1. Download a prebuilt server zip from your publisher
  2. Extract, chmod +x Robust.Server
  3. ./Robust.Server
  4. For production, see SS14.Watchdog: https://github.com/space-wizards/SS14.Watchdog
EOF
        ;;
esac

echo ""
echo "Troubleshooting (if first run fails):"
echo "  - libssl version mismatch: export CLR_OPENSSL_VERSION_OVERRIDE=48"
echo "  - ARM64: Robust Toolbox < 267.0.0 doesn't support ARM64; use x64 via emulation"
echo ""
