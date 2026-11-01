import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private let overlay = SelectionOverlay()
    private var window: NSWindow?
    private var launchedAsLoginItem = false
    private lazy var model = AppModel { [weak self] in self?.startCapture() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch event is only available this early.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchKind = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        launchedAsLoginItem = launchKind == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        statusItem = makeStatusItem()

        OCR.warmUp()
        hotKey = HotKey { [weak self] in self?.startCapture() }
        if hotKey == nil {
            Toast.show("Không đăng ký được ⌘⇧T: app khác đang giữ phím này")
        }

        model.enableLaunchAtLoginOnFirstRun()
        if !launchedAsLoginItem || !model.hasScreenAccess {
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    /// An accessory app shows no menu bar, but these still provide ⌘W, ⌘Q and ⌘C in the window.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Thoát Copylens", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let editMenu = NSMenu(title: "Sửa")
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        let windowMenu = NSMenu(title: "Cửa sổ")
        windowMenu.addItem(NSMenuItem(title: "Đóng", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let menu = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Copylens")

        let menu = NSMenu()
        let capture = NSMenuItem(title: "Trích xuất text", action: #selector(startCapture), keyEquivalent: "t")
        capture.keyEquivalentModifierMask = [.command, .shift]
        capture.target = self
        menu.addItem(capture)
        let open = NSMenuItem(title: "Mở Copylens…", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Thoát", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        return item
    }

    @objc private func showWindow() {
        model.refresh()
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: MainView(model: model)))
        window.title = "Copylens"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.center()
        return window
    }

    @objc private func startCapture() {
        guard !overlay.isActive else {
            overlay.cancel()
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            showWindow()
            model.openScreenRecordingSettings()
            Toast.show("Hãy cấp quyền Screen Recording rồi mở lại app")
            return
        }
        // Our own windows are left out of the capture, so they must not appear to cover the text.
        let hidden = window?.isVisible == true ? window : nil
        hidden?.orderOut(nil)
        overlay.onDismiss = { hidden?.orderFront(nil) }
        overlay.begin { [weak self] rect, screen in
            self?.extract(rect: rect, screen: screen)
        }
    }

    private func extract(rect: CGRect, screen: NSScreen) {
        Task { @MainActor in
            // Normally done before this shows; it matters while the model is still compiling.
            let progress = Task { @MainActor in
                try await Task.sleep(for: .milliseconds(500))
                Toast.show("Đang đọc text…", autoHide: false)
            }
            defer { progress.cancel() }
            do {
                let image = try await ScreenCapture.image(of: rect, on: screen)
                let result = try await OCR.recognizeRacing(image)
                let text = result.text
                progress.cancel()
                if text.isEmpty {
                    Toast.show("Không tìm thấy text")
                } else {
                    model.copy(text)
                    model.add(text, usedFallback: result.usedFallback)
                    Toast.show(result.usedFallback
                        ? "Đã copy \(text.count) ký tự (chế độ nhanh, không có dấu tiếng Việt)"
                        : "Đã copy \(text.count) ký tự")
                }
            } catch {
                progress.cancel()
                Toast.show("Lỗi: \(error.localizedDescription)")
            }
        }
    }
}
