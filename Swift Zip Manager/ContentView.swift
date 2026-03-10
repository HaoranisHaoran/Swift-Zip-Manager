import SwiftUI
import UniformTypeIdentifiers

// MARK: - 语言管理器
class LanguageManager: ObservableObject {
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }
    
    init() {
        if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = languages.first {
            self.currentLanguage = first
        } else {
            self.currentLanguage = "en"
        }
    }
}

// MARK: - 最近文件模型
struct RecentFile: Identifiable, Codable {
    var id = UUID()
    let url: URL
    let lastOpened: Date
    let name: String
    let path: String
    
    init(url: URL) {
        self.url = url
        self.lastOpened = Date()
        self.name = url.lastPathComponent
        self.path = url.path
    }
}

// MARK: - App State
class AppState: ObservableObject {
    enum ActiveSheet: Identifiable {
        case newArchive, settings, tools
        
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
    let isFolder: Bool
    let modificationDate: Date?
    let isSystemFile: Bool
    
    init(name: String, path: String, size: String, isFolder: Bool = false, modificationDate: Date? = nil) {
        self.name = name
        self.path = path
        self.size = size
        self.isFolder = isFolder
        self.modificationDate = modificationDate
        
        // 检测系统文件
        let lowercasedName = name.lowercased()
        self.isSystemFile = lowercasedName == ".ds_store" ||
                           lowercasedName == "thumbs.db" ||
                           lowercasedName == "desktop.ini" ||
                           name.hasPrefix("._") ||
                           name.contains("__MACOSX")
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
    private let maxRecentFiles = 10
    private let userDefaultsKey = "RecentFiles"
    
    init() {
        loadRecentFiles()
    }
    
    func addRecentFile(url: URL) {
        // 移除已存在的相同文件
        recentFiles.removeAll { $0.url.path == url.path }
        
        // 添加新文件
        let newFile = RecentFile(url: url)
        recentFiles.insert(newFile, at: 0)
        
        // 限制数量
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        
        saveRecentFiles()
    }
    
    func removeRecentFile(at indexSet: IndexSet) {
        recentFiles.remove(atOffsets: indexSet)
        saveRecentFiles()
    }
    
    func clearAll() {
        recentFiles.removeAll()
        saveRecentFiles()
    }
    
    private func loadRecentFiles() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let files = try? JSONDecoder().decode([RecentFile].self, from: data) else {
            return
        }
        recentFiles = files
    }
    
    private func saveRecentFiles() {
        guard let data = try? JSONEncoder().encode(recentFiles) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
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
    @Published var archiveInfo: ArchiveInfo?
    @Published var isDragging = false
    
    struct ArchiveInfo {
        let path: String
        let size: Int64
        let itemCount: Int
        let folderCount: Int
        let fileCount: Int
        let systemFileCount: Int
        let created: Date?
        let modified: Date?
    }
    
    let formats = ["zip", "tar", "gz", "7z", "rar"]
    
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
        return nil
    }
    
    func checkCommand(_ command: String) -> Bool {
        return findCommandPath(command) != nil
    }
    
    func listArchiveContents(_ url: URL, recentFilesManager: RecentFilesManager? = nil) {
        file = url
        let ext = url.pathExtension.lowercased()
        
        // 添加到最近文件
        recentFilesManager?.addRecentFile(url: url)
        
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
            } else {
                DispatchQueue.main.async {
                    self.error = "Please install unrar to list RAR contents: brew install unar"
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
        process.standardOutput = outputPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            var fileEntries: [ArchiveEntry] = []
            var folderCount = 0
            var fileCount = 0
            var systemFileCount = 0
            
            let lines = output.split(separator: "\n")
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("Archive:") {
                    // 判断是否为文件夹
                    let isFolder = trimmed.hasSuffix("/") || trimmed.hasSuffix("\\")
                    
                    let entry = ArchiveEntry(
                        name: trimmed,
                        path: trimmed,
                        size: "--",
                        isFolder: isFolder,
                        modificationDate: nil
                    )
                    
                    if entry.isSystemFile {
                        systemFileCount += 1
                        // 可以选择是否显示系统文件，这里我们显示但标记为系统文件
                    }
                    
                    if isFolder {
                        folderCount += 1
                    } else {
                        fileCount += 1
                    }
                    
                    fileEntries.append(entry)
                }
            }
            
            // 获取文件信息
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                let fileSize = attributes[.size] as? Int64 ?? 0
                let created = attributes[.creationDate] as? Date
                let modified = attributes[.modificationDate] as? Date
                
                self.archiveInfo = ArchiveInfo(
                    path: url.path,
                    size: fileSize,
                    itemCount: fileEntries.count,
                    folderCount: folderCount,
                    fileCount: fileCount,
                    systemFileCount: systemFileCount,
                    created: created,
                    modified: modified
                )
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
                    
                case "tar", "gz", "tgz":
                    executablePath = "/usr/bin/tar"
                    arguments = ["-xf", source.path, "-C", target.path]
                    
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
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Extraction failed"
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
                
                let process = Process()
                var arguments: [String] = []
                
                switch format.lowercased() {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    arguments = ["-r", targetPath]
                    let fileList = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    for file in fileList {
                        arguments.append(file.lastPathComponent)
                    }
                    process.currentDirectoryURL = tempDir
                    
                case "tar":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    arguments = ["-cf", targetPath, "-C", tempDir.path, "."]
                    
                case "gz":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    arguments = ["-czf", targetPath, "-C", tempDir.path, "."]
                    
                case "7z":
                    guard let sevenZipPath = self.findCommandPath("7z") else {
                        throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "7z command not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: sevenZipPath)
                    arguments = ["a", targetPath, "-r", "."]
                    process.currentDirectoryURL = tempDir
                    
                case "rar":
                    guard let rarPath = self.findCommandPath("rar") else {
                        throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "rar command not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: rarPath)
                    arguments = ["a", "-r", targetPath, "."]
                    process.currentDirectoryURL = tempDir
                    
                default:
                    break
                }
                
                process.arguments = arguments
                
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
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Creation failed"
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
    
    // 添加文件到现有归档（拖拽或右键菜单）
    func addFilesToArchive(files: [URL]) {
        guard let archiveURL = file else { return }
        let format = archiveURL.pathExtension.lowercased()
        
        isProcessing = true
        progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let process = Process()
                var arguments: [String] = []
                
                // 创建临时目录来准备文件
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // 复制要添加的文件到临时目录
                for file in files {
                    let destPath = tempDir.appendingPathComponent(file.lastPathComponent)
                    try FileManager.default.copyItem(at: file, to: destPath)
                }
                
                switch format.lowercased() {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    arguments = ["-r", archiveURL.path]
                    let fileList = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    for file in fileList {
                        arguments.append(file.lastPathComponent)
                    }
                    process.currentDirectoryURL = tempDir
                    
                case "7z":
                    guard let sevenZipPath = self.findCommandPath("7z") else {
                        throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "7z command not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: sevenZipPath)
                    arguments = ["a", archiveURL.path, "-r", "."]
                    process.currentDirectoryURL = tempDir
                    
                case "rar":
                    guard let rarPath = self.findCommandPath("rar") else {
                        throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "rar command not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: rarPath)
                    arguments = ["a", archiveURL.path, "-r", "."]
                    process.currentDirectoryURL = tempDir
                    
                default:
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Adding files to \(format) archives is not supported"
                        self.showAlert = true
                    }
                    return
                }
                
                process.arguments = arguments
                
                try process.run()
                process.waitUntilExit()
                
                try? FileManager.default.removeItem(at: tempDir)
                
                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.progress = 1.0
                        self.error = "Files added to archive successfully"
                        self.showAlert = true
                        // 重新加载归档内容
                        self.listArchiveContents(archiveURL)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Failed to add files"
                        self.showAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = "Failed to add files: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
    
    // 从归档中删除文件
    func removeFilesFromArchive(fileNames: [String]) {
        guard let archiveURL = file else { return }
        let format = archiveURL.pathExtension.lowercased()
        
        isProcessing = true
        progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let process = Process()
                var arguments: [String] = []
                
                switch format.lowercased() {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    arguments = ["-d", archiveURL.path]
                    arguments.append(contentsOf: fileNames)
                    
                case "7z":
                    guard let sevenZipPath = self.findCommandPath("7z") else {
                        throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "7z command not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: sevenZipPath)
                    arguments = ["d", archiveURL.path]
                    arguments.append(contentsOf: fileNames)
                    
                case "rar":
                    guard let rarPath = self.findCommandPath("rar") else {
                        throw NSError(domain: "CommandNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "rar command not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: rarPath)
                    arguments = ["d", archiveURL.path]
                    arguments.append(contentsOf: fileNames)
                    
                default:
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Deleting files from \(format) archives is not supported"
                        self.showAlert = true
                    }
                    return
                }
                
                process.arguments = arguments
                
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.progress = 1.0
                        self.error = "Files removed from archive successfully"
                        self.showAlert = true
                        // 重新加载归档内容
                        self.listArchiveContents(archiveURL)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.error = "Failed to remove files"
                        self.showAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = "Failed to remove files: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
    
    func format(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - 毛玻璃效果修饰器
struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .edgesIgnoringSafeArea(.all)
            )
    }
}

// NSVisualEffectView 包装器
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

extension View {
    func glassBackground() -> some View {
        self.modifier(GlassBackground())
    }
}

// MARK: - 帮助条目模型
struct HelpItem: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let keywords: [String]
}

// MARK: - 帮助视图（带搜索框）
struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedItem: UUID?
    
    let helpItems: [HelpItem] = [
        HelpItem(
            title: "📦 Open Archive",
            content: """
            Click 'Open Archive' or press ⌘O to open and view archive contents.
            
            Supported formats:
            • ZIP - Standard compression format
            • TAR - Tape Archive format
            • GZ - Gzip compressed files
            • 7Z - High compression ratio format (requires p7zip)
            • RAR - Proprietary archive format (requires unar/rar)
            """,
            keywords: ["open", "archive", "zip", "tar", "gz", "7z", "rar", "load"]
        ),
        HelpItem(
            title: "🆕 New Archive",
            content: """
            Click 'New Archive' or press ⌘W to create a new archive.
            
            Steps:
            1. Add files or folders using the Add buttons
            2. Enter a custom name for your archive
            3. Choose the format: ZIP, TAR, GZ, 7Z, or RAR
            4. Select a destination folder
            5. Click Create to generate the archive
            
            Note: 7Z and RAR compression require additional tools.
            """,
            keywords: ["new", "create", "compress", "zip", "tar", "gz", "7z", "rar"]
        ),
        HelpItem(
            title: "📤 Extract",
            content: """
            Select files in the list, then click 'Extract' to extract them.
            
            • Select single files by clicking
            • Select multiple files by holding ⌘ while clicking
            • Select all files with ⌘A
            • If no files are selected, all files will be extracted
            
            The extracted files will be placed in a folder named after the archive.
            """,
            keywords: ["extract", "unzip", "untar", "decompress", "unarchive"]
        ),
        HelpItem(
            title: "✏️ Modify Archive",
            content: """
            After opening an archive, you can modify it by:
            
            • Adding files: Drag and drop files directly onto the archive window
            • Adding files: Right-click and select 'Add Files...'
            • Deleting files: Select files, right-click and choose 'Delete'
            
            Note: Modification support depends on the archive format.
            ZIP, 7Z, and RAR formats support adding/deleting files.
            TAR/GZ formats have limited modification support.
            
            System files (like .DS_Store, __MACOSX) are automatically filtered.
            """,
            keywords: ["modify", "add", "delete", "update", "edit", "drag", "drop"]
        ),
        HelpItem(
            title: "🕒 Recent Files",
            content: """
            The left sidebar shows your recently opened archives.
            
            • Click on any recent file to quickly reopen it
            • Right-click or swipe to remove items from the list
            • Click 'Clear All' to remove all recent files
            """,
            keywords: ["recent", "history", "previous", "quick"]
        ),
        HelpItem(
            title: "⚙️ Settings",
            content: """
            Access settings by clicking the 'Settings' button at the bottom.
            
            Language:
            • Choose your preferred display language
            • The app needs to restart to apply language changes
            
            Tools:
            • Install required tools for 7Z and RAR support
            • Click 'Install Required Tools' to view installation commands
            """,
            keywords: ["settings", "language", "preferences", "tools", "install"]
        ),
        HelpItem(
            title: "🛠️ Tool Installation",
            content: """
            To enable full 7Z and RAR support, install the following tools using Homebrew:
            
            1. Install Homebrew (if not already installed):
               /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            2. Install 7z support:
               brew install p7zip
            
            3. Install RAR support:
               brew install unar  (for extraction)
               brew install rar   (for compression)
            
            After installation, restart the app for changes to take effect.
            """,
            keywords: ["install", "tools", "homebrew", "7z", "rar", "p7zip", "unar"]
        ),
        HelpItem(
            title: "🌐 Language",
            content: """
            Changing the language:
            
            1. Go to Settings
            2. Select your preferred language from the dropdown
            3. Click OK
            4. Restart the app when prompted
            
            The app supports multiple languages including English, Chinese, Spanish, French, German, Japanese, Korean, and more.
            """,
            keywords: ["language", "translate", "localization", "international"]
        ),
        HelpItem(
            title: "⌨️ Keyboard Shortcuts",
            content: """
            Available keyboard shortcuts:
            
            • ⌘O - Open Archive
            • ⌘W - New Archive
            • ⌘? - Open Help
            • ⌘A - Select all files in list
            • ⌘D - Deselect all files
            • ⌘, - Open Settings (if available)
            
            In dialogs, press ⏎ (Enter) to confirm or ⎋ (Escape) to cancel.
            """,
            keywords: ["shortcut", "keyboard", "hotkey", "⌘", "command"]
        )
    ]
    
    var filteredItems: [HelpItem] {
        if searchText.isEmpty {
            return helpItems
        } else {
            return helpItems.filter { item in
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.content.localizedCaseInsensitiveContains(searchText) ||
                item.keywords.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }
    
    var body: some View {
        HSplitView {
            // 左侧导航栏
            VStack(alignment: .leading, spacing: 0) {
                Text("Topics")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                List(helpItems) { item in
                    HStack {
                        Text(item.title)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(selectedItem == item.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
                    .onTapGesture {
                        selectedItem = item.id
                    }
                }
                .listStyle(PlainListStyle())
            }
            .frame(minWidth: 180, maxWidth: 250)
            
            // 右侧内容区域
            VStack(alignment: .leading, spacing: 0) {
                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField("Search", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 14))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding()
                
                Divider()
                
                // 内容显示
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if filteredItems.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No results found")
                                    .font(.headline)
                                Text("Try different keywords")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(40)
                        } else {
                            ForEach(filteredItems) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.title)
                                        .font(.title2)
                                        .bold()
                                    
                                    Text(item.content)
                                        .font(.body)
                                        .lineSpacing(4)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
                
                Divider()
                
                // 底部按钮
                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .padding()
                }
            }
        }
        .frame(width: 800, height: 550)
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var languageManager: LanguageManager
    @StateObject private var manager = ArchiveManager()
    @StateObject private var recentFilesManager = RecentFilesManager()
    @State private var selectedLanguage = "en"
    @State private var showRestartAlert = false
    @State private var copyMessage = ""
    @State private var showOpenPanel = false
    @State private var selectedRecentFile: RecentFile?
    @State private var isTargeted = false
    
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
        HSplitView {
            // 左侧最近文件列表 - 带毛玻璃效果
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent Files")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                if recentFilesManager.recentFiles.isEmpty {
                    VStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 5)
                        Text("No recent files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(recentFilesManager.recentFiles) { recentFile in
                        HStack {
                            Image(systemName: "doc.zipper")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(recentFile.name)
                                    .lineLimit(1)
                                Text(recentFile.path)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .background(selectedRecentFile?.id == recentFile.id ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                        .onTapGesture {
                            selectedRecentFile = recentFile
                            manager.listArchiveContents(recentFile.url, recentFilesManager: recentFilesManager)
                        }
                        .contextMenu {
                            Button("Remove from Recent") {
                                if let index = recentFilesManager.recentFiles.firstIndex(where: { $0.id == recentFile.id }) {
                                    recentFilesManager.recentFiles.remove(at: index)
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    
                    HStack {
                        Button("Clear All") {
                            recentFilesManager.clearAll()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .disabled(recentFilesManager.recentFiles.isEmpty)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .frame(minWidth: 200, maxWidth: 250)
            .glassBackground() // 应用毛玻璃效果
            
            // 右侧主内容 - 带拖拽区域
            VStack {
                if manager.file == nil {
                    // Empty state
                    VStack(spacing: 20) {
                        Button("Open Archive") {
                            showOpenPanel = true
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("New Archive") {
                            appState.activeSheet = .newArchive
                        }
                        .buttonStyle(.bordered)
                        
                        Text("Or drag and drop an archive here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                    .background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isTargeted ? Color.blue : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                    )
                    .padding()
                    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                        handleDrop(providers: providers)
                        return true
                    }
                } else {
                    // Main view
                    VStack(spacing: 0) {
                        // 归档信息栏
                        if let info = manager.archiveInfo {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("\(info.itemCount) items (\(info.fileCount) files, \(info.folderCount) folders)")
                                    .font(.caption)
                                if info.systemFileCount > 0 {
                                    Text("•")
                                        .font(.caption)
                                    Text("\(info.systemFileCount) system files hidden")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("•")
                                    .font(.caption)
                                Text(formatFileSize(info.size))
                                    .font(.caption)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                        }
                        
                        Divider()
                        
                        // Toolbar
                        HStack {
                            Button("Open") {
                                showOpenPanel = true
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
                        
                        // File list with selection and context menu
                        List(selection: $manager.selectedIDs) {
                            ForEach(manager.entries.filter { !$0.isSystemFile }) { entry in
                                HStack {
                                    Image(systemName: entry.isFolder ? "folder" : "doc")
                                        .foregroundColor(entry.isFolder ? .yellow : .blue)
                                    Text(entry.name)
                                    Spacer()
                                    if !entry.isFolder {
                                        Text(entry.size)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .tag(entry.id)
                                .contextMenu {
                                    Button("Delete") {
                                        manager.removeFilesFromArchive(fileNames: [entry.name])
                                    }
                                    
                                    if entry.isFolder {
                                        Button("Extract Folder") {
                                            selectFolderForExtraction(entryName: entry.name)
                                        }
                                    } else {
                                        Button("Extract File") {
                                            selectFolderForExtraction(entryName: entry.name)
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.inset)
                        
                        // 拖拽提示
                        if manager.file != nil {
                            Text("Drop files here to add to archive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity)
                                .background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                        if manager.file != nil {
                            return handleDropForAdd(providers: providers)
                        }
                        return false
                    }
                }
                
                // 底部按钮
                HStack {
                    Spacer()
                    Button("Settings") {
                        appState.activeSheet = .settings
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding(.bottom, 10)
                .padding(.top, 5)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            }
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
            }
        }
        .fileImporter(
            isPresented: $showOpenPanel,
            allowedContentTypes: [.zip, .archive]
        ) { result in
            switch result {
            case .success(let url):
                manager.listArchiveContents(url, recentFilesManager: recentFilesManager)
            case .failure:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOpenPanel)) { _ in
            showOpenPanel = true
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
    
    func selectFolderForExtraction(entryName: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Select destination folder for \(entryName)"
        panel.prompt = "Extract Here"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // 这里需要实现单个文件的提取逻辑
                // 简化处理，先提示
                DispatchQueue.main.async {
                    self.manager.error = "Single file extraction coming soon"
                    self.manager.showAlert = true
                }
            }
        }
    }
    
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: kUTTypeFileURL as String, options: nil) { (item, error) in
                defer { group.leave() }
                
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
            if let firstURL = urls.first, urls.count == 1 {
                // 单个文件，直接打开
                if firstURL.pathExtension.lowercased() == "zip" ||
                   firstURL.pathExtension.lowercased() == "7z" ||
                   firstURL.pathExtension.lowercased() == "rar" ||
                   firstURL.pathExtension.lowercased() == "tar" ||
                   firstURL.pathExtension.lowercased() == "gz" {
                    manager.listArchiveContents(firstURL, recentFilesManager: recentFilesManager)
                }
            }
        }
        
        return true
    }
    
    func handleDropForAdd(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: kUTTypeFileURL as String, options: nil) { (item, error) in
                defer { group.leave() }
                
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
            if !urls.isEmpty {
                manager.addFilesToArchive(files: urls)
            }
        }
        
        return true
    }
    
    func formatFileSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
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
    
    // GitHub 链接
    let githubURL = "https://github.com/HaoranisHaoran/Swift-Zip-Manager"
    
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
                
                // GitHub 链接部分
                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "archivebox")
                                .foregroundColor(.blue)
                            
                            Text("Swift Zip Manager")
                                .font(.headline)
                        }
                        
                        Text("Version 0.1.4 Alpha")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        HStack {
                            Image(systemName: "star")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            
                            Text("If you like this app, please star on GitHub")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Text(githubURL)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .underline()
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .onTapGesture {
                                    if let url = URL(string: githubURL) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                        }
                        .padding(.top, 4)
                        
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Text("Copy URL")
                                .font(.caption)
                                .foregroundColor(.green)
                                .onTapGesture {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(githubURL, forType: .string)
                                    copyMessage = "GitHub URL copied to clipboard"
                                    appState.showCommandCopied = true
                                }
                        }
                        .padding(.top, 4)
                        
                        // 自定义提示
                        Text("You can modify the GitHub URL in SettingsView")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(height: 350)
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
        .frame(width: 450, height: 450)
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
