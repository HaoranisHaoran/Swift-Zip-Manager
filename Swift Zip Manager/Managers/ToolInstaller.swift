import SwiftUI
import Security

// MARK: - 工具安装管理器
class ToolInstaller: ObservableObject {
    @Published var isInstalling = false
    @Published var installProgress: Double = 0
    @Published var installMessage = ""
    
    // 工具下载URL
    private let sevenzzURL = "https://github.com/ip7z/7zip/releases/download/26.00/7z2600-mac.tar.xz"
    
    // RAR 根据架构选择不同版本
    private var rarURL: String {
        #if arch(arm64)
            return "https://www.rarlab.com/rar/rarmacos-arm-720.tar.gz"
        #else
            return "https://www.rarlab.com/rar/rarmacos-x64-720.tar.gz"
        #endif
    }
    
    // 根据架构获取安装路径
    private var installPath: String {
        #if arch(arm64)
            return "/opt/local/bin"
        #else
            return "/usr/local/bin"
        #endif
    }
    
    func checkTools() -> [String] {
        var missing: [String] = []
        if !checkCommand("7zz") { missing.append("7zz") }
        if !checkCommand("rar") { missing.append("rar") }
        return missing
    }
    
    func checkCommand(_ command: String) -> Bool {
        let path = "\(installPath)/\(command)"
        return FileManager.default.fileExists(atPath: path)
    }
    
    func installTools(_ tools: [String], progress: @escaping (Double, String) -> Void, completion: @escaping (Bool, String) -> Void) {
        isInstalling = true
        installProgress = 0
        installMessage = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            var allSuccess = true
            var outputMessage = ""
            
            for (index, tool) in tools.enumerated() {
                let toolName = tool
                progress(Double(index) / Double(tools.count), "Installing \(toolName)...")
                
                let success: Bool
                if toolName == "7zz" {
                    success = self.install7zz()
                } else if toolName == "rar" {
                    success = self.installRAR()
                } else {
                    success = false
                }
                
                if !success {
                    allSuccess = false
                    outputMessage = "Failed to install \(toolName)"
                    break
                }
            }
            
            progress(1.0, "Installation complete")
            DispatchQueue.main.async {
                self.isInstalling = false
                self.installProgress = 1.0
                completion(allSuccess, outputMessage)
            }
        }
    }
    
    private func install7zz() -> Bool {
        guard let url = URL(string: sevenzzURL) else { return false }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let archivePath = tempDir.appendingPathComponent("7zz.tar.xz")
        
        // 下载
        guard downloadFile(from: url, to: archivePath) else { return false }
        
        // 解压
        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extractProcess.arguments = ["-xf", archivePath.path, "-C", tempDir.path]
        try? extractProcess.run()
        extractProcess.waitUntilExit()
        
        // 查找 7zz 可执行文件
        let findProcess = Process()
        let pipe = Pipe()
        findProcess.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        findProcess.arguments = [tempDir.path, "-name", "7zz", "-type", "f"]
        findProcess.standardOutput = pipe
        try? findProcess.run()
        findProcess.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let foundPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !foundPath.isEmpty {
            let destPath = "\(installPath)/7zz"
            
            // 创建目标目录（如果需要）
            _ = runCommandWithAdmin("/bin/mkdir", arguments: ["-p", installPath])
            
            // 复制文件
            let copySuccess = runCommandWithAdmin("/bin/cp", arguments: [foundPath, destPath])
            
            if copySuccess {
                // 设置可执行权限
                _ = runCommandWithAdmin("/bin/chmod", arguments: ["+x", destPath])
            }
            
            try? FileManager.default.removeItem(at: tempDir)
            return FileManager.default.fileExists(atPath: destPath)
        }
        
        try? FileManager.default.removeItem(at: tempDir)
        return false
    }
    
    private func installRAR() -> Bool {
        guard let url = URL(string: rarURL) else { return false }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let archivePath = tempDir.appendingPathComponent("rar.tar.gz")
        
        // 下载
        guard downloadFile(from: url, to: archivePath) else { return false }
        
        // 解压
        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extractProcess.arguments = ["-xzf", archivePath.path, "-C", tempDir.path]
        try? extractProcess.run()
        extractProcess.waitUntilExit()
        
        // 查找 rar 可执行文件
        let findProcess = Process()
        let pipe = Pipe()
        findProcess.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        findProcess.arguments = [tempDir.path, "-name", "rar", "-type", "f"]
        findProcess.standardOutput = pipe
        try? findProcess.run()
        findProcess.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let foundPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !foundPath.isEmpty {
            let destPath = "\(installPath)/rar"
            
            // 创建目标目录（如果需要）
            _ = runCommandWithAdmin("/bin/mkdir", arguments: ["-p", installPath])
            
            // 复制文件
            let copySuccess = runCommandWithAdmin("/bin/cp", arguments: [foundPath, destPath])
            
            if copySuccess {
                // 设置可执行权限
                _ = runCommandWithAdmin("/bin/chmod", arguments: ["+x", destPath])
            }
            
            try? FileManager.default.removeItem(at: tempDir)
            return FileManager.default.fileExists(atPath: destPath)
        }
        
        try? FileManager.default.removeItem(at: tempDir)
        return false
    }
    
    // 使用管理员权限运行命令
    private func runCommandWithAdmin(_ command: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        
        // 构建 AppleScript
        let cmdString = "\(command) " + arguments.map { "'\($0.replacingOccurrences(of: "'", with: "\\'"))'" }.joined(separator: " ")
        let script = """
        do shell script "\(cmdString)" with administrator privileges
        """
        
        process.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("Command failed: \(command) \(arguments), error: \(errorMsg)")
            }
            
            return process.terminationStatus == 0
        } catch {
            print("Failed to run command: \(error)")
            return false
        }
    }
    
    private func downloadFile(from url: URL, to destination: URL) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        
        let task = session.downloadTask(with: url) { tempURL, response, error in
            if let tempURL = tempURL, error == nil {
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    success = true
                } catch {
                    print("Download move error: \(error)")
                }
            } else if let error = error {
                print("Download failed: \(error)")
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        
        return success
    }
    
    func deleteTools() -> Bool {
        let sevenzzPath = "\(installPath)/7zz"
        let rarPath = "\(installPath)/rar"
        
        var success = true
        
        if FileManager.default.fileExists(atPath: sevenzzPath) {
            if !runCommandWithAdmin("/bin/rm", arguments: [sevenzzPath]) {
                success = false
            }
        }
        
        if FileManager.default.fileExists(atPath: rarPath) {
            if !runCommandWithAdmin("/bin/rm", arguments: [rarPath]) {
                success = false
            }
        }
        
        return success
    }
}
