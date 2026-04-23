import SwiftUI

@main
struct SwiftZipManagerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @State private var showHelp = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(languageManager)
                .frame(minWidth: 900, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: .openArchiveNotification)) { _ in
                    NotificationCenter.default.post(name: .showOpenPanelNotification, object: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: .showHelpNotification)) { _ in
                    showHelp = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .checkForUpdatesNotification)) { _ in
                    updateChecker.checkForUpdates(showIfNone: true)
                }
                .sheet(isPresented: $showHelp) {
                    HelpView()
                }
                .onAppear {
                    if autoCheckUpdates {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            updateChecker.checkForUpdates()
                        }
                    }
                }
        }
        .commands {
            // 设置菜单 ⌘,
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            // 文件菜单中的新建归档 ⌘N 和打开 ⌘O
            CommandGroup(after: .newItem) {
                Button("New Archive") {
                    appState.showNewArchive = true
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Open Archive") {
                    NotificationCenter.default.post(name: .openArchiveNotification, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("New Window") {
                    newWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }
            
            // 帮助菜单 ⌘?
            CommandGroup(replacing: .help) {
                Button("Swift Zip Manager Help") {
                    NotificationCenter.default.post(name: .showHelpNotification, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
            
            // 检查更新 ⌘U
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Check for Updates...") {
                    updateChecker.checkForUpdates(showIfNone: true)
                }
                .keyboardShortcut("u", modifiers: .command)
            }
        }
    }
    
    // 新建窗口
    private func newWindow() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }
    
    // 关闭所有窗口
    private func closeAllWindows() {
        for window in NSApplication.shared.windows {
            window.close()
        }
    }
}

// MARK: - 通知扩展
extension Notification.Name {
    static let checkForUpdatesNotification = Notification.Name("checkForUpdatesNotification")
    static let openArchiveNotification = Notification.Name("openArchiveNotification")
    static let showOpenPanelNotification = Notification.Name("showOpenPanelNotification")
    static let showHelpNotification = Notification.Name("showHelpNotification")
}
