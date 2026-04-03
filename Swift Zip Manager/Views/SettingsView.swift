import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var languageManager: LanguageManager
    @ObservedObject var toolInstaller: ToolInstaller
    @Environment(\.dismiss) var dismiss
    @State private var tempLanguage: String
    @State private var showRestartAlert = false
    @State private var isChecking = false
    @State private var missingTools: [String] = []
    @State private var showInstallAlert = false
    @State private var installProgress: Double = 0
    @State private var isInstalling = false
    
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
                // 语言选择
                Section("Language") {
                    Picker("Display Language", selection: $tempLanguage) {
                        ForEach(languages.keys.sorted(), id: \.self) { code in
                            Text(languages[code] ?? code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // 工具检查与安装
                Section("Tools") {
                    HStack {
                        Text("Status:")
                        Spacer()
                        if isInstalling {
                            ProgressView(value: installProgress)
                                .progressViewStyle(.linear)
                                .frame(width: 150)
                        } else if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            let missing = toolInstaller.checkTools()
                            if missing.isEmpty {
                                Text("All tools installed")
                                    .foregroundColor(.green)
                            } else {
                                Text("\(missing.count) tools missing")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Button(isInstalling ? "Installing..." : "Check & Install Tools") {
                        checkAndInstall()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstalling || isChecking)
                }
                
                // 关于
                Section("About") {
                    HStack {
                        Image(systemName: "archivebox")
                            .foregroundColor(.blue)
                        Text("Swift Zip Manager")
                            .font(.headline)
                    }
                    Text("Version 1.0.0 Beta 2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Divider()
                    HStack {
                        Image(systemName: "link.circle.fill")
                            .font(.caption)
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
                }
            }
            .formStyle(.grouped)
            .frame(height: 380)
            
            HStack {
                Button("Apply") {
                    if tempLanguage != languageManager.currentLanguage {
                        languageManager.currentLanguage = tempLanguage
                        showRestartAlert = true
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom)
        }
        .frame(width: 500, height: 520)
        .alert("Language Changed", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                exit(0)
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("The app needs to restart to apply the new language.")
        }
        .alert("Missing Tools", isPresented: $showInstallAlert) {
            Button("Install All") {
                installTools()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The following tools are required:\n• \(missingTools.joined(separator: "\n• "))")
        }
    }
    
    func checkAndInstall() {
        isChecking = true
        DispatchQueue.global().async {
            let missing = toolInstaller.checkTools()
            DispatchQueue.main.async {
                isChecking = false
                if !missing.isEmpty {
                    missingTools = missing
                    showInstallAlert = true
                } else {
                    // 所有工具已安装
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
    
    func installTools() {
        isInstalling = true
        installProgress = 0
        
        toolInstaller.installTools(
            missingTools,
            progress: { progress, message in
                DispatchQueue.main.async {
                    installProgress = progress
                }
            },
            completion: { success, message in
                DispatchQueue.main.async {
                    isInstalling = false
                    if success {
                        let alert = NSAlert()
                        alert.messageText = "Installation Complete"
                        alert.informativeText = "Tools installed successfully. Please restart the app for changes to take effect."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "Restart Now")
                        alert.addButton(withTitle: "Later")
                        if alert.runModal() == .alertFirstButtonReturn {
                            exit(0)
                        }
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Installation Failed"
                        alert.informativeText = message
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        )
    }
}
