#!/bin/bash

# FC Restore CLI Download and Run Script
# For Linux and macOS

set -e pipefail

# Base URL for downloads
BASE_URL="https://github.com/frappe/fc-scripts/raw/develop/fcrestore/dist"

# Detect OS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    linux*)
        OS="linux"
        ;;
    darwin*)
        OS="darwin"
        ;;
    *)
        echo "Unsupported operating system: $OS"
        echo "Please report this issue at https://support.frappe.io"
        echo "Include the following information:"
        echo "  OS: $OS"
        echo "  Architecture: $(uname -m)"
        exit 1
        ;;
esac

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        ARCH="amd64"
        ;;
    arm64|aarch64)
        ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        echo "Please report this issue at https://support.frappe.io"
        echo "Include the following information:"
        echo "  OS: $OS"
        echo "  Architecture: $ARCH"
        exit 1
        ;;
esac

# Construct binary name and download URL
BINARY_NAME="fcrestore-${OS}-${ARCH}"
DOWNLOAD_URL="${BASE_URL}/${BINARY_NAME}"
LOCAL_PATH="/tmp/${BINARY_NAME}"

echo "Detected system: ${OS}/${ARCH}"
echo "Downloading fcrestore CLI..."

# Download the binary
if command -v curl >/dev/null 2>&1; then
    if ! curl -L -f -s -o "$LOCAL_PATH" "$DOWNLOAD_URL"; then
        echo "Failed to download fcrestore binary"
        echo "URL attempted: $DOWNLOAD_URL"
        echo ""
        echo "This could mean:"
        echo "  • The binary for your platform (${OS}/${ARCH}) is not available"
        echo "  • There's a network connectivity issue"
        echo ""
        echo "Please report this issue at https://support.frappe.io"
        echo "Include the following information:"
        echo "  OS: $OS"
        echo "  Architecture: $ARCH"
        echo "  URL: $DOWNLOAD_URL"
        exit 1
    fi
elif command -v wget >/dev/null 2>&1; then
    if ! wget -q -O "$LOCAL_PATH" "$DOWNLOAD_URL"; then
        echo "Failed to download fcrestore binary"
        echo "URL attempted: $DOWNLOAD_URL"
        echo ""
        echo "This could mean:"
        echo "  • The binary for your platform (${OS}/${ARCH}) is not available"
        echo "  • There's a network connectivity issue"
        echo ""
        echo "Please report this issue at https://support.frappe.io"
        echo "Include the following information:"
        echo "  OS: $OS"
        echo "  Architecture: $ARCH"
        echo "  URL: $DOWNLOAD_URL"
        exit 1
    fi
else
    echo "Neither curl nor wget is available"
    echo "Please install curl or wget and try again"
    exit 1
fi

# Make binary executable
chmod +x "$LOCAL_PATH"

echo "Download complete!"
echo ""

# Run the binary with all passed arguments
exec "$LOCAL_PATH" "$@"