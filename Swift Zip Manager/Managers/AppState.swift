import SwiftUI

// MARK: - App State
class AppState: ObservableObject {
    @Published var showNewArchive = false
    @Published var showSettings = false
    @Published var showTools = false
    @Published var showCommandCopied = false
    @Published var showCloseConfirmation = false
    
    // 关闭当前窗口
    func closeCurrentWindow() {
        if let window = NSApplication.shared.keyWindow {
            window.close()
        }
    }
}
