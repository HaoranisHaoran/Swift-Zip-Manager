import SwiftUI

@main
struct SwiftZipManagerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var languageManager = LanguageManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(languageManager)
                .frame(minWidth: 700, minHeight: 450)
        }
        .commands {
            // 只添加自定义的归档命令，帮助菜单完全由系统管理
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

// 添加通知名称扩展
extension Notification.Name {
    static let openArchive = Notification.Name("openArchive")
}
