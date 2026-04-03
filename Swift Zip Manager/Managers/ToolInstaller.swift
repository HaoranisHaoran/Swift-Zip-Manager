import SwiftUI

// MARK: - 工具安装管理器
class ToolInstaller: ObservableObject {
    @Published var isInstalling = false
    @Published var installProgress: Double = 0
    @Published var installMessage = ""
    
    func checkTools() -> [String] {
        var missing: [String] = []
        if !checkCommand("unar") { missing.append("unar (RAR extraction)") }
        if !checkCommand("rar") { missing.append("rar (RAR compression)") }
        if !checkCommand("7z") { missing.append("7z (7Z support)") }
        return missing
    }
    
    func checkCommand(_ command: String) -> Bool {
        let paths = ["/usr/local/bin/\(command)", "/opt/homebrew/bin/\(command)", "/usr/bin/\(command)"]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }
    
    func installTools(_ tools: [String], progress: @escaping (Double, String) -> Void, completion: @escaping (Bool, String) -> Void) {
        isInstalling = true
        installProgress = 0
        installMessage = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            var allSuccess = true
            var outputMessage = ""
            
            if !self.checkCommand("brew") {
                progress(0.1, "Installing Homebrew...")
                let success = self.runCommand("/bin/bash", arguments: ["-c", "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"])
                if !success {
                    completion(false, "Homebrew installation failed")
                    return
                }
            }
            
            let total = Double(tools.count)
            for (index, tool) in tools.enumerated() {
                let toolName = tool.split(separator: " ").first ?? ""
                progress(Double(index) / total, "Installing \(tool)...")
                
                let success = self.runCommand("/bin/bash", arguments: ["-c", "brew install \(toolName)"])
                if !success {
                    allSuccess = false
                    outputMessage = "Failed to install \(tool)"
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
    
    private func runCommand(_ command: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
