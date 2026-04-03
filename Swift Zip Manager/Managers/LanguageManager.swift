import SwiftUI

// MARK: - 语言管理器
class LanguageManager: ObservableObject {
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: .languageChangedNotification, object: nil)
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
