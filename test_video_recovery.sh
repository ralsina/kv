#!/bin/bash

# Test script for video device auto-recovery fix
# This script helps validate that the KV server can handle video device failures

set -e

SERVER_URL="http://localhost:3000"
LOG_FILE="/tmp/kv_test.log"

echo "=== KV Server Video Device Recovery Test ==="
echo "Server URL: $SERVER_URL"
echo "Log file: $LOG_FILE"
echo ""

# Function to check if server is running
check_server() {
    if curl -s "$SERVER_URL/health" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to get current video device
get_video_device() {
    curl -s "$SERVER_URL/api/status" | jq -r '.video.device // "unknown"'
}

# Function to get video status
get_video_status() {
    curl -s "$SERVER_URL/api/status" | jq -r '.video | {status: .status, device: .device, available: .device_available, accessible: .device_accessible}'
}

# Function to trigger manual re-detection
trigger_redetection() {
    local force=${1:-false}
    if [ "$force" = "true" ]; then
        curl -s -X POST "$SERVER_URL/api/video/redetect-device" \
            -H "Content-Type: application/json" \
            -d '{"force": true}'
    else
        curl -s -X POST "$SERVER_URL/api/video/redetect-device"
    fi
}

echo "1. Checking if KV server is running..."
if check_server; then
    echo "✅ Server is running"
else
    echo "❌ Server is not running. Please start with: sudo ./kvm_server"
    exit 1
fi

echo ""
echo "2. Getting initial video device status..."
INITIAL_DEVICE=$(get_video_device)
echo "Current video device: $INITIAL_DEVICE"
echo "Full video status:"
get_video_status | jq .
echo ""

echo "3. Testing manual re-detection (normal mode)..."
echo "Response:"
trigger_redetection | jq .
echo ""

echo "4. Current device after normal re-detection:"
AFTER_NORMAL=$(get_video_device)
echo "Device: $AFTER_NORMAL"
echo ""

echo "5. Testing forced re-detection..."
echo "Response:"
trigger_redetection true | jq .
echo ""

echo "6. Final device status:"
FINAL_DEVICE=$(get_video_device)
echo "Device: $FINAL_DEVICE"
get_video_status | jq .
echo ""

echo "=== Test Summary ==="
echo "Initial device: $INITIAL_DEVICE"
echo "After normal re-detection: $AFTER_NORMAL"
echo "Final device: $FINAL_DEVICE"

if [ "$INITIAL_DEVICE" != "unknown" ] && [ "$FINAL_DEVICE" != "unknown" ]; then
    echo "✅ Video device re-detection is working"
else
    echo "❌ There may be an issue with video device detection"
fi

echo ""
echo "=== Manual Testing Instructions ==="
echo "To test automatic recovery:"
echo "1. Note the current video device: $FINAL_DEVICE"
echo "2. In another terminal, simulate device failure:"
echo "   sudo rm $FINAL_DEVICE"
echo "3. Watch the server logs for automatic re-detection"
echo "4. Check status: curl -s $SERVER_URL/api/status | jq .video"
echo ""
echo "To test with real USB device:"
echo "1. Disconnect USB video capture device"
echo "2. Wait 5-10 seconds for error detection"
echo "3. Reconnect device (may get different /dev/videoX number)"
echo "4. Server should automatically switch to new device"