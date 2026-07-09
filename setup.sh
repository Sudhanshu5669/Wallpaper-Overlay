#!/bin/bash
set -e

# Dynamically get the directory where setup.sh is located
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEOS_DIR="$WORKSPACE_DIR/videos"
SYSTEM_VIDEOS_DIR="$HOME/Library/Application Support/com.apple.wallpaper/aerials/videos"

echo "=== Wallpaper Overlay Setup ==="

# 1. Check for videos
echo "Checking for .mov and .mp4 files..."
VIDEO_COUNT=0

if [ -d "$VIDEOS_DIR" ]; then
    VIDEO_COUNT=$(find "$VIDEOS_DIR" -maxdepth 1 \( -iname "*.mov" -o -iname "*.mp4" \) | wc -l | tr -d ' ')
fi

if [ "$VIDEO_COUNT" -eq 0 ]; then
    echo "No .mov or .mp4 files found in workspace folder: $VIDEOS_DIR"
    echo "Checking system videos directory..."
    if [ -d "$SYSTEM_VIDEOS_DIR" ]; then
        SYSTEM_VIDEO_COUNT=$(find "$SYSTEM_VIDEOS_DIR" -maxdepth 1 \( -iname "*.mov" -o -iname "*.mp4" \) | wc -l | tr -d ' ')
        if [ "$SYSTEM_VIDEO_COUNT" -gt 0 ]; then
            echo "Found $SYSTEM_VIDEO_COUNT videos in system directory. Using system directory as fallback."
            VIDEO_COUNT=$SYSTEM_VIDEO_COUNT
        fi
    fi
fi

if [ "$VIDEO_COUNT" -eq 0 ]; then
    echo "⚠️ Warning: No .mov or .mp4 videos found in either workspace 'videos/' or system folder."
    echo "Please place some .mov or .mp4 files in '$VIDEOS_DIR' before loading the agent."
    echo "Continuing compilation anyway..."
fi

# 2. Build the Swift app
echo "Creating ~/bin if it doesn't exist..."
mkdir -p "$HOME/bin"

echo "Compiling wp_overlay.swift..."
swiftc -O -o "$HOME/bin/wp_overlay" "$WORKSPACE_DIR/wp_overlay.swift"
echo "✅ Compilation successful. Executable located at ~/bin/wp_overlay"

# 3. Configure and Copy LaunchAgent Plist
echo "Configuring LaunchAgent plist..."
mkdir -p "$HOME/Library/LaunchAgents"
cp "$WORKSPACE_DIR/com.user.fixwallpaper.plist" "$HOME/Library/LaunchAgents/com.user.fixwallpaper.plist"
sed -i '' "s|REPLACE_WITH_USERNAME|$USER|g" "$HOME/Library/LaunchAgents/com.user.fixwallpaper.plist"
sed -i '' "s|REPLACE_WITH_VIDEOS_DIR|$VIDEOS_DIR|g" "$HOME/Library/LaunchAgents/com.user.fixwallpaper.plist"
echo "✅ LaunchAgent plist installed to ~/Library/LaunchAgents/com.user.fixwallpaper.plist"

# 4. Load the LaunchAgent
if [ "$VIDEO_COUNT" -gt 0 ]; then
    echo "Restarting LaunchAgent..."
    launchctl unload "$HOME/Library/LaunchAgents/com.user.fixwallpaper.plist" 2>/dev/null || true
    launchctl load "$HOME/Library/LaunchAgents/com.user.fixwallpaper.plist"
    echo "✅ LaunchAgent loaded."

    # 5. Verify process is running
    echo "Verifying service is running..."
    sleep 2
    if pgrep -x "wp_overlay" > /dev/null; then
        echo "🎉 Success: wp_overlay is running! PID: $(pgrep -x wp_overlay)"
    else
        echo "❌ Error: wp_overlay process is not running. Check logs at ~/Library/Logs/com.user.fixwallpaper.err.log"
    fi
else
    echo "ℹ️ Compilation is complete, but LaunchAgent has not been loaded because no videos are present."
    echo "Once you add .mov or .mp4 files to '$VIDEOS_DIR', run this script again: ./setup.sh"
fi
