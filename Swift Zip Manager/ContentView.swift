import SwiftUI
import UniformTypeIdentifiers

// MARK: - 语言管理器
class LanguageManager: ObservableObject {
    @Published var currentLanguage: String

    init() {
        if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = languages.first {
            self.currentLanguage = first
        } else {
            self.currentLanguage = "en"
        }
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}

// MARK: - App State
class AppState: ObservableObject {
    enum ActiveSheet: Identifiable {
        case newArchive, settings, tools, help
        
        var id: Int { hashValue }
    }
    
    @Published var activeSheet: ActiveSheet?
    @Published var showCommandCopied = false
}

// MARK: - Archive Entry Model
struct ArchiveEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let size: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ArchiveEntry, rhs: ArchiveEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Archive Manager
class ArchiveManager: ObservableObject {
    @Published var file: URL?
    @Published var entries: [ArchiveEntry] = []
    @Published var selectedIDs = Set<UUID>()
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var error: String?
    @Published var showAlert = false

    // 压缩格式列表（含 7z 和 rar）
    let formats = ["zip", "tar", "gz", "7z", "rar"]

    // 获取格式对应的扩展名
    func getExtension(for format: String) -> String {
        switch format.lowercased() {
        case "zip": return "zip"
        case "tar": return "tar"
        case "gz": return "tar.gz"
        case "7z": return "7z"
        case "rar": return "rar"
        default: return "zip"
        }
    }

    // 增强的命令查找函数
    func findCommandPath(_ command: String) -> String? {
        let commonPaths = [
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/usr/sbin/\(command)",
            "/sbin/\(command)"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        } catch {
            print("which command failed: \(error)")
        }

        return nil
    }

    func checkCommand(_ command: String) -> Bool {
        return findCommandPath(command) != nil
    }

    func listArchiveContents(_ url: URL) {
        file = url
        let ext = url.pathExtension.lowercased()

        let process = Process()
        var arguments: [String] = []
        var executablePath: String?

        switch ext {
        case "zip":
            executablePath = "/usr/bin/zipinfo"
            arguments = [url.path]

        case "tar", "gz", "tgz":
            executablePath = "/usr/bin/tar"
            arguments = ["tf", url.path]

        case "7z":
            if let sevenZipPath = findCommandPath("7z") {
                executablePath = sevenZipPath
                arguments = ["l", url.path]
            } else {
                DispatchQueue.main.async {
                    self.error = "Please install p7zip to list 7z contents: brew install p7zip"
                    self.showAlert = true
                }
                return
            }

        case "rar":
            if let unrarPath = findCommandPath("unrar") {
                executablePath = unrarPath
                arguments = ["lb", url.path]
            } else if let lsarPath = findCommandPath("lsar") {
                executablePath = lsarPath
                arguments = [url.path]
            } else {
                DispatchQueue.main.async {
                    self.error = "Please install unrar or lsar to list RAR contents: brew install unar"
                    self.showAlert = true
                }
                return
            }

        default:
            DispatchQueue.main.async {
                self.error = "Unsupported format: \(ext)"
                self.showAlert = true
            }
            return
        }

        guard let execPath = executablePath else {
            DispatchQueue.main.async {
                self.error = "Could not find required command"
                self.showAlert = true
            }
            return
        }

        process.executableURL = URL(fileURLWithPath: execPath)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""

            var fileEntries: [ArchiveEntry] = []
            let lines = output.split(separator: "\n")

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("Archive:") && !trimmed.hasPrefix("Path =") {
                    var fileName = trimmed
                    if ext == "7z" || ext == "rar" {
                        let components = trimmed.split(separator: " ", maxSplits: 5)
                        if components.count >= 6 {
                            fileName = String(components[5])
                        }
                    }
                    fileEntries.append(ArchiveEntry(
                        name: fileName,
                        path: fileName,
                        size: "--"
                    ))
                }
            }

            DispatchQueue.main.async {
                self.entries = fileEntries
                self.selectedIDs.removeAll()
                if fileEntries.isEmpty {
                    self.error = "No files found in archive"
                    self.showAlert = true
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to read archive: \(error.localizedDescription)"
                self.showAlert = true
            }
        }
    }

    func extractSelected(to destination: URL) {
        let list = selectedIDs.isEmpty ? entries : entries.filter { selectedIDs.contains($0.id) }
        guard !list.isEmpty else {
            DispatchQueue.main.async {
                self.error = "No files selected to extract"
                self.showAlert = true
            }
            return
        }

        guard let source = file else {
            DispatchQueue.main.async {
                self.error = "No archive file loaded"
                self.showAlert = true
            }
            return
        }

        let target = destination.appendingPathComponent(source.deletingPathExtension().lastPathComponent)
        let ext = source.pathExtension.lowercased()

        isProcessing = true
        progress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

                let process = Process()
                var arguments: [String] = []
                var executablePath: String?

                switch ext {
                case "zip":
                    executablePath = "/usr/bin/unzip"
                    arguments = ["-o", source.path, "-d", target.path]

                case "tar":
                    executablePath = "/usr/bin/tar"
                    arguments = ["-xf", source.path, "-C", target.path]

                case "gz", "tgz":
                    executablePath = "/usr/bin/tar"
                    arguments = ["-xzf", source.path, "-C", target.path]

                case "7z":
                    if let sevenZipPath = self.findCommandPath("7z") {
                        executablePath = sevenZipPath
                        arguments = ["x", source.path, "-o" + target.path, "-y"]
                    } else {
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            self.error = "7z command not found. Please install p7zip: brew install p7zip"
                            self.showAlert = true
                        }
                        return
                    }

                case "rar":
                    if let unarPath = self.findCommandPath("unar") {
                        executablePath = unarPath
                        arguments = ["-o", target.path, source.path]
                    } else if let unrarPath = self.findCommandPath("unrar") {
                        executablePath = unrarPath
                        arguments = ["x", source.path, target.path]
                    } else {
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            self.error = "unar/unrar command not found. Please install: brew install unar"
                            self.showAlert = true
                        }
                        return
                    }

                default:
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Unsupported format: \(ext)"
                        self.showAlert = true
                    }
                    return
                }

                guard let execPath = executablePath else {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Could not find required command"
                        self.showAlert = true
                    }
                    return
                }

                process.executableURL = URL(fileURLWithPath: execPath)
                process.arguments = arguments

                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = environment

                let errorPipe = Pipe()
                process.standardError = errorPipe

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.progress = 1.0
                        self.error = "Extraction complete"
                        self.showAlert = true
                    }
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Extraction failed: \(errorMsg)"
                        self.showAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = "Extraction failed: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }

    func createArchive(files: [URL], format: String, archiveName: String, destination: URL) {
        if format == "rar" && !checkCommand("rar") {
            DispatchQueue.main.async {
                self.error = "rar command not found. Please install rar: brew install rar"
                self.showAlert = true
            }
            return
        }
        if format == "7z" && !checkCommand("7z") {
            DispatchQueue.main.async {
                self.error = "7z command not found. Please install p7zip: brew install p7zip"
                self.showAlert = true
            }
            return
        }

        isProcessing = true
        progress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let process = Process()
                var arguments: [String] = []
                var executablePath: String?
                let ext = self.getExtension(for: format)
                let fileName = archiveName.hasSuffix(".\(ext)") ? archiveName : "\(archiveName).\(ext)"
                let targetPath = destination.appendingPathComponent(fileName).path

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                for file in files {
                    let destPath = tempDir.appendingPathComponent(file.lastPathComponent)
                    try FileManager.default.copyItem(at: file, to: destPath)
                }

                switch format.lowercased() {
                case "zip":
                    executablePath = "/usr/bin/zip"
                    arguments = ["-r", targetPath]
                    let fileList = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    for file in fileList {
                        arguments.append(file.lastPathComponent)
                    }
                    process.currentDirectoryURL = tempDir

                case "tar":
                    executablePath = "/usr/bin/tar"
                    arguments = ["-cf", targetPath, "-C", tempDir.path, "."]

                case "gz":
                    executablePath = "/usr/bin/tar"
                    arguments = ["-czf", targetPath, "-C", tempDir.path, "."]

                case "7z":
                    guard let sevenZipPath = self.findCommandPath("7z") else {
                        throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "7z command not found"])
                    }
                    executablePath = sevenZipPath
                    arguments = ["a", targetPath, "-r", "."]
                    process.currentDirectoryURL = tempDir

                case "rar":
                    guard let rarPath = self.findCommandPath("rar") else {
                        throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "rar command not found"])
                    }
                    executablePath = rarPath
                    arguments = ["a", "-r", targetPath, "."]
                    process.currentDirectoryURL = tempDir

                default:
                    executablePath = "/usr/bin/zip"
                    arguments = ["-r", targetPath]
                    let fileList = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    for file in fileList {
                        arguments.append(file.lastPathComponent)
                    }
                    process.currentDirectoryURL = tempDir
                }

                guard let execPath = executablePath else {
                    throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find required command"])
                }

                process.executableURL = URL(fileURLWithPath: execPath)
                process.arguments = arguments

                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = environment

                let errorPipe = Pipe()
                process.standardError = errorPipe

                try process.run()
                process.waitUntilExit()

                try? FileManager.default.removeItem(at: tempDir)

                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.progress = 1.0
                        self.error = "Archive created: \(fileName)"
                        self.showAlert = true
                    }
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Creation failed: \(errorMsg)"
                        self.showAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = "Creation failed: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }

    func format(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var languageManager: LanguageManager
    @StateObject private var manager = ArchiveManager()
    @State private var selectedLanguage = "en"
    @State private var showRestartAlert = false
    @State private var copyMessage = ""

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

    var body: some View {
        VStack {
            if manager.file == nil {
                // Empty state
                VStack(spacing: 20) {
                    Button("Open Archive") {
                        openArchive()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("New Archive") {
                        appState.activeSheet = .newArchive
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Main view
                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                        Button("Open") {
                            openArchive()
                        }
                        .buttonStyle(.bordered)

                        Button("New") {
                            appState.activeSheet = .newArchive
                        }
                        .buttonStyle(.bordered)

                        Button("Extract") {
                            selectFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.entries.isEmpty)

                        if manager.isProcessing {
                            ProgressView(value: manager.progress)
                                .frame(width: 80)
                            Text("\(Int(manager.progress * 100))%")
                                .font(.caption)
                        }

                        Spacer()
                    }
                    .padding()

                    Divider()

                    // File list with selection
                    List(selection: $manager.selectedIDs) {
                        ForEach(manager.entries) { entry in
                            HStack {
                                Image(systemName: "doc")
                                Text(entry.name)
                                Spacer()
                                Text(entry.size)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(entry.id)
                        }
                    }
                    .listStyle(.inset)
                }
            }

            // 底部按钮
            HStack {
                Spacer()
                Button("Settings") {
                    appState.activeSheet = .settings
                }
                .buttonStyle(.bordered)

                Button("Help") {
                    appState.activeSheet = .help
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.bottom, 10)
            .padding(.top, 5)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .alert(manager.error ?? "Done", isPresented: $manager.showAlert) {
            Button("OK") { }
        }
        .alert("Command Copied", isPresented: $appState.showCommandCopied) {
            Button("OK") { }
        } message: {
            Text(copyMessage)
        }
        .alert("Language Changed", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                exit(0)
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("The app needs to restart to apply the new language.")
        }
        .sheet(item: $appState.activeSheet) { sheet in
            switch sheet {
            case .newArchive:
                NewArchiveView(manager: manager)
            case .settings:
                SettingsView(
                    selectedLanguage: $selectedLanguage,
                    languages: languages,
                    showRestartAlert: $showRestartAlert,
                    appState: appState,
                    copyMessage: $copyMessage
                )
                .environmentObject(languageManager)
            case .tools:
                ToolsView(appState: appState, copyMessage: $copyMessage)
            case .help:
                HelpView()
            }
        }
    }

    func openArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "zip") ?? .zip,
            UTType(filenameExtension: "tar") ?? .archive,
            UTType(filenameExtension: "gz") ?? .archive,
            UTType(filenameExtension: "tgz") ?? .archive,
            UTType(filenameExtension: "7z") ?? .archive,
            UTType(filenameExtension: "rar") ?? .archive
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select an archive file"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                manager.listArchiveContents(url)
            }
        }
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Select destination folder"
        panel.prompt = "Extract Here"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                manager.extractSelected(to: url)
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Binding var selectedLanguage: String
    let languages: [String: String]
    @Binding var showRestartAlert: Bool
    var appState: AppState
    @Binding var copyMessage: String
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) var dismiss
    @State private var tempLanguage: String

    init(selectedLanguage: Binding<String>, languages: [String: String], showRestartAlert: Binding<Bool>, appState: AppState, copyMessage: Binding<String>) {
        self._selectedLanguage = selectedLanguage
        self.languages = languages
        self._showRestartAlert = showRestartAlert
        self.appState = appState
        self._copyMessage = copyMessage
        self._tempLanguage = State(initialValue: selectedLanguage.wrappedValue)
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
                        ForEach(Array(languages.keys.sorted()), id: \.self) { code in
                            HStack {
                                Text(languages[code] ?? code)
                                Text("(\(code))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: tempLanguage) { newLanguage in
                        if newLanguage != languageManager.currentLanguage {
                            languageManager.currentLanguage = newLanguage
                            selectedLanguage = newLanguage
                            showRestartAlert = true
                        }
                    }
                }

                Section("Tools") {
                    Button("Install Required Tools") {
                        appState.activeSheet = .tools
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(height: 200)
            .padding()

            HStack {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom)
        }
        .frame(width: 400, height: 350)
        .padding()
    }
}

// MARK: - Tools View
struct ToolsView: View {
    var appState: AppState
    @Binding var copyMessage: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Install Required Tools")
                .font(.title2)
                .bold()
                .padding(.top)

            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    // Homebrew
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Homebrew")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text("Homebrew is a package manager for macOS. You need it to install 7z and RAR.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                                .lineLimit(2)

                            Button("Copy") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", forType: .string)
                                copyMessage = "Homebrew install command copied"
                                appState.showCommandCopied = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    // 7z
                    VStack(alignment: .leading, spacing: 10) {
                        Text("2. 7z Support")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text("p7zip provides 7z compression and extraction support.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("brew install p7zip")
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)

                            Button("Copy") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("brew install p7zip", forType: .string)
                                copyMessage = "7z install command copied"
                                appState.showCommandCopied = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    // RAR Extraction
                    VStack(alignment: .leading, spacing: 10) {
                        Text("3. RAR Extraction")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text("unar provides RAR extraction support.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("brew install unar")
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)

                            Button("Copy") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("brew install unar", forType: .string)
                                copyMessage = "unar install command copied"
                                appState.showCommandCopied = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    // RAR Compression
                    VStack(alignment: .leading, spacing: 10) {
                        Text("4. RAR Compression")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text("rar provides RAR compression support.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("brew install rar")
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)

                            Button("Copy") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("brew install rar", forType: .string)
                                copyMessage = "rar install command copied"
                                appState.showCommandCopied = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    // Verification
                    VStack(alignment: .leading, spacing: 10) {
                        Text("5. Verify Installation")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text("Run these commands to verify the tools are installed correctly:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("which 7z unar rar")
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)

                            Button("Copy") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("which 7z unar rar", forType: .string)
                                copyMessage = "Verification command copied"
                                appState.showCommandCopied = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text("Note: You need to restart the app after installing tools")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 10)
                }
                .padding()
            }

            HStack {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom)
        }
        .frame(width: 550, height: 600)
        .padding()
    }
}

// MARK: - New Archive View
struct NewArchiveView: View {
    @ObservedObject var manager: ArchiveManager
    @State private var files: [URL] = []
    @State private var format = "zip"
    @State private var archiveName = ""
    @State private var destination: URL?
    @State private var showPicker = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("New Archive").font(.title2).padding()

            List(files, id: \.self) { file in
                HStack {
                    Text(file.lastPathComponent)
                    Spacer()
                    Text(size(file)).font(.caption)
                }
            }
            .frame(height: 150)

            HStack {
                Button("Add Files") { showPicker = true }
                Button("Add Folder") { showPicker = true }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Name:")
                        .font(.caption)
                        .frame(width: 50, alignment: .trailing)

                    TextField("Archive name", text: $archiveName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)

                    Text(".\(manager.getExtension(for: format))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Format:")
                        .font(.caption)
                        .frame(width: 50, alignment: .trailing)

                    Picker("", selection: $format) {
                        ForEach(manager.formats, id: \.self) { format in
                            Text(format.uppercased())
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)

                    Spacer()
                }

                HStack {
                    Text("Save to:")
                        .font(.caption)
                        .frame(width: 50, alignment: .trailing)

                    Text(destination?.lastPathComponent ?? "Not selected")
                        .font(.caption)
                        .lineLimit(1)
                        .frame(width: 200, alignment: .leading)

                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.begin { response in
                            if response == .OK {
                                destination = panel.url
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()

            HStack {
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard let dest = destination else { return }
                    let name = archiveName.isEmpty ? "Archive" : archiveName
                    manager.createArchive(files: files, format: format, archiveName: name, destination: dest)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(files.isEmpty || destination == nil)
            }
        }
        .frame(width: 600, height: 450)
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.data, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                files.append(contentsOf: urls)
            case .failure:
                break
            }
        }
    }

    func size(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int64 ?? 0
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - Help Components
struct HelpSection: View {
    let title: String
    let content: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .padding(.top, 5)

            ForEach(content, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading)
            }
        }
    }
}

// MARK: - Help View
struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Help")
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HelpSection(title: "📦 Open Archive", content: [
                        "Click 'Open Archive' or press ⌘O to open and view archive contents",
                        "Supported formats: ZIP, TAR, GZ, 7Z, RAR"
                    ])

                    HelpSection(title: "🆕 New Archive", content: [
                        "Click 'New Archive' or press ⌘W to create a new archive",
                        "• Add files/folders to compress",
                        "• Enter custom archive name",
                        "• Choose format: ZIP, TAR, GZ, 7Z, RAR",
                        "• Select destination folder"
                    ])

                    HelpSection(title: "📤 Extract", content: [
                        "Select files in the list, then click 'Extract' to extract them",
                        "• Supports: ZIP, TAR, GZ, 7Z, RAR"
                    ])

                    HelpSection(title: "⚙️ Settings", content: [
                        "• Change language",
                        "• Install required tools (7z, RAR) via Tools button"
                    ])

                    HelpSection(title: "🌐 Language", content: [
                        "After changing language, the app needs to restart to apply"
                    ])
                }
                .padding(.horizontal, 5)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(width: 500, height: 550)
    }
}
