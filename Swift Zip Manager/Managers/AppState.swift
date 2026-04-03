import SwiftUI

// MARK: - App State
class AppState: ObservableObject {
    @Published var showNewArchive = false
    @Published var showSettings = false
    @Published var showTools = false
    @Published var showCommandCopied = false
}

// MARK: - 通知名称扩展
extension Notification.Name {
    static let openArchiveNotification = Notification.Name("openArchiveNotification")
    static let showOpenPanelNotification = Notification.Name("showOpenPanelNotification")
    static let showHelpNotification = Notification.Name("showHelpNotification")
    static let languageChangedNotification = Notification.Name("languageChangedNotification")
}
