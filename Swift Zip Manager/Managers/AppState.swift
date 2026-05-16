import SwiftUI

// MARK: - App State
class AppState: ObservableObject {
    @Published var showNewArchive = false
    @Published var showSettings = false
    @Published var showTools = false
    @Published var showCommandCopied = false
    @Published var showCloseConfirmation = false
    @Published var showDeveloperWindow = false
    
    // 开发者模式
    @Published var isDeveloperMode = false
    @Published var devLogs: [DevLogEntry] = []
    @Published var devMetrics = DevMetrics()
    
    // 开发者设置 - Debug
    @Published var customToolPath7zz = ""
    @Published var customToolPathRar = ""
    @Published var useCustomToolPaths = false
    @Published var debugLoggingEnabled = false
    @Published var showHiddenFiles = false
    
    // 开发者设置 - Experimental
    @Published var experimentalParallelExtract = false
    @Published var experimentalNewExtractor = false
    @Published var experimentalFastZip = false
    
    // 开发者设置 - Unstable
    @Published var unstableAsyncWrite = false
    @Published var unstableMemoryExtract = false
    @Published var unstableSkipPermissions = false
    
    // 开发者设置 - Advanced
    @Published var advancedMemoryLimit = 512
    @Published var advancedTempDir = ""
    @Published var advancedMaxConcurrent = 4
    
    init() {
        isDeveloperMode = UserDefaults.standard.bool(forKey: "DeveloperMode")
        loadDeveloperSettings()
        if isDeveloperMode {
            addDevLog("Developer Mode Active", type: .info)
        }
    }
    
    func closeCurrentWindow() {
        if let window = NSApplication.shared.keyWindow {
            window.close()
        }
    }
    
    func toggleDeveloperMode() {
        isDeveloperMode.toggle()
        UserDefaults.standard.set(isDeveloperMode, forKey: "DeveloperMode")
        
        if isDeveloperMode {
            addDevLog("Developer Mode Enabled", type: .info)
        } else {
            addDevLog("Developer Mode Disabled", type: .info)
        }
    }
    
    func openDeveloperWindow() {
        showDeveloperWindow = true
    }
    
    func addDevLog(_ message: String, type: DevLogType = .info) {
        guard isDeveloperMode else { return }
        let entry = DevLogEntry(message: message, type: type, date: Date())
        DispatchQueue.main.async {
            self.devLogs.insert(entry, at: 0)
            if self.devLogs.count > 500 {
                self.devLogs.removeLast()
            }
        }
    }
    
    private func loadDeveloperSettings() {
        customToolPath7zz = UserDefaults.standard.string(forKey: "CustomToolPath7zz") ?? ""
        customToolPathRar = UserDefaults.standard.string(forKey: "CustomToolPathRar") ?? ""
        useCustomToolPaths = UserDefaults.standard.bool(forKey: "UseCustomToolPaths")
        debugLoggingEnabled = UserDefaults.standard.bool(forKey: "DebugLoggingEnabled")
        showHiddenFiles = UserDefaults.standard.bool(forKey: "ShowHiddenFiles")
        
        experimentalParallelExtract = UserDefaults.standard.bool(forKey: "ExperimentalParallelExtract")
        experimentalNewExtractor = UserDefaults.standard.bool(forKey: "ExperimentalNewExtractor")
        experimentalFastZip = UserDefaults.standard.bool(forKey: "ExperimentalFastZip")
        
        unstableAsyncWrite = UserDefaults.standard.bool(forKey: "UnstableAsyncWrite")
        unstableMemoryExtract = UserDefaults.standard.bool(forKey: "UnstableMemoryExtract")
        unstableSkipPermissions = UserDefaults.standard.bool(forKey: "UnstableSkipPermissions")
        
        advancedMemoryLimit = UserDefaults.standard.integer(forKey: "AdvancedMemoryLimit")
        if advancedMemoryLimit == 0 { advancedMemoryLimit = 512 }
        advancedTempDir = UserDefaults.standard.string(forKey: "AdvancedTempDir") ?? ""
        advancedMaxConcurrent = UserDefaults.standard.integer(forKey: "AdvancedMaxConcurrent")
        if advancedMaxConcurrent == 0 { advancedMaxConcurrent = 4 }
    }
    
    func saveDeveloperSettings() {
        UserDefaults.standard.set(customToolPath7zz, forKey: "CustomToolPath7zz")
        UserDefaults.standard.set(customToolPathRar, forKey: "CustomToolPathRar")
        UserDefaults.standard.set(useCustomToolPaths, forKey: "UseCustomToolPaths")
        UserDefaults.standard.set(debugLoggingEnabled, forKey: "DebugLoggingEnabled")
        UserDefaults.standard.set(showHiddenFiles, forKey: "ShowHiddenFiles")
        
        UserDefaults.standard.set(experimentalParallelExtract, forKey: "ExperimentalParallelExtract")
        UserDefaults.standard.set(experimentalNewExtractor, forKey: "ExperimentalNewExtractor")
        UserDefaults.standard.set(experimentalFastZip, forKey: "ExperimentalFastZip")
        
        UserDefaults.standard.set(unstableAsyncWrite, forKey: "UnstableAsyncWrite")
        UserDefaults.standard.set(unstableMemoryExtract, forKey: "UnstableMemoryExtract")
        UserDefaults.standard.set(unstableSkipPermissions, forKey: "UnstableSkipPermissions")
        
        UserDefaults.standard.set(advancedMemoryLimit, forKey: "AdvancedMemoryLimit")
        UserDefaults.standard.set(advancedTempDir, forKey: "AdvancedTempDir")
        UserDefaults.standard.set(advancedMaxConcurrent, forKey: "AdvancedMaxConcurrent")
    }
}

// MARK: - 开发者日志模型
struct DevLogEntry: Identifiable {
    let id = UUID()
    let message: String
    let type: DevLogType
    let date: Date
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    var icon: String {
        switch type {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .success: return "checkmark.circle"
        }
    }
    
    var color: Color {
        switch type {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

enum DevLogType {
    case info, warning, error, success
}

// MARK: - 开发者指标
struct DevMetrics {
    var totalAPICalls: Int = 0
    var successfulAPICalls: Int = 0
    var failedAPICalls: Int = 0
    var averageAPIDuration: TimeInterval = 0
}

// MARK: - 通知扩展
extension Notification.Name {
    static let LanguageChanged = Notification.Name("languageChangedNotification")
    static let OpenArchive = Notification.Name("openArchiveNotification")
    static let ShowOpenPanel = Notification.Name("showOpenPanelNotification")
    static let ShowHelp = Notification.Name("showHelpNotification")
    static let CheckForUpdates = Notification.Name("checkForUpdatesNotification")
    static let reloadFileList = Notification.Name("reloadFileList")
    static let parallelExtractionChanged = Notification.Name("parallelExtractionChanged")
    static let newExtractorChanged = Notification.Name("newExtractorChanged")
    static let asyncWriteChanged = Notification.Name("asyncWriteChanged")
    static let developerSettingsChanged = Notification.Name("developerSettingsChanged")
    static let developerSettingsReset = Notification.Name("developerSettingsReset")
}
