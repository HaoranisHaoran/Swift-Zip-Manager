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
    @State private var installMessage = ""
    @State private var showDeleteConfirm = false
    
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
                Section("Language") {
                    Picker("Display Language", selection: $tempLanguage) {
                        ForEach(languages.keys.sorted(), id: \.self) { code in
                            Text(languages[code] ?? code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Section("Tools") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Status:")
                            Spacer()
                            if isInstalling {
                                VStack(alignment: .trailing, spacing: 4) {
                                    ProgressView(value: installProgress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 150)
                                    if !installMessage.isEmpty {
                                        Text(installMessage)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else if isChecking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                let missing = toolInstaller.checkTools()
                                if missing.isEmpty {
                                    Text("All tools installed ✓")
                                        .foregroundColor(.green)
                                } else {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(missing.count) tools missing")
                                            .foregroundColor(.orange)
                                        ForEach(missing, id: \.self) { tool in
                                            Text(tool)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            Button(isInstalling ? "Installing..." : "Install 7zz & RAR Tools") {
                                checkAndInstall()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isInstalling || isChecking)
                            
                            Button("Delete Tools") {
                                showDeleteConfirm = true
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                            .disabled(isInstalling || isChecking)
                        }
                        
                        Text("7zz: Universal extractor (ZIP, RAR, 7Z, TAR, etc.)\nRAR: RAR compression and extraction")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                
                Section("About") {
                    HStack {
                        Image(systemName: "archivebox")
                            .foregroundColor(.blue)
                        Text("Swift Zip Manager")
                            .font(.headline)
                    }
                    Text("Version 1.0.0 Beta 3")
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
            .frame(height: 460)
            
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
        .frame(width: 500, height: 600)
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
        .alert("Delete Tools", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTools()
            }
        } message: {
            Text("Are you sure you want to delete 7zz and RAR tools?\n\nYou will need to reinstall them to use archive features.")
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
                    installMessage = message
                }
            },
            completion: { success, message in
                DispatchQueue.main.async {
                    isInstalling = false
                    if success {
                        let alert = NSAlert()
                        alert.messageText = "Installation Complete"
                        alert.informativeText = "Tools installed successfully to ~/Library/Application Support/SwiftZipManager/tools/\n\nPlease restart the app for changes to take effect."
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
    
    func deleteTools() {
        let success = toolInstaller.deleteTools()
        
        let alert = NSAlert()
        if success {
            alert.messageText = "Tools Deleted"
            alert.informativeText = "7zz and RAR tools have been removed from ~/Library/Application Support/SwiftZipManager/tools/\n\nPlease restart the app."
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
