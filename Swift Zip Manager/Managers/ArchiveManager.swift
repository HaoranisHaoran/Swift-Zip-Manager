import SwiftUI

// MARK: - 归档管理器
class ArchiveManager: ObservableObject {
    @Published var currentArchive: URL?
    @Published var entries: [ArchiveEntry] = []
    @Published var selectedArchiveIDs = Set<UUID>()
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
    
    func loadArchive(_ url: URL, recentManager: RecentFilesManager? = nil) {
        currentArchive = url
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
                error = "7z not found. Please install p7zip"
                showAlert = true
                return
            }
            process.executableURL = URL(fileURLWithPath: path)
            args = ["l", url.path]
        case "rar":
            if let path = findCommand("urar") {
                process.executableURL = URL(fileURLWithPath: path)
                args = ["t", url.path]
            } else if let path = findCommand("unrar") {
                process.executableURL = URL(fileURLWithPath: path)
                args = ["lb", url.path]
            } else {
                error = "unar not found. Please install unar"
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
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("Archive:") {
                    var fileName = trimmed
                    if ext == "rar" {
                        let components = trimmed.split(separator: " ", maxSplits: 1)
                        if components.count == 2 {
                            fileName = String(components[1])
                        }
                    }
                    let isFolder = fileName.hasSuffix("/")
                    list.append(ArchiveEntry(name: fileName, size: "--", isFolder: isFolder))
                }
            }
            entries = list.filter { !$0.isSystemFile }
            selectedArchiveIDs.removeAll()
        } catch {
            self.error = error.localizedDescription
            showAlert = true
        }
    }
    
    func extractArchive(to destination: URL) {
        guard let source = currentArchive else { return }
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
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
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
    
    func createArchive(files: [URL], format: String, name: String, destination: URL) {
        if format == "rar" && findCommand("rar") == nil {
            error = "rar not found. Please install rar"
            showAlert = true
            return
        }
        if format == "7z" && findCommand("7z") == nil {
            error = "7z not found. Please install p7zip"
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
}
