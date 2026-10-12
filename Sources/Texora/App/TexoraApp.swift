import SwiftUI
import AppKit

@main
struct TexoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Texora", id: "main") {
            RootView()
                .environment(model)
                .environment(model.themes)
                .environment(model.settings)
                .environment(\.theme, model.themes.current)
                .preferredColorScheme(model.themes.current.colorScheme)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    delegate.model = model
                    model.themes.apply()
                    DebugAutomation.startIfRequested(model: model)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { TexoraCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .environment(model.themes)
                .environment(model.settings)
                .environment(\.theme, model.themes.current)
                .preferredColorScheme(model.themes.current.colorScheme)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            model?.workspace?.close()
            model?.library.saveNow()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { model?.handleOpen(url: url) }
        }
    }
}
