import AppKit
import AVFoundation
import QuartzCore

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

// ---------------------------------------------------------------------------
// ScreenEntry: one self-contained overlay per physical display.
//
// FIX: Give each screen its OWN AVPlayer so every display gets an independent
// GPU render path. Sharing a single AVQueuePlayer across multiple AVPlayerLayer
// instances on different NSWindows causes stuttering and desync on external screens.
// ---------------------------------------------------------------------------
struct ScreenEntry {
    let displayID: CGDirectDisplayID
    let window: NSWindow
    let player: AVPlayer  // per-screen player
}

// Build fresh AVPlayerItems for the given video files
func makePlayerItems() -> [AVPlayerItem] {
    videoFiles.map { AVPlayerItem(url: URL(fileURLWithPath: "\(videoDir)/\($0)")) }
}

// Return the CoreGraphics display ID for a given NSScreen (nil if unavailable)
func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
}

// ---------------------------------------------------------------------------
// WallpaperOverlayApp: manages one ScreenEntry per connected display.
// Keyed by CGDirectDisplayID so we can add/remove displays without touching
// unrelated windows, preventing any flash on unaffected screens.
// ---------------------------------------------------------------------------
class WallpaperOverlayApp {
    @MainActor var entries: [CGDirectDisplayID: ScreenEntry] = [:]

    // ------------------------------------------------------------------
    // makeEntry: build an NSWindow + AVPlayer for one physical screen
    // ------------------------------------------------------------------
    @MainActor
    func makeEntry(for screen: NSScreen) -> ScreenEntry? {
        guard let did = displayID(for: screen) else { return nil }

        // Independent looping player for this screen
        let screenPlayer = AVQueuePlayer(items: makePlayerItems())
        screenPlayer.isMuted = true

        // Re-queue finished items so playback loops forever
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { note in
            guard let ended = note.object as? AVPlayerItem else { return }
            // Only handle items belonging to this screen's player
            if screenPlayer.items().contains(ended) || screenPlayer.currentItem == ended {
                let copy = ended.copy() as! AVPlayerItem
                copy.seek(to: .zero, completionHandler: nil)
                screenPlayer.insert(copy, after: nil)
            }
        }

        // contentView uses local (0,0) coords; window is positioned globally
        let localFrame = NSRect(origin: .zero, size: screen.frame.size)
        let contentView = NSView(frame: localFrame)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

        let playerLayer = AVPlayerLayer(player: screenPlayer)
        playerLayer.frame = localFrame
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentView.layer?.addSublayer(playerLayer)

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        // Sit just above the macOS system wallpaper layer so our overlay
        // always wins, but below desktop icons and all normal app windows
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.backgroundColor = NSColor.black
        // Explicitly set global frame so the window lands on the right screen
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)

        screenPlayer.play()

        return ScreenEntry(displayID: did, window: window, player: screenPlayer)
    }

    // ------------------------------------------------------------------
    // rebuildWindows: full teardown + rebuild.
    // Called ONLY when display hardware changes (monitor plugged/unplugged).
    // Uses orderOut (hide) not close (AppKit event), so no flash on
    // screens that stay connected.
    // ------------------------------------------------------------------
    @MainActor
    func rebuildWindows() {
        let currentScreens = NSScreen.screens
        let currentIDs = Set(currentScreens.compactMap { displayID(for: $0) })

        // Remove entries for displays that are gone
        for (did, entry) in entries where !currentIDs.contains(did) {
            entry.window.orderOut(nil)
            entries.removeValue(forKey: did)
        }

        // Add entries for new displays; leave untouched ones alone
        for screen in currentScreens {
            guard let did = displayID(for: screen), entries[did] == nil else { continue }
            if let entry = makeEntry(for: screen) {
                entries[did] = entry
            }
        }
    }

    // ------------------------------------------------------------------
    // refreshWindows: soft refresh on space/desktop switch.
    // Never destroys any window — just brings them all to front.
    // If a display appears that has no entry yet, we add only that entry.
    // ------------------------------------------------------------------
    @MainActor
    func refreshWindows() {
        let currentScreens = NSScreen.screens
        var addedAny = false

        for screen in currentScreens {
            guard let did = displayID(for: screen) else { continue }
            if let entry = entries[did] {
                // Window already exists for this screen — just re-raise it
                entry.window.orderFront(nil)
            } else {
                // New display appeared mid-session — add just this one
                if let entry = makeEntry(for: screen) {
                    entries[did] = entry
                    addedAny = true
                }
            }
        }

        // Also clean up orphaned entries (display disconnected during space switch)
        let currentIDs = Set(currentScreens.compactMap { displayID(for: $0) })
        for did in entries.keys where !currentIDs.contains(did) {
            entries[did]?.window.orderOut(nil)
            entries.removeValue(forKey: did)
        }

        _ = addedAny // suppress unused warning
    }
}

let appController = WallpaperOverlayApp()

// Initial setup
Task { @MainActor in
    appController.rebuildWindows()
}

// Monitor plugged in or out → reconcile display list
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        appController.rebuildWindows()
    }
}

// Active space/desktop changed → soft re-raise only (no window destruction)
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.activeSpaceDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    Task { @MainActor in
        appController.refreshWindows()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
