# 🏞️ macOS Live Aerial Wallpaper Overlay

A ultra-lightweight, high-performance utility that overlays Apple Aerial screen savers (or any custom videos) as a live desktop wallpaper behind your desktop icons on macOS. 

Written in pure Swift utilizing native **AppKit** and **AVFoundation**, this utility is designed for efficiency, stability, and zero-flash transitions.

---

## ✨ Features

- **📺 Multi-Display Support**: Detects and plays video on all connected monitors. Each screen gets its own hardware-accelerated video rendering pipeline.
- **⚡ Battery & CPU Optimizations**:
  - **Video-Only Demuxing**: Automatically strips out audio tracks from video files on load, preventing unnecessary audio decoding overhead.
  - **Zero Idle Power (0% CPU)**: Automatically pauses playback when your monitors go to sleep, when you lock your Mac, or when you lock the user session. It instantly wakes back up when you resume.
  - **Opaque Compositing**: Configures rendering layers as opaque (`isOpaque = true`), allowing macOS WindowServer to skip expensive background layer blending calculations.
- **🚀 Zero-Flash Active Space Switching**: Unlike naive wallpaper overlays, this program does not destroy and recreate windows when you switch desktops (spaces). It uses a soft re-raising mechanism that prevents the system wallpaper from flashing through.
- **🔌 Dynamic Hardware Reconciling**: Automatically detects when screens are plugged in or unplugged, adjusting layouts dynamically.
- **📂 Smart Directory Fallback**: Scans the workspace `videos/` folder first. If empty, it falls back to the standard macOS system Apple Aerial folder.
- **🎥 Format Support**: Fully supports case-insensitive `.mov` and `.mp4` video files.

---

## 📁 Repository Structure

- `wp_overlay.swift` — The compiled Swift application.
- `com.user.fixwallpaper.plist` — LaunchAgent configuration to run the app in the background and start it at login.
- `setup.sh` — The deployment script that builds, installs, configures, and launches the service.
- `videos/` — The workspace folder where you can drop your custom wallpaper video files.

---

## 🚀 Quick Start Guide

### Step 1: Clone the Repository
Clone this repository to your preferred location on your Mac.

### Step 2: Add Your Videos
Place your favorite `.mov` or `.mp4` videos inside the `videos/` folder in the repository directory.

> [!TIP]
> **Using Apple's Aerial Videos:**
> If you have already downloaded Apple's Aerial wallpaper videos on your Mac, you don't need to copy them! If your workspace `videos/` folder is empty, the application will automatically scan your system's aerial folder as a fallback:
> `~/Library/Application Support/com.apple.wallpaper/aerials/videos/`

### Step 3: Run the Setup Script
Open Terminal in the repository folder and execute:
```bash
./setup.sh
```
This script will:
1. Compile the Swift code using optimal optimizations (`swiftc -O`) into `~/bin/wp_overlay`.
2. Configure your LaunchAgent plist with your username and dynamic workspace path.
3. Register and start the background service via `launchctl`.
4. Verify that the service is running.

---

## 🛠️ Management & Commands

### How it Works (Process Management)
The wallpaper overlay runs as a background process named `wp_overlay` under a LaunchAgent. Because `KeepAlive` is set to `true` in its configuration, if the process is terminated, the system will instantly relaunch it.

#### Restart the Service / Apply New Videos
If you add, change, or remove video files in the `videos/` folder, restart the process to scan the directory again:
```bash
pkill wp_overlay
```
*Note: The LaunchAgent will automatically restart the process within a second.*

#### Stop the Service Temporarily
To turn off the live wallpaper overlay:
```bash
launchctl unload ~/Library/LaunchAgents/com.user.fixwallpaper.plist
```

#### Start the Service Manually
To turn the live wallpaper overlay back on:
```bash
launchctl load ~/Library/LaunchAgents/com.user.fixwallpaper.plist
```

#### Recompile and Apply Changes
If you modify the Swift source code or want to reinstall from scratch, simply run:
```bash
./setup.sh
```

---

## 🧹 Uninstalling

To completely remove the service and all its files from your Mac:

```bash
# 1. Stop the running service
launchctl unload ~/Library/LaunchAgents/com.user.fixwallpaper.plist 2>/dev/null || true

# 2. Remove the LaunchAgent plist
rm ~/Library/LaunchAgents/com.user.fixwallpaper.plist

# 3. Remove the compiled executable
rm ~/bin/wp_overlay
```

---

## 🔍 Troubleshooting & Logs

The application logs standard print outputs and any errors into dedicated system logs. If the wallpaper doesn't load or freezes, inspect these log files:

- **Standard Log (Outputs directory information, video count, etc.)**:
  ```bash
  cat ~/Library/Logs/com.user.fixwallpaper.out.log
  ```
- **Error Log (Outputs system crashes or compilation errors)**:
  ```bash
  cat ~/Library/Logs/com.user.fixwallpaper.err.log
  ```
- **Check Process in Activity Monitor**:
  Search for `wp_overlay` in **Activity Monitor** or run this command:
  ```bash
  pgrep -l wp_overlay
  ```
