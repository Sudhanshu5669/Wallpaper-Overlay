# macOS Live Aerial Wallpaper Overlay

A custom lightweight live desktop wallpaper utility that plays Apple Aerial `.mov` videos (or any custom videos) behind desktop elements on macOS.

## Features

- Dynamic multi-screen support: plays video overlays on all screens.
- Re-creates overlay windows automatically when screen configurations change (e.g. plugging/unplugging monitors) or when active spaces change.
- Extremely lightweight, written in pure Swift, using Apple's native AppKit and AVFoundation framework.
- Persisted and managed via a macOS LaunchAgent.
- Automatically scans the workspace `videos/` folder first, falling back to the standard macOS system aerial videos directory if empty.

## Project Structure

- `wp_overlay.swift`: Swift source code implementing the desktop window overlay and video playback.
- `com.user.fixwallpaper.plist`: The LaunchAgent plist template.
- `setup.sh`: Automated script to build the Swift app, configure the LaunchAgent plist, and launch/verify the background service.
- `videos/`: The workspace folder where you can drop your `.mov` videos.

## Quick Start

1. **Add videos**: Drop your preferred `.mov` video files (such as Apple's Aerial videos) into the `videos/` directory in this workspace:
   ```bash
   # Add your .mov files to:
   ./videos/
   ```

2. **Run the setup script**:
   ```bash
   ./setup.sh
   ```
   This will:
   - Compile `wp_overlay.swift` to `~/bin/wp_overlay`.
   - Install the LaunchAgent configuration to `~/Library/LaunchAgents/com.user.fixwallpaper.plist`.
   - Load the agent using `launchctl`.
   - Verify that the process is running.

## Management Commands

### Start the Service Manually
```bash
launchctl load ~/Library/LaunchAgents/com.user.fixwallpaper.plist
```

### Stop the Service Manually
```bash
launchctl unload ~/Library/LaunchAgents/com.user.fixwallpaper.plist
```

### Restart the Service
To apply updates to videos or settings, run:
```bash
./setup.sh
```

### Check Process Status
```bash
pgrep -l wp_overlay
```

## Logs & Troubleshooting

If you encounter any issues (e.g., the overlay does not start), inspect the following log files:

- **Standard Output Log**:
  `~/Library/Logs/com.user.fixwallpaper.out.log`
- **Standard Error Log**:
  `~/Library/Logs/com.user.fixwallpaper.err.log`
