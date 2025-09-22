#!/bin/bash
set -euo pipefail

# --- Configuration ---
REPO="ralsina/kv"
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
SERVICE_NAME="kv.service"
BINARY_NAME="kv"
VERSION="0.12.0" # Hardcoded version
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT ERR INT TERM # Ensure cleanup

# --- Helper Functions ---

# Check if required commands are available
check_dependencies() {
    local deps=("curl" "dnsmasq") # Removed jq
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: Required dependency '$dep' is not installed." >&2
            echo "Please install it (e.g., sudo apt-get install $dep or sudo yum install $dep) and run the script again." >&2
            exit 1
        fi
    done
}

# Determine system architecture and map to KV asset name
get_architecture() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        *)
            echo "Error: Unsupported architecture '$arch'." >&2
            echo "This script currently supports x86_64 (amd64) and aarch64 (arm64)." >&2
            exit 1
            ;;
    esac
}

# --- Main Installation Logic ---

echo "Starting KV installation..."

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root." >&2
   exit 1
fi

# Check for required tools
check_dependencies

# Get system architecture
ARCH=$(get_architecture)
echo "Detected architecture: ${ARCH}"

# Construct download URL for the hardcoded version
echo "Using KV version: ${VERSION}"
ASSET_NAME="${BINARY_NAME}-static-linux-${ARCH}" # Asset name based on architecture
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_NAME}"

echo "Target asset name: ${ASSET_NAME}"
echo "Constructed download URL: ${DOWNLOAD_URL}"

# Download the asset
echo "Downloading KV binary..."
DOWNLOAD_PATH="${TEMP_DIR}/${ASSET_NAME}"
if ! curl -L -o "${DOWNLOAD_PATH}" "${DOWNLOAD_URL}"; then
    echo "Error: Failed to download the asset from ${DOWNLOAD_URL}." >&2
    echo "Please ensure version ${VERSION} and asset ${ASSET_NAME} exist at ${REPO} releases." >&2
    exit 1
fi

echo "Binary downloaded."

# Install the binary to the target directory
echo "Installing binary to ${INSTALL_DIR}/${BINARY_NAME}..."
if ! mv "${DOWNLOAD_PATH}" "${INSTALL_DIR}/${BINARY_NAME}"; then
    echo "Error: Failed to move the binary to the installation directory." >&2
    exit 1
fi
if ! chmod +x "${INSTALL_DIR}/${BINARY_NAME}"; then
    echo "Error: Failed to make the binary executable." >&2
    exit 1
fi

echo "KV binary installed successfully."

# Install the systemd service file
echo "Installing systemd service file to ${SERVICE_DIR}/${SERVICE_NAME}..."

# Create the service file using a heredoc, embedding the content from the template
cat <<EOF > "${SERVICE_DIR}/${SERVICE_NAME}"
[Unit]
Description=KV Log Viewer
After=network.target

[Service]
Type=simple

# --- Authentication Configuration ---
# Set these environment variables to enable Basic Authentication.
# If KV_USER and KV_PASSWORD are not set, KV will run without authentication.
# Environment="KV_USER=your_kv_username"
# Environment="KV_PASSWORD=your_strong_kv_password"

# Replace with the actual path to your KV directory
WorkingDirectory=${INSTALL_DIR}/
# Replace with the actual path and options to the KV binary
ExecStart=${INSTALL_DIR}/${BINARY_NAME} -b 0.0.0.0 -p 3000 -r 720p
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Verify service file creation
if [[ ! -f "${SERVICE_DIR}/${SERVICE_NAME}" ]]; then
    echo "Error: Failed to create the service file." >&2
    exit 1
fi

echo "Systemd service file created."

# Reload systemd daemon, enable and start the service
echo "Reloading systemd daemon..."
if ! systemctl daemon-reload; then
    echo "Error: Failed to reload systemd daemon." >&2
    exit 1
fi

echo "Enabling KV service to start on boot..."
if ! systemctl enable "${SERVICE_NAME}"; then
    echo "Error: Failed to enable KV service." >&2
    exit 1
fi

echo "Starting KV service..."
if ! systemctl start "${SERVICE_NAME}"; then
    echo "Error: Failed to start KV service." >&2
    exit 1
fi

echo ""
echo "--- KV Installation Complete ---"
echo "KV binary installed to: ${INSTALL_DIR}/${BINARY_NAME}"
echo "Systemd service file created at: ${SERVICE_DIR}/${SERVICE_NAME}"
echo ""
echo "--- Next Steps ---"
echo "1. Check the service status: systemctl status kv.service"
echo "2. Configure authentication (optional but recommended):"
echo "   Edit the service file: sudo nano ${SERVICE_DIR}/${SERVICE_NAME}"
echo "   Uncomment and set KV_USER and KV_PASSWORD."
echo "   After editing, run: sudo systemctl daemon-reload && sudo systemctl restart kv.service"
echo "3. Access KV at http://<your_server_ip>:3000"

# Clean up temporary directory
# Cleanup is now handled by the trap
echo "Temporary files will be cleaned up automatically."

exit 0
