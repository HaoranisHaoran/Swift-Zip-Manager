import SwiftUI

// MARK: - 语言管理器
class LanguageManager: ObservableObject {
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }
    
    init() {
        if let lang = UserDefaults.standard.array(forKey: "AppleLanguages")?.first as? String {
            currentLanguage = lang
        } else {
            currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        }
    }
}

// MARK: - 通知扩展
extension Notification.Name {
    static let languageChanged = Notification.Name("languageChangedNotification")
    static let openArchive = Notification.Name("openArchiveNotification")
    static let showOpenPanel = Notification.Name("showOpenPanelNotification")
    static let showHelp = Notification.Name("showHelpNotification")
    static let checkForUpdates = Notification.Name("checkForUpdatesNotification")
}
