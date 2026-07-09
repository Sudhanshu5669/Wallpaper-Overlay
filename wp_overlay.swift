import AppKit
import AVFoundation
import QuartzCore
import CoreMedia

// Helper to check if a file is a supported video format (.mov or .mp4)
func isVideoFile(_ fileName: String) -> Bool {
    let lowercased = fileName.lowercased()
    return lowercased.hasSuffix(".mov") || lowercased.hasSuffix(".mp4")
}

// Determine which video directory to use:
// 1. Command-line argument (if provided and contains video files)
// 2. Relative "./videos" directory in execution context
// 3. Fallback to system wallpaper videos folder
let videoDir: String = {
    let systemVideoDir = ("~/Library/Application Support/com.apple.wallpaper/aerials/videos" as NSString).expandingTildeInPath

    func hasVideoFiles(in dir: String) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return false
        }
        return files.contains { isVideoFile($0) }
    }

    if CommandLine.arguments.count > 1 {
        let argVideoDir = (CommandLine.arguments[1] as NSString).expandingTildeInPath
        if hasVideoFiles(in: argVideoDir) {
            return argVideoDir
        }
    }

    let localWorkspaceVideoDir = ("./videos" as NSString).expandingTildeInPath
    if hasVideoFiles(in: localWorkspaceVideoDir) {
        return localWorkspaceVideoDir
    }

    return systemVideoDir
}()

guard let files = try? FileManager.default.contentsOfDirectory(atPath: videoDir) else {
    print("No videos directory found at \(videoDir)")
    exit(1)
}

let videoFiles = files.filter { isVideoFile($0) }.sorted()
guard !videoFiles.isEmpty else {
    print("No supported video files (.mov, .mp4) found in \(videoDir)")
    exit(1)
}

print("Loading \(videoFiles.count) video(s) from \(videoDir)")

// Build fresh AVPlayerItems for the given video files
func makePlayerItems() -> [AVPlayerItem] {
    videoFiles.compactMap { filename -> AVPlayerItem? in
        let url = URL(fileURLWithPath: "\(videoDir)/\(filename)")
        let asset = AVURLAsset(url: url)

        // OPTIMIZATION: Extract only the video track. Stripping the audio track completely
        // prevents macOS from allocating audio decoding pipelines, saving CPU demuxing/decoding cycles.
        let composition = AVMutableComposition()
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return AVPlayerItem(url: url)
        }

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return AVPlayerItem(url: url)
        }

        do {
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: asset.duration),
                of: videoTrack,
                at: .zero
            )
            // Retain natural transformation (e.g. rotation metadata)
            compositionVideoTrack.preferredTransform = videoTrack.preferredTransform

            return AVPlayerItem(asset: composition)
        } catch {
            return AVPlayerItem(url: url)
        }
    }
}

// Return the CoreGraphics display ID for a given NSScreen (nil if unavailable)
func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
}

struct ScreenEntry {
    let displayID: CGDirectDisplayID
    let window: NSWindow
    let player: AVPlayer
}

class WallpaperOverlayApp {
    @MainActor var entries: [CGDirectDisplayID: ScreenEntry] = [:]
    @MainActor var isPaused = false

    @MainActor
    func makeEntry(for screen: NSScreen) -> ScreenEntry? {
        guard let did = displayID(for: screen) else { return nil }

        let screenPlayer = AVQueuePlayer(items: makePlayerItems())
        // OPTIMIZATION: Disable audio routing and energy-inhibiting behaviors
        screenPlayer.volume = 0.0
        screenPlayer.isMuted = true
        screenPlayer.preventsDisplaySleepDuringVideoPlayback = false

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { note in
            guard let ended = note.object as? AVPlayerItem else { return }
            if screenPlayer.items().contains(ended) || screenPlayer.currentItem == ended {
                let copy = ended.copy() as! AVPlayerItem
                copy.seek(to: .zero, completionHandler: nil)
                screenPlayer.insert(copy, after: nil)
            }
        }

        let localFrame = NSRect(origin: .zero, size: screen.frame.size)
        let contentView = NSView(frame: localFrame)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        // OPTIMIZATION: Tell WindowServer compositor layer blending isn't required
        contentView.layer?.isOpaque = true

        let playerLayer = AVPlayerLayer(player: screenPlayer)
        playerLayer.frame = localFrame
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        // OPTIMIZATION: GPU-accelerated drawing and opaque configuration
        playerLayer.isOpaque = true
        playerLayer.drawsAsynchronously = true
        contentView.layer?.addSublayer(playerLayer)

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.backgroundColor = NSColor.black
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)

        if !isPaused {
            screenPlayer.play()
        }

        return ScreenEntry(displayID: did, window: window, player: screenPlayer)
    }

    @MainActor
    func rebuildWindows() {
        let currentScreens = NSScreen.screens
        let currentIDs = Set(currentScreens.compactMap { displayID(for: $0) })

        for (did, entry) in entries where !currentIDs.contains(did) {
            entry.window.orderOut(nil)
            entries.removeValue(forKey: did)
        }

        for screen in currentScreens {
            guard let did = displayID(for: screen), entries[did] == nil else { continue }
            if let entry = makeEntry(for: screen) {
                entries[did] = entry
            }
        }
    }

    @MainActor
    func refreshWindows() {
        let currentScreens = NSScreen.screens
        var addedAny = false

        for screen in currentScreens {
            guard let did = displayID(for: screen) else { continue }
            if let entry = entries[did] {
                entry.window.orderFront(nil)
            } else {
                if let entry = makeEntry(for: screen) {
                    entries[did] = entry
                    addedAny = true
                }
            }
        }

        let currentIDs = Set(currentScreens.compactMap { displayID(for: $0) })
        for did in entries.keys where !currentIDs.contains(did) {
            entries[did]?.window.orderOut(nil)
            entries.removeValue(forKey: did)
        }

        _ = addedAny
    }

    // OPTIMIZATION: Pause rendering/play when screen locks or monitor sleeps
    @MainActor
    func pausePlayback() {
        isPaused = true
        for entry in entries.values {
            entry.player.pause()
        }
    }

    @MainActor
    func resumePlayback() {
        isPaused = false
        for entry in entries.values {
            entry.player.play()
        }
    }
}

let appController = WallpaperOverlayApp()

// Initial setup
Task { @MainActor in
    appController.rebuildWindows()
}

// Monitor changes → reconcile
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        appController.rebuildWindows()
    }
}

// Active space changed → soft refresh
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.activeSpaceDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        appController.refreshWindows()
    }
}

// OPTIMIZATION: Stop playback on Screen Sleep/Lock to drop CPU usage to 0%
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.screensDidSleepNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        appController.pausePlayback()
    }
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.screensDidWakeNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        appController.resumePlayback()
    }
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.sessionDidResignActiveNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        appController.pausePlayback()
    }
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.sessionDidBecomeActiveNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        appController.resumePlayback()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
