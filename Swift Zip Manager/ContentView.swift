import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var manager = ArchiveManager()
    @StateObject private var recentManager = RecentFilesManager()
    @StateObject private var toolInstaller = ToolInstaller()
    @State private var currentDirectory: URL? = FileManager.default.homeDirectoryForCurrentUser
    @State private var viewMode: RightContentView.ViewMode = .list
    @State private var showInstallAlert = false
    @State private var missingTools: [String] = []
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                manager: manager,
                recentManager: recentManager,
                currentDirectory: $currentDirectory
            )
            .environmentObject(appState)
        } detail: {
            RightContentView(
                manager: manager,
                recentManager: recentManager,
                currentDirectory: $currentDirectory,
                viewMode: $viewMode
            )
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .alert(manager.error ?? "Done", isPresented: $manager.showAlert) {
            Button("OK") { }
        }
        .sheet(isPresented: $appState.showNewArchive) {
            NewArchiveView(manager: manager)
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView(
                appState: appState,
                languageManager: languageManager,
                toolInstaller: toolInstaller
            )
        }
        .onAppear {
            let missing = toolInstaller.checkTools()
            if !missing.isEmpty {
                missingTools = missing
                showInstallAlert = true
            }
        }
        .alert("Missing Tools", isPresented: $showInstallAlert) {
            Button("Install All") {
                installTools()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("This app requires additional tools for archive operations:\n\n• 7zz: Universal extractor (supports ZIP, RAR, 7Z, TAR, etc.)\n• rar: RAR compression only\n\nClick Install to download and set up these tools.")
        }
    }
    
    func installTools() {
        toolInstaller.installTools(missingTools, progress: { _, _ in }, completion: { success, message in
            if success {
                manager.error = "Tools installed. Please restart the app."
            } else {
                manager.error = "Install failed: \(message)"
            }
            manager.showAlert = true
        })
    }
}
