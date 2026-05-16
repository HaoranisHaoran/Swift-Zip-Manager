import SwiftUI
import AppKit

// MARK: - 更新检查器
class UpdateChecker: ObservableObject {
    @Published var isChecking = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus = ""
    @Published var updateAvailable: UpdateInfo?
    @Published var isDownloading = false
    
    private let repoOwner = "HaoranisHaoran"
    private let repoName = "Swift-Zip-Manager"
    private let targetFileName = "Swift.Zip.Manager.dmg"
    
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    
    // 当前版本 Build 号（从 Info.plist 读取）
    private var currentBuildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
    
    // 当前版本显示名
    private var currentVersionDisplay: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(shortVersion)(\(currentBuildNumber))"
    }
    
    struct UpdateInfo {
        let version: String           // v1.0.0-Beta.3(3C1)
        let buildNumber: String       // 3C1
        let body: String
        let downloadURL: URL
        let isNewer: Bool
        let fileSize: Int64?
    }
    
    // MARK: - 版本比较核心逻辑（A < B < C < D < E < F < ...）
    private func compareBuildNumber(_ build1: String, _ build2: String) -> ComparisonResult {
        let pattern = /(\d+)([A-Z])(\d+)/
        
        guard let match1 = build1.firstMatch(of: pattern),
              let match2 = build2.firstMatch(of: pattern) else {
            return build1.compare(build2)
        }
        
        let phase1 = Int(match1.1) ?? 0
        let phase2 = Int(match2.1) ?? 0
        
        let milestone1 = String(match1.2)
        let milestone2 = String(match2.2)
        
        let buildNum1 = Int(match1.3) ?? 0
        let buildNum2 = Int(match2.3) ?? 0
        
        // 1. 比较阶段数字（1=Indev, 2=Alpha, 3=Beta, 4+=正式版）
        if phase1 != phase2 {
            return phase1 > phase2 ? .orderedDescending : .orderedAscending
        }
        
        // 2. 同一阶段内，比较里程碑字母（A < B < C < D < E < F ...）
        if milestone1 != milestone2 {
            return milestone1 > milestone2 ? .orderedDescending : .orderedAscending
        }
        
        // 3. 同一里程碑内，比较构建次数
        if buildNum1 != buildNum2 {
            return buildNum1 > buildNum2 ? .orderedDescending : .orderedAscending
        }
        
        return .orderedSame
    }
    
    private func isVersionNewer(_ latestBuildNumber: String) -> Bool {
        return compareBuildNumber(latestBuildNumber, currentBuildNumber) == .orderedDescending
    }
    
    // MARK: - 检查更新
    func checkForUpdates(showIfNone: Bool = false, completion: ((Bool, String?) -> Void)? = nil) {
        isChecking = true
        
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            isChecking = false
            completion?(false, "Invalid GitHub API URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                
                if let error = error {
                    print("Update check failed: \(error)")
                    completion?(false, error.localizedDescription)
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let body = json["body"] as? String,
                      let assets = json["assets"] as? [[String: Any]] else {
                    if showIfNone {
                        self?.showNoUpdateAlert()
                    }
                    completion?(false, "Failed to parse release data")
                    return
                }
                
                // 提取 Build 号（从 tag_name 中提取括号内的部分，如 3C1）
                let buildNumber = self?.extractBuildNumber(from: tagName) ?? ""
                
                // 查找 .dmg 资产
                var assetURL: URL?
                var fileSize: Int64?
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name == self?.targetFileName,
                       let urlString = asset["browser_download_url"] as? String {
                        assetURL = URL(string: urlString)
                        fileSize = asset["size"] as? Int64
                        break
                    }
                }
                
                guard let downloadURL = assetURL else {
                    if showIfNone {
                        self?.showAlert(title: "Error", message: "Could not find download file")
                    }
                    completion?(false, "DMG file not found in release")
                    return
                }
                
                let isNewer = self?.isVersionNewer(buildNumber) ?? false
                
                let updateInfo = UpdateInfo(
                    version: tagName,
                    buildNumber: buildNumber,
                    body: body,
                    downloadURL: downloadURL,
                    isNewer: isNewer,
                    fileSize: fileSize
                )
                
                self?.updateAvailable = updateInfo
                
                if isNewer {
                    completion?(true, nil)
                } else if showIfNone {
                    self?.showNoUpdateAlert()
                    completion?(false, "No update available")
                } else {
                    completion?(false, nil)
                }
            }
        }.resume()
    }
    
    // 从 tag_name 提取 Build 号，如 "v1.0.0-Beta.3(3C1)" → "3C1"
    private func extractBuildNumber(from tagName: String) -> String {
        let pattern = /\(([^)]+)\)/
        if let match = tagName.firstMatch(of: pattern) {
            return String(match.1)
        }
        return ""
    }
    
    // MARK: - 下载并安装
    func downloadAndInstall(progress: @escaping (Double, String) -> Void, completion: @escaping (Bool, String) -> Void) {
        guard let update = updateAvailable else {
            completion(false, "No update available")
            return
        }
        
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Downloading..."
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: config)
        
        downloadTask = session.downloadTask(with: update.downloadURL) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isDownloading = false
                    completion(false, error.localizedDescription)
                    return
                }
                
                guard let tempURL = tempURL else {
                    self?.isDownloading = false
                    completion(false, "No file received")
                    return
                }
                
                self?.installUpdate(from: tempURL, completion: completion)
            }
        }
        
        // 监听下载进度
        progressObservation = downloadTask?.progress.observe(\.fractionCompleted) { [weak self] progressObj, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = progressObj.fractionCompleted
                let percent = Int(progressObj.fractionCompleted * 100)
                self?.downloadStatus = "Downloading... \(percent)%"
                progress(progressObj.fractionCompleted, self?.downloadStatus ?? "")
            }
        }
        
        downloadTask?.resume()
    }
    
    private func installUpdate(from tempURL: URL, completion: @escaping (Bool, String) -> Void) {
        downloadStatus = "Preparing installation..."
        
        let appPath = Bundle.main.bundleURL
        let appName = appPath.lastPathComponent
        let destinationDir = appPath.deletingLastPathComponent()
        let newAppPath = destinationDir.appendingPathComponent(appName)
        
        downloadStatus = "Opening DMG..."
        
        // 挂载 DMG
        let mountProcess = Process()
        mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountProcess.arguments = ["attach", tempURL.path, "-nobrowse", "-quiet"]
        
        do {
            try mountProcess.run()
            mountProcess.waitUntilExit()
            
            // 查找挂载点
            guard let mountPoint = findMountPoint(for: tempURL) else {
                completion(false, "Could not mount DMG")
                return
            }
            
            downloadStatus = "Copying files..."
            
            // 查找 .app 文件
            let contents = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                _ = ejectDMG(mountPoint)
                completion(false, "No app found in DMG")
                return
            }
            
            // 卸载 DMG
            _ = ejectDMG(mountPoint)
            
            downloadStatus = "Installing..."
            
            // 使用 AppleScript 请求管理员权限进行替换
            let success = replaceAppWithAdmin(newApp: newApp, targetPath: newAppPath)
            
            if success {
                downloadStatus = "Installation complete. Restarting..."
                completion(true, "Installation complete")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.restartApp()
                }
            } else {
                completion(false, "Could not replace app")
            }
            
        } catch {
            completion(false, error.localizedDescription)
        }
        
        isDownloading = false
    }
    
    private func findMountPoint(for dmgURL: URL) -> URL? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info"]
        process.standardOutput = pipe
        
        try? process.run()
        process.waitUntilExit()
        
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        let lines = output.split(separator: "\n")
        for (index, line) in lines.enumerated() {
            if line.contains(dmgURL.lastPathComponent) {
                if index + 1 < lines.count {
                    let mountPath = String(lines[index + 1]).trimmingCharacters(in: .whitespaces)
                    if mountPath.hasPrefix("/Volumes/") {
                        return URL(fileURLWithPath: mountPath)
                    }
                }
            }
        }
        
        return nil
    }
    
    private func ejectDMG(_ mountPoint: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
    
    private func replaceAppWithAdmin(newApp: URL, targetPath: URL) -> Bool {
        let script = """
        do shell script "rm -rf '\(targetPath.path)' && cp -R '\(newApp.path)' '\(targetPath.path)'" with administrator privileges
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func restartApp() {
        let appPath = Bundle.main.bundleURL.path
        let script = """
        do shell script "sleep 1; open '\(appPath)'" with administrator privileges
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        
        NSApplication.shared.terminate(nil)
    }
    
    private func showNoUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = "No Update Available"
        alert.informativeText = "You're running the latest version (Build \(currentBuildNumber))."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        progressObservation?.invalidate()
        progressObservation = nil
        isDownloading = false
        downloadProgress = 0
        downloadStatus = ""
    }
}
