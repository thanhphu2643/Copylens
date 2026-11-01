import AppKit
import ServiceManagement

struct Extraction: Identifiable {
    let id = UUID()
    let text: String
    let usedFallback: Bool
    let date = Date()
}

/// State behind the main window. Recent text stays in memory only: what people
/// capture can be sensitive, so it's gone when the app quits.
@MainActor
final class AppModel: ObservableObject {
    private static let maxRecents = 20
    private static let configuredLoginKey = "didConfigureLaunchAtLogin"

    @Published private(set) var recents: [Extraction] = []
    @Published private(set) var hasScreenAccess = CGPreflightScreenCaptureAccess()
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var loginError: String?

    let startCapture: () -> Void
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    /// A login item points at this copy of the app, so it must live where it will stay.
    var isInstalled: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    init(startCapture: @escaping () -> Void) {
        self.startCapture = startCapture
        refresh()
    }

    func refresh() {
        hasScreenAccess = CGPreflightScreenCaptureAccess()
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        loginNeedsApproval = status == .requiresApproval
    }

    /// On by default, once. Turning it off afterwards sticks.
    func enableLaunchAtLoginOnFirstRun() {
        let defaults = UserDefaults.standard
        guard isInstalled, !defaults.bool(forKey: Self.configuredLoginKey) else { return }
        defaults.set(true, forKey: Self.configuredLoginKey)
        setLaunchAtLogin(true)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func add(_ text: String, usedFallback: Bool) {
        recents.insert(Extraction(text: text, usedFallback: usedFallback), at: 0)
        recents.removeLast(max(0, recents.count - Self.maxRecents))
    }

    func clearRecents() {
        recents = []
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
