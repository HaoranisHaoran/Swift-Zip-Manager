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
            // 文件菜单
            CommandGroup(after: .newItem) {
                Button("New Archive") {
                    appState.showNewArchive = true
                }
                .keyboardShortcut("a", modifiers: .command)
                
                Button("Open Archive") {
                    NotificationCenter.default.post(name: .openArchiveNotification, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("New Window") {
                    newWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                
                Button("Close Window") {
                    closeCurrentWindow()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            
            // 编辑菜单
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Extract Selected") {
                    NotificationCenter.default.post(name: .extractSelectedNotification, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                
                Button("Extract All") {
                    NotificationCenter.default.post(name: .extractAllNotification, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Delete from Archive") {
                    NotificationCenter.default.post(name: .deleteSelectedNotification, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
            
            // 显示菜单
            CommandGroup(after: .toolbar) {
                Button("Show in Finder") {
                    NotificationCenter.default.post(name: .showInFinderNotification, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            // 帮助菜单
            CommandGroup(replacing: .help) {
                Button("Swift Zip Manager Help") {
                    NotificationCenter.default.post(name: .showHelpNotification, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
            
            // 更新菜单
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Check for Updates...") {
                    updateChecker.checkForUpdates(showIfNone: true)
                }
                .keyboardShortcut("u", modifiers: .command)
            }
        }
    }
    
    private func newWindow() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }
    
    private func closeCurrentWindow() {
        NSApplication.shared.keyWindow?.close()
    }
}

// MARK: - 通知扩展
extension Notification.Name {
    static let checkForUpdatesNotification = Notification.Name("checkForUpdatesNotification")
    static let openArchiveNotification = Notification.Name("openArchiveNotification")
    static let showOpenPanelNotification = Notification.Name("showOpenPanelNotification")
    static let showHelpNotification = Notification.Name("showHelpNotification")
    static let extractSelectedNotification = Notification.Name("extractSelectedNotification")
    static let extractAllNotification = Notification.Name("extractAllNotification")
    static let deleteSelectedNotification = Notification.Name("deleteSelectedNotification")
    static let showInFinderNotification = Notification.Name("showInFinderNotification")
}
