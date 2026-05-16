import SwiftUI

struct DeveloperSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedCategory: DevCategory = .debug
    
    enum DevCategory: String, CaseIterable {
        case debug = "Debug"
        case experimental = "Experimental Features"
        case unstable = "Unstable Features"
        case advanced = "Advanced Settings"
        
        var icon: String {
            switch self {
            case .debug: return "ladybug.fill"
            case .experimental: return "flask.fill"
            case .unstable: return "exclamationmark.triangle.fill"
            case .advanced: return "gearshape.2.fill"
            }
        }
        
        var description: String {
            switch self {
            case .debug: return "Debugging tools and diagnostics"
            case .experimental: return "Experimental features (may change or be removed)"
            case .unstable: return "Unstable features (may crash or lose data)"
            case .advanced: return "Advanced settings for power users"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Developer")
                .font(.largeTitle)
                .bold()
            
            Text("Tools for developers and advanced users")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            Picker("", selection: $selectedCategory) {
                ForEach(DevCategory.allCases, id: \.self) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 8)
            
            Text(selectedCategory.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                switch selectedCategory {
                case .debug:
                    debugView
                case .experimental:
                    experimentalView
                case .unstable:
                    unstableView
                case .advanced:
                    advancedView
                }
            }
        }
        .onDisappear {
            appState.saveDeveloperSettings()
            applySettings()
        }
    }
    
    // MARK: - Debug View
    @ViewBuilder
    private var debugView: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Debug Logging", isOn: $appState.debugLoggingEnabled)
                    
                    Text("Log all operations to console and developer panel")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                    
                    Divider()
                    
                    Toggle("Show Hidden Files", isOn: $appState.showHiddenFiles)
                    
                    Text("Show .DS_Store, .localized and other hidden files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                    
                    Divider()
                    
                    HStack {
                        Button("Export Debug Logs") {
                            exportLogs()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear Logs") {
                            appState.devLogs.removeAll()
                            appState.addDevLog("Logs cleared", type: .info)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("View Logs in Console") {
                            openConsole()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            } label: {
                Text("Logging")
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use Custom Tool Paths", isOn: $appState.useCustomToolPaths)
                    
                    if appState.useCustomToolPaths {
                        HStack {
                            Text("7zz Path:")
                                .frame(width: 80, alignment: .leading)
                            TextField("/usr/local/bin/7zz", text: $appState.customToolPath7zz)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                browseForTool("7zz")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        HStack {
                            Text("RAR Path:")
                                .frame(width: 80, alignment: .leading)
                            TextField("/usr/local/bin/rar", text: $appState.customToolPathRar)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                browseForTool("rar")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Text("⚠️ Changes will take effect after app restart")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.leading, 88)
                    }
                }
                .padding()
            } label: {
                Text("Tool Paths")
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Simulate Archive Load") {
                        appState.addDevLog("Simulating archive load", type: .info)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            appState.addDevLog("Archive load simulation completed", type: .success)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Simulate Extraction Error") {
                        appState.addDevLog("Simulating extraction error", type: .warning)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            appState.addDevLog("Extraction failed: Corrupted archive", type: .error)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Test Tool Paths") {
                        testToolPaths()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } label: {
                Text("Test Operations")
            }
        }
    }
    
    // MARK: - Experimental View
    @ViewBuilder
    private var experimentalView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Parallel Extraction", isOn: $appState.experimentalParallelExtract)
                    
                    Text("Extract multiple files simultaneously for faster performance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                    
                    Divider()
                    
                    Toggle("New Extraction Engine", isOn: $appState.experimentalNewExtractor)
                    
                    Text("Use the new extraction engine with better performance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                    
                    Divider()
                    
                    Toggle("Fast ZIP Processing", isOn: $appState.experimentalFastZip)
                    
                    Text("Skip CRC check for faster ZIP extraction (less reliable)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                }
                .padding()
            } label: {
                Text("Experimental Features")
            }
            
            HStack {
                Image(systemName: "info.circle")
                Text("⚠️ These features are experimental and may change or be removed")
                    .font(.caption)
            }
            .foregroundColor(.orange)
        }
    }
    
    // MARK: - Unstable View
    @ViewBuilder
    private var unstableView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Async File Writing", isOn: $appState.unstableAsyncWrite)
                    
                    Text("Write files asynchronously (may cause data loss if app crashes)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.leading, 24)
                    
                    Divider()
                    
                    Toggle("In-Memory Extraction", isOn: $appState.unstableMemoryExtract)
                    
                    Text("Extract directly to memory (high RAM usage, may crash on large files)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.leading, 24)
                    
                    Divider()
                    
                    Toggle("Skip Permission Checks", isOn: $appState.unstableSkipPermissions)
                    
                    Text("Bypass file permission checks (security risk)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.leading, 24)
                }
                .padding()
            } label: {
                Label("Unstable Features", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
            
            VStack {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("⚠️⚠️ WARNING: These features are unstable and may cause crashes or data loss ⚠️⚠️")
                        .font(.caption)
                }
            }
            .foregroundColor(.red)
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Advanced View
    @ViewBuilder
    private var advancedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Memory Limit (MB):")
                            .frame(width: 120, alignment: .leading)
                        TextField("512", value: $appState.advancedMemoryLimit, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("MB")
                            .font(.caption)
                        Button("Apply") {
                            applyMemoryLimit()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("Maximum memory usage during extraction")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 124)
                    
                    Divider()
                    
                    HStack {
                        Text("Temp Directory:")
                            .frame(width: 120, alignment: .leading)
                        TextField("/tmp", text: $appState.advancedTempDir)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") {
                            browseForTempDir()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Apply") {
                            applyTempDir()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("Custom temporary directory for extraction (restart required)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 124)
                    
                    Divider()
                    
                    HStack {
                        Text("Max Concurrent Operations:")
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $appState.advancedMaxConcurrent) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("4").tag(4)
                            Text("8").tag(8)
                            Text("16").tag(16)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                    
                    Text("Maximum number of parallel operations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 124)
                }
                .padding()
            } label: {
                Text("Performance Settings")
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Reset All Settings") {
                        resetAdvancedSettings()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    
                    Button("Clear All Cache") {
                        clearCache()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Open App Support Directory") {
                        openAppSupportDirectory()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } label: {
                Text("Danger Zone")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func browseForTool(_ tool: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.executable]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if tool == "7zz" {
                    appState.customToolPath7zz = url.path
                } else {
                    appState.customToolPathRar = url.path
                }
                appState.addDevLog("Custom \(tool) path set to \(url.path)", type: .info)
            }
        }
    }
    
    private func browseForTempDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.advancedTempDir = url.path
                appState.addDevLog("Temp directory set to \(url.path)", type: .info)
            }
        }
    }
    
    private func exportLogs() {
        let logText = appState.devLogs.map { "[\($0.formattedDate)] \($0.message)" }.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "debug_logs.txt"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? logText.write(to: url, atomically: true, encoding: .utf8)
                appState.addDevLog("Logs exported", type: .success)
            }
        }
    }
    
    private func openConsole() {
        let script = """
        tell application "Console"
            activate
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
    
    private func testToolPaths() {
        let fileManager = FileManager.default
        let sevenzzExists = fileManager.fileExists(atPath: appState.customToolPath7zz)
        let rarExists = fileManager.fileExists(atPath: appState.customToolPathRar)
        
        appState.addDevLog("Tool path test: 7zz=\(sevenzzExists ? "found" : "not found"), RAR=\(rarExists ? "found" : "not found")", type: .info)
    }
    
    private func applyMemoryLimit() {
        let limit = appState.advancedMemoryLimit
        UserDefaults.standard.set(limit, forKey: "AdvancedMemoryLimit")
        appState.addDevLog("Memory limit set to \(limit) MB", type: .info)
    }
    
    private func applyTempDir() {
        let dir = appState.advancedTempDir
        if !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        UserDefaults.standard.set(dir, forKey: "AdvancedTempDir")
        appState.addDevLog("Temp directory set to \(dir)", type: .info)
    }
    
    private func applySettings() {
        NotificationCenter.default.post(name: .developerSettingsChanged, object: nil)
    }
    
    private func resetAdvancedSettings() {
        appState.advancedMemoryLimit = 512
        appState.advancedTempDir = ""
        appState.advancedMaxConcurrent = 4
        appState.useCustomToolPaths = false
        appState.customToolPath7zz = ""
        appState.customToolPathRar = ""
        appState.debugLoggingEnabled = false
        appState.showHiddenFiles = false
        appState.experimentalParallelExtract = false
        appState.experimentalNewExtractor = false
        appState.experimentalFastZip = false
        appState.unstableAsyncWrite = false
        appState.unstableMemoryExtract = false
        appState.unstableSkipPermissions = false
        
        appState.saveDeveloperSettings()
        appState.addDevLog("All advanced settings reset", type: .warning)
        
        NotificationCenter.default.post(name: .developerSettingsReset, object: nil)
    }
    
    private func clearCache() {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        
        var cleared = 0
        do {
            let tempContents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for item in tempContents where item.lastPathComponent.hasPrefix("SwiftZip") {
                try? FileManager.default.removeItem(at: item)
                cleared += 1
            }
            
            let cacheContents = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            for item in cacheContents where item.lastPathComponent.hasPrefix("com.haoran.SwiftZipManager") {
                try? FileManager.default.removeItem(at: item)
                cleared += 1
            }
            
            appState.addDevLog("Cache cleared (\(cleared) items)", type: .success)
        } catch {
            appState.addDevLog("Failed to clear cache: \(error.localizedDescription)", type: .error)
        }
    }
    
    private func openAppSupportDirectory() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.haoran.SwiftZipManager")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(appDir)
    }
}
