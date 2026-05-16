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
        // 1. 优先使用用户目录下的工具
        let home = FileManager.default.homeDirectoryForCurrentUser
        let toolsPath = home.appendingPathComponent("~/Library/Application Support/com.haoran.Swift-Zip-Manager/tools/\(command)")
        
        if FileManager.default.fileExists(atPath: toolsPath.path) {
            return toolsPath.path
        }
        
        // 2. 回退到系统路径
        #if arch(arm64)
            let paths = ["/opt/local/bin/\(command)"]
        #else
            let paths = ["/usr/local/bin/\(command)"]
        #endif
        
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    func loadArchive(_ url: URL, recentManager: RecentFilesManager? = nil) {
        currentArchive = url
        recentManager?.add(url)
        
        let ext = url.pathExtension.lowercased()
        let process = Process()
        var args: [String] = []
        
        switch ext {
        case "zip", "7z", "rar":
            guard let sevenzzPath = findCommand("7zz") else {
                DispatchQueue.main.async {
                    self.error = "7zz not found. Please install 7zz first"
                    self.showAlert = true
                }
                return
            }
            process.executableURL = URL(fileURLWithPath: sevenzzPath)
            args = ["l", url.path]
            
        case "tar", "gz", "tgz":
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            args = ["tf", url.path]
            
        default:
            DispatchQueue.main.async {
                self.error = "Unsupported format"
                self.showAlert = true
            }
            return
        }
        
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                var list: [ArchiveEntry] = []
                let lines = output.split(separator: "\n")
                
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { continue }
                    
                    if ext == "zip" || ext == "7z" || ext == "rar" {
                        let components = trimmed.split(separator: " ", maxSplits: 3)
                        if components.count >= 4 {
                            let size = String(components[2])
                            var fileName = String(components[3])
                            let isFolder = fileName.hasSuffix("/")
                            if isFolder {
                                fileName = String(fileName.dropLast())
                            }
                            if !fileName.isEmpty && fileName != "." && fileName != ".." {
                                list.append(ArchiveEntry(name: fileName, size: size, isFolder: isFolder))
                            }
                        }
                    } else {
                        let isFolder = trimmed.hasSuffix("/")
                        let fileName = isFolder ? String(trimmed.dropLast()) : trimmed
                        if !fileName.isEmpty && fileName != "." && fileName != ".." {
                            list.append(ArchiveEntry(name: fileName, size: "--", isFolder: isFolder))
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.entries = list.filter { !$0.isSystemFile }
                    self.selectedArchiveIDs.removeAll()
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }
    
    // MARK: - 普通提取
    func extractArchive(to destination: URL) {
        guard let source = currentArchive else { return }
        let ext = source.pathExtension.lowercased()
        
        // 需要密码的格式
        if ext == "rar" || ext == "7z" {
            DispatchQueue.main.async {
                self.promptForPassword { password in
                    if let pwd = password {
                        self.extractArchiveWithPassword(source, to: destination, password: pwd)
                    }
                }
            }
        } else {
            extractArchiveWithPassword(source, to: destination, password: nil)
        }
    }
    
    // MARK: - 带密码提取
    func extractArchiveWithPassword(_ source: URL, to destination: URL, password: String?) {
        let ext = source.pathExtension.lowercased()
        let target = destination.appendingPathComponent(source.deletingPathExtension().lastPathComponent)
        
        DispatchQueue.main.async {
            self.isProcessing = true
            self.progress = 0
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                
                let process = Process()
                var args: [String] = []
                
                switch ext {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    args = ["-o", source.path, "-d", target.path]
                    if let pwd = password, !pwd.isEmpty {
                        args.append("-P")
                        args.append(pwd)
                    }
                    
                case "7z":
                    guard let sevenzzPath = self.findCommand("7zz") else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "7zz not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: sevenzzPath)
                    args = ["x", source.path, "-o\(target.path)", "-y"]
                    if let pwd = password, !pwd.isEmpty {
                        args.append("-p\(pwd)")
                    }
                    
                case "rar":
                    guard let rarPath = self.findCommand("rar") else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "rar not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: rarPath)
                    args = ["x"]
                    if let pwd = password, !pwd.isEmpty {
                        args.append("-p\(pwd)")
                    }
                    args.append(source.path)
                    args.append(target.path)
                    
                case "tar", "gz", "tgz":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    args = ["-xf", source.path, "-C", target.path]
                    
                default:
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format"])
                }
                
                process.arguments = args
                let errorPipe = Pipe()
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.progress = 1.0
                }
                
                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.error = "Extraction complete: \(source.lastPathComponent)"
                        self.showAlert = true
                    }
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
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
    
    private func promptForPassword(completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Password Required"
        alert.informativeText = "This archive may be encrypted. Please enter the password."
        
        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField
        alert.addButton(withTitle: "Extract")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completion(textField.stringValue)
        } else {
            completion(nil)
        }
    }
    
    // MARK: - 加密创建归档
    func createArchiveWithEncryption(files: [URL], format: String, name: String, destination: URL, password: String) {
        if format == "rar" && findCommand("rar") == nil {
            DispatchQueue.main.async {
                self.error = "rar not found. Please install RAR first"
                self.showAlert = true
            }
            return
        }
        
        if format == "7z" && findCommand("7zz") == nil {
            DispatchQueue.main.async {
                self.error = "7zz not found. Please install 7zz first"
                self.showAlert = true
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let ext = self.getExtension(for: format)
                let fileName = name.hasSuffix(".\(ext)") ? name : "\(name).\(ext)"
                let targetPath = destination.appendingPathComponent(fileName).path
                
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                for file in files {
                    let destURL = tempDir.appendingPathComponent(file.lastPathComponent)
                    try FileManager.default.copyItem(at: file, to: destURL)
                }
                
                let process = Process()
                var args: [String] = []
                
                switch format {
                case "zip":
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    args = ["-r"]
                    if !password.isEmpty {
                        args.append("-P")
                        args.append(password)
                    }
                    args.append(targetPath)
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
                    guard let sevenzzPath = self.findCommand("7zz") else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "7zz not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: sevenzzPath)
                    args = ["a", targetPath, "."]
                    if !password.isEmpty {
                        args.append("-p\(password)")
                        args.append("-mhe=on")
                    }
                    process.currentDirectoryURL = tempDir
                    
                case "rar":
                    guard let rarPath = self.findCommand("rar") else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "rar not found"])
                    }
                    process.executableURL = URL(fileURLWithPath: rarPath)
                    args = ["a", "-r"]
                    if !password.isEmpty {
                        args.append("-hp\(password)")
                    }
                    args.append(targetPath)
                    args.append(".")
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
                    if process.terminationStatus == 0 {
                        self.error = "Archive created: \(fileName)"
                        self.showAlert = true
                    } else {
                        self.error = "Failed to create archive"
                        self.showAlert = true
                    }
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
    
    // MARK: - 普通创建归档
    func createArchive(files: [URL], format: String, name: String, destination: URL) {
        createArchiveWithEncryption(files: files, format: format, name: name, destination: destination, password: "")
    }
}

