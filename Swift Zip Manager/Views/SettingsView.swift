import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var languageManager: LanguageManager
    @ObservedObject var toolInstaller: ToolInstaller
    @Environment(\.dismiss) var dismiss
    
    // 语言设置
    @State private var tempLanguage: String
    
    // 工具管理
    @State private var isCheckingTools = false
    @State private var missingTools: [String] = []
    @State private var showInstallAlert = false
    @State private var installProgress: Double = 0
    @State private var isInstalling = false
    @State private var installMessage = ""
    @State private var showDeleteConfirm = false
    
    // 自动更新
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @State private var showUpdateSheet = false
    
    let languages = [
        "en": "English",
        "zh-Hans": "简体中文",
        "zh-Hant": "繁體中文",
        "es": "Español",
        "fr": "Français",
        "de": "Deutsch",
        "ja": "日本語",
        "ko": "한국어",
        "ru": "Русский",
        "it": "Italiano",
        "pt": "Português",
        "nl": "Nederlands",
        "sv": "Svenska",
        "da": "Dansk"
    ]
    
    let githubURL = "https://github.com/HaoranisHaoran/Swift-Zip-Manager"
    
    // 当前版本
    private var currentVersion: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(shortVersion) (Build \(build))"
    }
    
    init(appState: AppState, languageManager: LanguageManager, toolInstaller: ToolInstaller) {
        self.appState = appState
        self.languageManager = languageManager
        self.toolInstaller = toolInstaller
        self._tempLanguage = State(initialValue: languageManager.currentLanguage)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()
                .padding(.top)
            
            Form {
                // MARK: - Language Section
                Section("Language") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Display Language")
                                .frame(width: 120, alignment: .leading)
                            Picker("", selection: $tempLanguage) {
                                ForEach(languages.keys.sorted(), id: \.self) { code in
                                    Text(languages[code] ?? code).tag(code)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }
                        
                        Text("Language change requires app restart")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 124)
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - Tools Section
                Section("Tools") {
                    VStack(alignment: .leading, spacing: 12) {
                        // 工具状态
                        HStack(alignment: .top, spacing: 12) {
                            Text("Status:")
                                .frame(width: 100, alignment: .leading)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if isInstalling {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: installProgress)
                                            .progressViewStyle(.linear)
                                            .frame(width: 200)
                                        if !installMessage.isEmpty {
                                            Text(installMessage)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                } else if isCheckingTools {
                                    HStack {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Checking...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    let missing = toolInstaller.checkTools()
                                    if missing.isEmpty {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("All tools installed")
                                                .foregroundColor(.green)
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundColor(.orange)
                                                Text("\(missing.count) tool(s) missing")
                                                    .foregroundColor(.orange)
                                            }
                                            ForEach(missing, id: \.self) { tool in
                                                Text(tool)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .padding(.leading, 20)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        // 操作按钮
                        HStack(spacing: 12) {
                            Button(action: checkAndInstallTools) {
                                if isInstalling {
                                    Label("Installing...", systemImage: "arrow.down.circle")
                                } else {
                                    Label("Install 7zz & RAR", systemImage: "arrow.down.circle")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isInstalling || isCheckingTools)
                            
                            Button(action: { showDeleteConfirm = true }) {
                                Label("Delete Tools", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isInstalling || isCheckingTools)
                        }
                        
                        Text("7zz: Universal extractor (ZIP, RAR, 7Z, TAR, etc.)\nRAR: RAR compression and extraction")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - Updates Section
                Section("Updates") {
                    VStack(alignment: .leading, spacing: 12) {
                        // 当前版本
                        HStack {
                            Text("Current Version")
                                .frame(width: 120, alignment: .leading)
                            Text(currentVersion)
                                .foregroundColor(.primary)
                        }
                        
                        Divider()
                        
                        // 自动检查开关
                        HStack {
                            Text("Auto-check")
                                .frame(width: 120, alignment: .leading)
                            Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                                .toggleStyle(.switch)
                        }
                        
                        // 手动检查按钮
                        HStack {
                            Text("")
                                .frame(width: 120, alignment: .leading)
                            Button(action: {
                                manualCheckForUpdates(showNoUpdateAlert: true)
                            }) {
                                if updateChecker.isChecking {
                                    HStack {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Checking...")
                                    }
                                } else {
                                    Text("Check for Updates")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(updateChecker.isChecking)
                        }
                        
                        // 更新可用提示
                        if let update = updateChecker.updateAvailable {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Version \(update.buildNumber) available")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Button("View") {
                                    showUpdateSheet = true
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }
                            .padding(.leading, 124)
                        }
                        
                        // 下载进度
                        if updateChecker.isDownloading {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    ProgressView(value: updateChecker.downloadProgress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 200)
                                    Text(updateChecker.downloadStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Button("Cancel") {
                                    updateChecker.cancelDownload()
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundColor(.orange)
                            }
                            .padding(.leading, 124)
                        }
                        
                        Text("Updates are downloaded from GitHub Releases")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 124)
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - About Section
                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "archivebox")
                                .foregroundColor(.blue)
                                .font(.title2)
                            Text("Swift Zip Manager")
                                .font(.headline)
                        }
                        
                        Divider()
                        
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(.blue)
                            Text(githubURL)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .underline()
                                .onTapGesture {
                                    if let url = URL(string: githubURL) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                        }
                        
                        HStack {
                            Image(systemName: "c.circle.fill")
                                .foregroundColor(.secondary)
                            Text("MIT License • Open Source")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 560)
            
            // MARK: - Bottom Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Apply") {
                    applyChanges()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 550, height: 680)
        .sheet(isPresented: $showUpdateSheet) {
            if let update = updateChecker.updateAvailable {
                UpdateDialogView(
                    update: update,
                    onDownload: {
                        startDownload()
                    },
                    onCancel: {
                        showUpdateSheet = false
                    }
                )
            }
        }
        .alert("Missing Tools", isPresented: $showInstallAlert) {
            Button("Install All") {
                installTools()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The following tools are required:\n• \(missingTools.joined(separator: "\n• "))")
        }
        .alert("Delete Tools", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTools()
            }
        } message: {
            Text("Are you sure you want to delete 7zz and RAR tools?\n\nYou will need to reinstall them to use archive features.")
        }
        .onAppear {
            // 静默检查更新，不弹窗
            if autoCheckUpdates && updateChecker.updateAvailable == nil && !updateChecker.isChecking {
                manualCheckForUpdates(showNoUpdateAlert: false)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func applyChanges() {
        if tempLanguage != languageManager.currentLanguage {
            languageManager.currentLanguage = tempLanguage
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showRestartAlert()
            }
        } else {
            dismiss()
        }
    }
    
    private func showRestartAlert() {
        let alert = NSAlert()
        alert.messageText = "Language Changed"
        alert.informativeText = "The app needs to restart to apply the new language."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            exit(0)
        }
    }
    
    private func manualCheckForUpdates(showNoUpdateAlert: Bool = false) {
        updateChecker.checkForUpdates { hasUpdate, message in
            if hasUpdate {
                showUpdateSheet = true
            } else if showNoUpdateAlert, let message = message {
                let alert = NSAlert()
                alert.messageText = "No Update Available"
                alert.informativeText = message
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    private func startDownload() {
        updateChecker.downloadAndInstall(
            progress: { _, _ in },
            completion: { success, message in
                if !success {
                    let alert = NSAlert()
                    alert.messageText = "Update Failed"
                    alert.informativeText = message
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                showUpdateSheet = false
            }
        )
    }
    
    private func checkAndInstallTools() {
        isCheckingTools = true
        DispatchQueue.global().async {
            let missing = toolInstaller.checkTools()
            DispatchQueue.main.async {
                isCheckingTools = false
                if !missing.isEmpty {
                    missingTools = missing
                    showInstallAlert = true
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Tools Status"
                    alert.informativeText = "All required tools are already installed."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    private func installTools() {
        isInstalling = true
        installProgress = 0
        
        toolInstaller.installTools(
            missingTools,
            progress: { progress, message in
                DispatchQueue.main.async {
                    installProgress = progress
                    installMessage = message
                }
            },
            completion: { success, message in
                DispatchQueue.main.async {
                    isInstalling = false
                    let alert = NSAlert()
                    if success {
                        alert.messageText = "Installation Complete"
                        alert.informativeText = "Tools installed successfully.\n\nSome features may require app restart."
                        alert.alertStyle = .informational
                    } else {
                        alert.messageText = "Installation Failed"
                        alert.informativeText = message
                        alert.alertStyle = .critical
                    }
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        )
    }
    
    private func deleteTools() {
        let success = toolInstaller.deleteTools()
        
        let alert = NSAlert()
        if success {
            alert.messageText = "Tools Deleted"
            alert.informativeText = "7zz and RAR tools have been removed.\n\nPlease restart the app."
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Delete Failed"
            alert.informativeText = "Failed to delete tools. They may have already been removed or are in use."
            alert.alertStyle = .warning
        }
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            exit(0)
        }
    }
}

// MARK: - Update Dialog View
struct UpdateDialogView: View {
    let update: UpdateChecker.UpdateInfo
    let onDownload: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("New Version Available")
                        .font(.headline)
                    Text("Build \(update.buildNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let size = update.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            Text("What's new:")
                .font(.subheadline)
                .fontWeight(.medium)
            
            ScrollView {
                Text(update.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 120)
            
            Divider()
            
            HStack {
                Button("Later") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Download & Install") {
                    onDownload()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400, height: 320)
    }
}

#Preview {
    SettingsView(
        appState: AppState(),
        languageManager: LanguageManager(),
        toolInstaller: ToolInstaller()
    )
}
