import AppKit
import SwiftUI

@main
struct MiyoiApp: App {
    @StateObject private var manager = DeviceManager()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Miyoi") {
            ContentView()
                .environmentObject(manager)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let window = NSApp.windows.first {
                            window.makeKeyAndOrderFront(nil)
                            window.styleMask.remove(.resizable)
                            window.collectionBehavior.remove(.fullScreenPrimary)
                            window.standardWindowButton(.zoomButton)?.isHidden = true
                        }
                    }
                }
        }
        .defaultSize(width: 820, height: 760)
        .windowResizability(.contentSize)
    }
}
