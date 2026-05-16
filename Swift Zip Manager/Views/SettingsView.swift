import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var languageManager: LanguageManager
    @ObservedObject var toolInstaller: ToolInstaller
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = "general"
    
    @State private var selectedLanguage: String
    @State private var isCheckingTools = false
    @State private var missingTools: [String] = []
    @State private var showInstallAlert = false
    @State private var installProgress: Double = 0
    @State private var isInstalling = false
    @State private var installMessage = ""
    @State private var showDeleteConfirm = false
    
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @State private var showUpdateSheet = false
    
    @State private var versionTapCount = 0
    @State private var lastTapTime = Date()
    
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
    
    private var currentVersion: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(shortVersion) (Build \(build))"
    }
    
    init(appState: AppState, languageManager: LanguageManager, toolInstaller: ToolInstaller) {
        self.appState = appState
        self.languageManager = languageManager
        self.toolInstaller = toolInstaller
        self._selectedLanguage = State(initialValue: languageManager.currentLanguage)
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("General", systemImage: "gear").tag("general")
                Label("Tools", systemImage: "wrench.and.screwdriver").tag("tools")
                Label("Updates", systemImage: "arrow.triangle.2.circlepath").tag("updates")
                Label("About", systemImage: "info.circle").tag("about")
                
                if appState.isDeveloperMode {
                    Divider()
                    Label("Developer", systemImage: "hammer.fill")
                        .foregroundColor(.orange)
                        .tag("developer")
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if selectedTab == "general" {
                            generalView
                        } else if selectedTab == "tools" {
                            toolsView
                        } else if selectedTab == "updates" {
                            updatesView
                        } else if selectedTab == "about" {
                            aboutView
                        } else if selectedTab == "developer" {
                            DeveloperSettingsView(appState: appState)
                        }
                    }
                    .padding(24)
                }
                
                Divider()
                
                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .padding(.trailing, 20)
                    .padding(.vertical, 12)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            .frame(minWidth: 500)
        }
        .frame(width: 750, height: 550)
        .sheet(isPresented: $showUpdateSheet) {
            if let update = updateChecker.updateAvailable {
                VStack {
                    Text("New Version Available").font(.headline)
                    Text("Build \(update.buildNumber)").font(.caption)
                    Text(update.body).font(.caption).padding()
                    HStack {
                        Button("Later") { showUpdateSheet = false }
                        Button("Download") { startDownload(); showUpdateSheet = false }
                    }
                }
                .padding()
                .frame(width: 400, height: 300)
            }
        }
        .alert("Missing Tools", isPresented: $showInstallAlert) {
            Button("Install All") { installTools() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Delete Tools", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteTools() }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    // MARK: - General View
    @ViewBuilder
    private var generalView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.largeTitle)
                .bold()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Language")
                    .font(.title3)
                    .bold()
                
                HStack {
                    Text("Display Language")
                        .frame(width: 140, alignment: .leading)
                    Picker("", selection: $selectedLanguage) {
                        ForEach(languages.keys.sorted(), id: \.self) { code in
                            Text(languages[code] ?? code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .onChange(of: selectedLanguage) { newValue in
                        if newValue != languageManager.currentLanguage {
                            languageManager.currentLanguage = newValue
                            showRestartAlert()
                        }
                    }
                }
                
                Text("Language change requires app restart")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 148)
            }
        }
    }
    
    // MARK: - Tools View
    @ViewBuilder
    private var toolsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tools")
                .font(.largeTitle)
                .bold()
            
            Text("Install and manage archive tools (7zz and RAR).")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    Text("Status:")
                        .frame(width: 100, alignment: .leading)
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if isInstalling {
                            VStack {
                                ProgressView(value: installProgress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 250)
                                if !installMessage.isEmpty {
                                    Text(installMessage).font(.caption)
                                }
                            }
                        } else if isCheckingTools {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Checking...").font(.caption)
                            }
                        } else {
                            let missing = toolInstaller.checkTools()
                            if missing.isEmpty {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                    Text("All tools installed").foregroundColor(.green)
                                }
                            } else {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                        Text("\(missing.count) tool(s) missing").foregroundColor(.orange)
                                    }
                                    ForEach(missing, id: \.self) { tool in
                                        Text(tool).font(.caption).padding(.leading, 20)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                HStack(spacing: 16) {
                    Button(action: checkAndInstallTools) {
                        Label(isInstalling ? "Installing..." : "Install 7zz & RAR", systemImage: "arrow.down.circle")
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
            }
        }
    }
    
    // MARK: - Updates View
    @ViewBuilder
    private var updatesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Updates")
                .font(.largeTitle)
                .bold()
            
            Text("Check for new versions and manage update settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Current Version")
                        .frame(width: 140, alignment: .leading)
                        .font(.headline)
                    Text(currentVersion)
                }
                
                Divider()
                
                HStack {
                    Text("Auto-check")
                        .frame(width: 140, alignment: .leading)
                        .font(.headline)
                    Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                        .toggleStyle(.switch)
                }
                
                HStack {
                    Text("")
                        .frame(width: 140, alignment: .leading)
                    Button(action: { checkForUpdates(showNoUpdateAlert: true) }) {
                        if updateChecker.isChecking {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Checking...")
                            }
                        } else {
                            Text("Check for Updates")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(updateChecker.isChecking)
                }
                
                if let update = updateChecker.updateAvailable {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Version \(update.buildNumber) available").font(.caption)
                        Button("View") { showUpdateSheet = true }.buttonStyle(.plain)
                    }
                    .padding(.leading, 148)
                }
                
                if updateChecker.isDownloading {
                    VStack(alignment: .leading) {
                        HStack {
                            ProgressView(value: updateChecker.downloadProgress)
                                .progressViewStyle(.linear)
                                .frame(width: 200)
                            Text(updateChecker.downloadStatus).font(.caption)
                        }
                        Button("Cancel") { updateChecker.cancelDownload() }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                    .padding(.leading, 148)
                }
                
                Text("Updates are downloaded from GitHub Releases")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 148)
            }
        }
    }
    
    // MARK: - About View
    @ViewBuilder
    private var aboutView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.largeTitle)
                .bold()
            
            Divider()
            
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "archivebox")
                        .foregroundColor(.blue)
                        .font(.system(size: 48))
                    VStack(alignment: .leading) {
                        Text("Swift Zip Manager")
                            .font(.title2)
                            .bold()
                        Text("Version \(currentVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .onTapGesture {
                                handleVersionTap()
                            }
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                    }
                }
                
                if appState.isDeveloperMode {
                    HStack {
                        Image(systemName: "hammer.fill").foregroundColor(.orange)
                        Text("Developer Mode Active").font(.caption).foregroundColor(.orange)
                    }
                }
                
                Divider()
                
                Link("GitHub", destination: URL(string: githubURL)!)
                Text("MIT License • Open Source").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Helper Functions
    private func handleVersionTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) > 1.0 {
            versionTapCount = 0
        }
        lastTapTime = now
        versionTapCount += 1
        if versionTapCount >= 5 {
            appState.toggleDeveloperMode()
            versionTapCount = 0
        }
    }
    
    private func showRestartAlert() {
        let alert = NSAlert()
        alert.messageText = "Language Changed"
        alert.informativeText = "Restart to apply changes."
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            exit(0)
        }
    }
    
    private func checkForUpdates(showNoUpdateAlert: Bool) {
        updateChecker.checkForUpdates { hasUpdate, message in
            if hasUpdate {
                showUpdateSheet = true
            } else if showNoUpdateAlert {
                let alert = NSAlert()
                alert.messageText = "No Update Available"
                alert.informativeText = message ?? "Latest version."
                alert.runModal()
            }
        }
    }
    
    private func startDownload() {
        updateChecker.downloadAndInstall(progress: { _, _ in }, completion: { success, msg in
            if !success {
                let alert = NSAlert()
                alert.messageText = "Update Failed"
                alert.informativeText = msg
                alert.runModal()
            }
            showUpdateSheet = false
        })
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
                }
            }
        }
    }
    
    private func installTools() {
        isInstalling = true
        installProgress = 0
        toolInstaller.installTools(missingTools, progress: { p, msg in
            DispatchQueue.main.async {
                installProgress = p
                installMessage = msg
            }
        }, completion: { success, msg in
            DispatchQueue.main.async {
                isInstalling = false
                let alert = NSAlert()
                alert.messageText = success ? "Complete" : "Failed"
                alert.informativeText = msg
                alert.runModal()
            }
        })
    }
    
    private func deleteTools() {
        let success = toolInstaller.deleteTools()
        let alert = NSAlert()
        alert.messageText = success ? "Deleted" : "Failed"
        alert.informativeText = success ? "Tools removed. Restart required." : "Could not delete."
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            exit(0)
        }
    }
}
