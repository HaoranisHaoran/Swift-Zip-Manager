import SwiftUI
import UniformTypeIdentifiers

// MARK: - App State
class AppState: ObservableObject {
    @Published var showNewArchive = false
    @Published var showSettings = false
    @Published var showTools = false
    @Published var showCommandCopied = false
}

// MARK: - 通知名称扩展
extension Notification.Name {
    static let openArchiveNotification = Notification.Name("openArchiveNotification")
    static let showOpenPanelNotification = Notification.Name("showOpenPanelNotification")
    static let showHelpNotification = Notification.Name("showHelpNotification")
    static let languageChangedNotification = Notification.Name("languageChangedNotification")
}

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
            currentLanguage = "en"
        }
    }
}

// MARK: - 最近文件模型
struct RecentFile: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let path: String
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.path = url.path
    }
    
    enum CodingKeys: String, CodingKey {
        case id, url, name, path
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: RecentFile, rhs: RecentFile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Archive Entry Model
struct ArchiveEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let size: String
    let isFolder: Bool
    let isSystemFile: Bool
    
    init(name: String, size: String, isFolder: Bool = false) {
        self.name = name
        self.size = size
        self.isFolder = isFolder
        let lowerName = name.lowercased()
        self.isSystemFile = lowerName == ".ds_store" || name.hasPrefix("._") || name.contains("__MACOSX")
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ArchiveEntry, rhs: ArchiveEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 最近文件管理器
class RecentFilesManager: ObservableObject {
    @Published var recentFiles: [RecentFile] = []
    private let maxCount = 10
    private let key = "RecentFiles"
    
    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let files = try? JSONDecoder().decode([RecentFile].self, from: data) {
            recentFiles = files
        }
    }
    
    func add(_ url: URL) {
        recentFiles.removeAll { $0.url.path == url.path }
        recentFiles.insert(RecentFile(url: url), at: 0)
        if recentFiles.count > maxCount { recentFiles.removeLast() }
        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func remove(at indexSet: IndexSet) {
        recentFiles.remove(atOffsets: indexSet)
        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func clear() {
        recentFiles.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
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
    
    let formats = ["zip", "tar", "gz", "7z", "rar"]
    
    func getExtension(for format: String) -> String {
        ["zip": "zip", "tar": "tar", "gz": "tar.gz", "7z": "7z", "rar": "rar"][format] ?? "zip"
    }
    
    func findCommand(_ command: String) -> String? {
        let paths = ["/usr/local/bin/\(command)", "/opt/homebrew/bin/\(command)", "/usr/bin/\(command)"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    func listContents(_ url: URL, recentManager: RecentFilesManager? = nil) {
        file = url
        recentManager?.add(url)
        
        let ext = url.pathExtension.lowercased()
        let process = Process()
        var args: [String] = []
        
        switch ext {
        case "zip":
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
            args = [url.path]
        case "tar", "gz", "tgz":
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            args = ["tf", url.path]
        case "7z":
            guard let path = findCommand("7z") else {
                error = "Install p7zip: brew install p7zip"
                showAlert = true
                return
            }
            process.executableURL = URL(fileURLWithPath: path)
            args = ["l", url.path]
        case "rar":
            if let path = findCommand("unar") {
                process.executableURL = URL(fileURLWithPath: path)
                args = ["-t", url.path]
            } else if let path = findCommand("unrar") {
                process.executableURL = URL(fileURLWithPath: path)
                args = ["lb", url.path]
            } else {
                error = "Install unar: brew install unar"
                showAlert = true
                return
            }
        default:
            error = "Unsupported format"
            showAlert = true
            return
        }
        
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            
            var list: [ArchiveEntry] = []
            for line in output.split(separator: "\n") {
                let name = line.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && !name.hasPrefix("Archive:") {
                    let isFolder = name.hasSuffix("/")
                    list.append(ArchiveEntry(name: name, size: "--", isFolder: isFolder))
                }
            }
            entries = list.filter { !$0.isSystemFile }
            selectedIDs.removeAll()
        } catch {
            self.error = error.localizedDescription
            showAlert = true
        }
    }
    
    func extract(to destination: URL) {
        guard let source = file else { return }
        let target = destination.appendingPathComponent(source.deletingPathExtension().lastPathComponent)
        let ext = source.pathExtension.lowercased()
        
        isProcessing = true
        progress = 0
        
        DispatchQueue.global().async {
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                
                let process = Process()
                var args: [String] = []
                
                switch ext {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    args = ["-o", source.path, "-d", target.path]
                    
                case "tar", "gz", "tgz":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    args = ["-xf", source.path, "-C", target.path]
                    
                case "7z":
                    guard let path = self.findCommand("7z") else {
                        throw NSError(domain: "", code: -1)
                    }
                    process.executableURL = URL(fileURLWithPath: path)
                    args = ["x", source.path, "-o" + target.path, "-y"]
                    
                case "rar":
                    if let path = self.findCommand("unar") {
                        process.executableURL = URL(fileURLWithPath: path)
                        args = ["-o", target.path, source.path]
                    } else if let path = self.findCommand("unrar") {
                        process.executableURL = URL(fileURLWithPath: path)
                        args = ["x", source.path, target.path]
                    } else {
                        throw NSError(domain: "", code: -1)
                    }
                    
                default:
                    throw NSError(domain: "", code: -1)
                }
                
                process.arguments = args
                let errorPipe = Pipe()
                process.standardError = errorPipe
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                
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
    
    func create(files: [URL], format: String, name: String, destination: URL) {
        if format == "rar" && findCommand("rar") == nil {
            error = "Install rar: brew install rar"
            showAlert = true
            return
        }
        if format == "7z" && findCommand("7z") == nil {
            error = "Install p7zip: brew install p7zip"
            showAlert = true
            return
        }
        
        isProcessing = true
        
        DispatchQueue.global().async {
            do {
                let ext = self.getExtension(for: format)
                let fileName = name.hasSuffix(".\(ext)") ? name : "\(name).\(ext)"
                let targetPath = destination.appendingPathComponent(fileName).path
                
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                for file in files {
                    try FileManager.default.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                }
                
                let process = Process()
                var args: [String] = []
                
                switch format {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    args = ["-r", targetPath]
                    let fileList = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    args.append(contentsOf: fileList.map { $0.lastPathComponent })
                    process.currentDirectoryURL = tempDir
                case "tar":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    args = ["-cf", targetPath, "-C", tempDir.path, "."]
                case "gz":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    args = ["-czf", targetPath, "-C", tempDir.path, "."]
                case "7z":
                    process.executableURL = URL(fileURLWithPath: self.findCommand("7z")!)
                    args = ["a", targetPath, "-r", "."]
                    process.currentDirectoryURL = tempDir
                case "rar":
                    process.executableURL = URL(fileURLWithPath: self.findCommand("rar")!)
                    args = ["a", "-r", targetPath, "."]
                    process.currentDirectoryURL = tempDir
                default:
                    break
                }
                
                process.arguments = args
                try process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: tempDir)
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = "Archive created: \(fileName)"
                    self.showAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }
    
    func addFiles(_ files: [URL]) {
        guard let archiveURL = file else { return }
        let format = archiveURL.pathExtension.lowercased()
        isProcessing = true
        
        DispatchQueue.global().async {
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                for file in files {
                    try FileManager.default.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                }
                
                let process = Process()
                var args: [String] = []
                
                switch format {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    args = ["-r", archiveURL.path]
                    let fileList = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    args.append(contentsOf: fileList.map { $0.lastPathComponent })
                    process.currentDirectoryURL = tempDir
                case "7z":
                    guard let path = self.findCommand("7z") else { throw NSError() }
                    process.executableURL = URL(fileURLWithPath: path)
                    args = ["a", archiveURL.path, "-r", "."]
                    process.currentDirectoryURL = tempDir
                case "rar":
                    guard let path = self.findCommand("rar") else { throw NSError() }
                    process.executableURL = URL(fileURLWithPath: path)
                    args = ["a", archiveURL.path, "-r", "."]
                    process.currentDirectoryURL = tempDir
                default:
                    break
                }
                
                process.arguments = args
                try process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: tempDir)
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.listContents(archiveURL)
                    self.error = "Files added"
                    self.showAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }
    
    func deleteFiles(_ names: [String]) {
        guard let archiveURL = file else { return }
        let format = archiveURL.pathExtension.lowercased()
        isProcessing = true
        
        DispatchQueue.global().async {
            do {
                let process = Process()
                var args: [String] = []
                
                switch format {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    args = ["-d", archiveURL.path]
                    args.append(contentsOf: names)
                case "7z":
                    guard let path = self.findCommand("7z") else { throw NSError() }
                    process.executableURL = URL(fileURLWithPath: path)
                    args = ["d", archiveURL.path]
                    args.append(contentsOf: names)
                case "rar":
                    guard let path = self.findCommand("rar") else { throw NSError() }
                    process.executableURL = URL(fileURLWithPath: path)
                    args = ["d", archiveURL.path]
                    args.append(contentsOf: names)
                default:
                    throw NSError()
                }
                
                process.arguments = args
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.listContents(archiveURL)
                    self.error = "Files deleted"
                    self.showAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }
}

// MARK: - 毛玻璃效果
struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
        )
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    func glassBackground() -> some View {
        self.modifier(GlassBackground())
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var manager = ArchiveManager()
    @StateObject private var recentManager = RecentFilesManager()
    @State private var isTargeted = false
    @State private var copyMessage = ""
    
    var body: some View {
        NavigationView {
            // 侧边栏
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 12) {
                    Button(action: { openArchive() }) {
                        Label("Open Archive", systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { appState.showNewArchive = true }) {
                        Label("New Archive", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                Divider().padding(.vertical, 8)
                
                Text("Recent Files").font(.headline).padding(.horizontal)
                
                if recentManager.recentFiles.isEmpty {
                    VStack {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 24)).foregroundColor(.secondary)
                        Text("No recent files").font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 20)
                } else {
                    List(recentManager.recentFiles, id: \.self) { file in
                        HStack {
                            Image(systemName: "doc.zipper").foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(file.name).lineLimit(1)
                                Text(file.path).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        .onTapGesture { manager.listContents(file.url, recentManager: recentManager) }
                        .contextMenu { Button("Remove") { recentManager.remove(at: [recentManager.recentFiles.firstIndex(of: file)!]) } }
                    }
                    .listStyle(.sidebar)
                }
                
                Spacer()
                Divider().padding(.vertical, 8)
                
                Button(action: { appState.showSettings = true }) {
                    Label("Settings", systemImage: "gear").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .frame(minWidth: 220, maxWidth: 280)
            .glassBackground()
            
            // 主内容
            VStack {
                if manager.file == nil {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.zipper").font(.system(size: 60)).foregroundColor(.blue.opacity(0.5))
                        Text("No Archive Opened").font(.title2).foregroundColor(.secondary)
                        Text("Open an archive or drag and drop here").font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isTargeted ? Color.blue : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                    )
                    .padding()
                    .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                        for provider in providers {
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                    DispatchQueue.main.async {
                                        self.manager.listContents(url, recentManager: self.recentManager)
                                    }
                                }
                            }
                        }
                        return true
                    }
                } else {
                    VStack(spacing: 0) {
                        if let info = manager.file {
                            HStack {
                                Image(systemName: "info.circle").foregroundColor(.blue)
                                Text(info.lastPathComponent).font(.headline).lineLimit(1)
                                Spacer()
                                Text("\(manager.entries.count) items").font(.caption)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                        }
                        Divider()
                        HStack {
                            Button("Extract") { selectFolder() }
                                .buttonStyle(.borderedProminent)
                                .disabled(manager.selectedIDs.isEmpty && !manager.entries.isEmpty)
                            if manager.isProcessing {
                                ProgressView(value: manager.progress).frame(width: 80)
                                Text("\(Int(manager.progress * 100))%").font(.caption)
                            }
                            Spacer()
                            Text("Drag files here to add").font(.caption).foregroundColor(.secondary)
                        }
                        .padding()
                        Divider()
                        List(selection: $manager.selectedIDs) {
                            ForEach(manager.entries) { entry in
                                HStack {
                                    Image(systemName: entry.isFolder ? "folder" : "doc")
                                        .foregroundColor(entry.isFolder ? .yellow : .blue)
                                    Text(entry.name)
                                    Spacer()
                                    if !entry.isFolder { Text(entry.size).font(.caption).foregroundColor(.secondary) }
                                }
                                .tag(entry.id)
                                .contextMenu {
                                    Button("Delete") { manager.deleteFiles([entry.name]) }
                                    Button("Extract") { selectFolderForExtraction(entry.name) }
                                }
                            }
                        }
                        .listStyle(.inset)
                    }
                    .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                        if manager.file != nil {
                            var urls: [URL] = []
                            let group = DispatchGroup()
                            for provider in providers {
                                group.enter()
                                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                        urls.append(url)
                                    }
                                    group.leave()
                                }
                            }
                            group.notify(queue: .main) {
                                if !urls.isEmpty {
                                    self.manager.addFiles(urls)
                                }
                            }
                            return true
                        }
                        return false
                    }
                }
            }
        }
        .alert(manager.error ?? "Done", isPresented: $manager.showAlert) {
            Button("OK") { }
        }
        .alert("Copied", isPresented: $appState.showCommandCopied) {
            Button("OK") { }
        } message: {
            Text(copyMessage)
        }
        .sheet(isPresented: $appState.showNewArchive) {
            NewArchiveView(manager: manager)
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView(appState: appState, copyMessage: $copyMessage, languageManager: languageManager)
        }
        .sheet(isPresented: $appState.showTools) {
            ToolsView(appState: appState, copyMessage: $copyMessage)
        }
    }
    
    // MARK: - Open Archive
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
                manager.listContents(url, recentManager: recentManager)
            }
        }
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                manager.extract(to: url)
            }
        }
    }
    
    func selectFolderForExtraction(_ name: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                manager.error = "Coming soon"
                manager.showAlert = true
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    var appState: AppState
    @Binding var copyMessage: String
    @ObservedObject var languageManager: LanguageManager
    @Environment(\.dismiss) var dismiss
    @State private var tempLanguage: String
    @State private var showRestartAlert = false
    
    let languages = ["en": "English", "zh-Hans": "简体中文", "zh-Hant": "繁體中文", "es": "Español", "fr": "Français", "de": "Deutsch", "ja": "日本語", "ko": "한국어", "ru": "Русский", "it": "Italiano", "pt": "Português", "nl": "Nederlands", "sv": "Svenska", "da": "Dansk"]
    let githubURL = "https://github.com/HaoranisHaoran/Swift-Zip-Manager"
    
    init(appState: AppState, copyMessage: Binding<String>, languageManager: LanguageManager) {
        self.appState = appState
        self._copyMessage = copyMessage
        self.languageManager = languageManager
        self._tempLanguage = State(initialValue: languageManager.currentLanguage)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings").font(.title2).bold().padding(.top)
            
            Form {
                Section("Language") {
                    Picker("Display Language", selection: $tempLanguage) {
                        ForEach(languages.keys.sorted(), id: \.self) { code in
                            Text(languages[code] ?? code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Tools") {
                    Button("Install Required Tools") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appState.showTools = true
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Section("About") {
                    HStack {
                        Image(systemName: "archivebox").foregroundColor(.blue)
                        Text("Swift Zip Manager").font(.headline)
                    }
                    Text("Version 1.0.0 Beta 1").font(.caption).foregroundColor(.secondary)
                    Divider()
                    HStack {
                        Image(systemName: "link.circle.fill").font(.caption).foregroundColor(.blue)
                        Text(githubURL).font(.caption).foregroundColor(.blue).underline().onTapGesture {
                            if let url = URL(string: githubURL) { NSWorkspace.shared.open(url) }
                        }
                    }
                    HStack {
                        Image(systemName: "doc.on.clipboard").font(.caption).foregroundColor(.green)
                        Text("Copy URL").font(.caption).foregroundColor(.green).onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(githubURL, forType: .string)
                            copyMessage = "URL copied"
                            appState.showCommandCopied = true
                        }
                    }
                }
            }
            .frame(height: 350).padding()
            
            HStack {
                Button("Apply") {
                    if tempLanguage != languageManager.currentLanguage {
                        languageManager.currentLanguage = tempLanguage
                        showRestartAlert = true
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }.padding(.bottom)
        }
        .frame(width: 450, height: 450).padding()
        .alert("Language Changed", isPresented: $showRestartAlert) {
            Button("Restart Now") { exit(0) }
            Button("Later", role: .cancel) { }
        } message: {
            Text("The app needs to restart to apply the new language.")
        }
    }
}

// MARK: - Tools View
struct ToolsView: View {
    var appState: AppState
    @Binding var copyMessage: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Install Required Tools").font(.title2).bold().padding(.top)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    // 1. Homebrew
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Homebrew").font(.headline).foregroundColor(.blue)
                        Text("Package manager for macOS").font(.caption).foregroundColor(.secondary)
                        HStack {
                            Text("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                                .font(.caption).padding(8).background(Color.gray.opacity(0.1)).cornerRadius(4)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", forType: .string)
                                copyMessage = "Homebrew command copied"
                                appState.showCommandCopied = true
                            }.buttonStyle(.bordered)
                        }
                    }
                    Divider()
                    
                    // 2. 7z Support
                    VStack(alignment: .leading, spacing: 10) {
                        Text("2. 7z Support").font(.headline).foregroundColor(.blue)
                        Text("p7zip - brew install p7zip").font(.caption).foregroundColor(.secondary)
                        HStack {
                            Text("brew install p7zip").font(.caption).padding(8).background(Color.gray.opacity(0.1)).cornerRadius(4)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install p7zip", forType: .string)
                                copyMessage = "7z command copied"
                                appState.showCommandCopied = true
                            }.buttonStyle(.bordered)
                        }
                    }
                    Divider()
                    
                    // 3. RAR Support
                    VStack(alignment: .leading, spacing: 10) {
                        Text("3. RAR Support").font(.headline).foregroundColor(.blue)
                        Text("unar + rar - brew install unar rar").font(.caption).foregroundColor(.secondary)
                        HStack {
                            Text("brew install unar rar").font(.caption).padding(8).background(Color.gray.opacity(0.1)).cornerRadius(4)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install unar rar", forType: .string)
                                copyMessage = "RAR command copied"
                                appState.showCommandCopied = true
                            }.buttonStyle(.bordered)
                        }
                    }
                    Divider()
                    
                    // 4. Verify
                    VStack(alignment: .leading, spacing: 10) {
                        Text("4. Verify").font(.headline).foregroundColor(.blue)
                        HStack {
                            Text("which 7z unar rar").font(.caption).padding(8).background(Color.gray.opacity(0.1)).cornerRadius(4)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("which 7z unar rar", forType: .string)
                                copyMessage = "Verify command copied"
                                appState.showCommandCopied = true
                            }.buttonStyle(.bordered)
                        }
                    }
                    Text("Note: Restart the app after installing").font(.caption).foregroundColor(.red)
                }.padding()
            }
            
            Button("Close") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).padding(.bottom)
        }
        .frame(width: 550, height: 600).padding()
    }
}

// MARK: - New Archive View
struct NewArchiveView: View {
    @ObservedObject var manager: ArchiveManager
    @State private var files: [URL] = []
    @State private var format = "zip"
    @State private var name = ""
    @State private var destination: URL?
    @State private var showPicker = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("New Archive").font(.title2).padding()
            
            List(files, id: \.self) { file in
                HStack { Text(file.lastPathComponent); Spacer(); Text(size(file)).font(.caption) }
            }.frame(height: 150)
            
            HStack {
                Button("Add Files") { showPicker = true }
                Button("Add Folder") { showPicker = true }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Name:").font(.caption).frame(width: 50, alignment: .trailing)
                    TextField("Archive name", text: $name).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 200)
                    Text(".\(manager.getExtension(for: format))").font(.caption).foregroundColor(.secondary)
                }
                HStack {
                    Text("Format:").font(.caption).frame(width: 50, alignment: .trailing)
                    Picker("", selection: $format) {
                        ForEach(manager.formats, id: \.self) { Text($0.uppercased()) }
                    }.pickerStyle(.segmented).frame(width: 300)
                    Spacer()
                }
                HStack {
                    Text("Save to:").font(.caption).frame(width: 50, alignment: .trailing)
                    Text(destination?.lastPathComponent ?? "Not selected").font(.caption).frame(width: 200, alignment: .leading)
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.begin { if $0 == .OK { destination = panel.url } }
                    }.buttonStyle(.bordered)
                }
            }.padding()
            
            HStack {
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard let dest = destination else { return }
                    let archiveName = name.isEmpty ? "Archive" : name
                    manager.create(files: files, format: format, name: archiveName, destination: dest)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(files.isEmpty || destination == nil)
            }
        }
        .frame(width: 600, height: 450)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var validUrls: [URL] = []
                for url in urls {
                    if FileManager.default.isReadableFile(atPath: url.path) {
                        validUrls.append(url)
                    } else {
                        DispatchQueue.main.async {
                            manager.error = "Cannot access: \(url.lastPathComponent)"
                            manager.showAlert = true
                        }
                    }
                }
                files.append(contentsOf: validUrls)
            case .failure(let error):
                DispatchQueue.main.async {
                    manager.error = error.localizedDescription
                    manager.showAlert = true
                }
            }
        }
    }
    
    func size(_ url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Help View
struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    
    let items = [
        ("📦 Open Archive", ["Click 'Open Archive' or press ⌘O to open", "Supported: ZIP, TAR, GZ, 7Z, RAR"]),
        ("🆕 New Archive", ["Click 'New Archive' or press ⌘W to create", "Add files, choose format, select destination"]),
        ("📤 Extract", ["Select files, click 'Extract'", "Supports all formats"]),
        ("✏️ Modify", ["Drag files to add", "Right-click to delete"]),
        ("⚙️ Settings", ["Change language", "Install tools"]),
        ("⌨️ Shortcuts", ["⌘O - Open", "⌘W - New", "⌘? - Help"])
    ]
    
    var filtered: [(String, [String])] {
        if search.isEmpty { return items }
        return items.filter { $0.0.localizedCaseInsensitiveContains(search) || $0.1.joined().localizedCaseInsensitiveContains(search) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Help")
                .font(.largeTitle)
                .bold()
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 15)
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button(action: { search = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 15)
            
            Divider()
                .padding(.bottom, 15)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(filtered, id: \.0) { title, content in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.headline)
                                .padding(.leading, 12)
                            
                            ForEach(content, id: \.self) { line in
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 28)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            
            Divider()
                .padding(.top, 10)
            
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.vertical, 12)
                .padding(.trailing, 16)
            }
        }
        .frame(width: 550, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
