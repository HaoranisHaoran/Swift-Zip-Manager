import SwiftUI

@main
struct SwiftZipManagerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var languageManager = LanguageManager()
    @State private var showHelp = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(languageManager)
                .frame(minWidth: 700, minHeight: 450)
                .onReceive(NotificationCenter.default.publisher(for: .openArchive)) { _ in
                    NotificationCenter.default.post(name: .showOpenPanel, object: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
                    showHelp = true
                }
                .sheet(isPresented: $showHelp) {
                    HelpView()
                }
        }
        .commands {
            // 替换系统的帮助菜单
            CommandGroup(replacing: .help) {
                Button("Swift Zip Manager Help") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Button("New Archive") {
                    appState.activeSheet = .newArchive
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Button("Open Archive") {
                    NotificationCenter.default.post(name: .openArchive, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

// 通知名称扩展
extension Notification.Name {
    static let openArchive = Notification.Name("openArchive")
    static let showOpenPanel = Notification.Name("showOpenPanel")
    static let showHelp = Notification.Name("showHelp")
    static let languageChanged = Notification.Name("languageChanged")
}
