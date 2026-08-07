import AppKit
import SwiftUI

private final class LockedWindowDelegate: NSObject, NSWindowDelegate {
    let fixedSize: NSSize

    init(size: NSSize) {
        fixedSize = size
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        fixedSize
    }
}

@main
struct MiyoiApp: App {
    @StateObject private var manager = DeviceManager()
    private let windowSize = NSSize(width: 820, height: 760)
    private let delegate: LockedWindowDelegate

    init() {
        delegate = LockedWindowDelegate(size: NSSize(width: 820, height: 760))
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Miyoi") {
            ContentView()
                .environmentObject(manager)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first {
                            window.delegate = delegate
                            window.styleMask = [.titled, .closable, .miniaturizable]
                            window.collectionBehavior = [.fullScreenNone]
                            window.standardWindowButton(.zoomButton)?.isHidden = true
                            window.setContentSize(windowSize)
                            window.minSize = windowSize
                            window.maxSize = windowSize
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
        }
        .defaultSize(width: windowSize.width, height: windowSize.height)
        .windowResizability(.contentSize)
    }
}
