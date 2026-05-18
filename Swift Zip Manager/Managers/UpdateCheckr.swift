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
    
    // App Support 目录路径
    private var appSupportFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.haoran.Swift-Zip-Manager")
    }
    
    private var downloadedDMGURL: URL {
        return appSupportFolder.appendingPathComponent("update.dmg")
    }
    
    // 当前版本 Build 号
    private var currentBuildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
    
    private var currentVersionDisplay: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(shortVersion)(\(currentBuildNumber))"
    }
    
    struct UpdateInfo {
        let version: String
        let buildNumber: String
        let body: String
        let downloadURL: URL
        let isNewer: Bool
        let fileSize: Int64?
    }
    
    // MARK: - Build 号比较
    private func compareBuildNumber(_ build1: String, _ build2: String) -> ComparisonResult {
        func parse(_ build: String) -> (major: Int, letter: String, minor: Int)? {
            let pattern = "^(\\d+)([A-Za-z])(\\d+)$"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: build, range: NSRange(location: 0, length: build.utf16.count)) else {
                return nil
            }
            
            let nsString = build as NSString
            let major = Int(nsString.substring(with: match.range(at: 1))) ?? 0
            let letter = nsString.substring(with: match.range(at: 2))
            let minor = Int(nsString.substring(with: match.range(at: 3))) ?? 0
            
            return (major, letter, minor)
        }
        
        guard let p1 = parse(build1), let p2 = parse(build2) else {
            return build1.compare(build2)
        }
        
        if p1.major != p2.major {
            return p1.major > p2.major ? .orderedDescending : .orderedAscending
        }
        if p1.letter != p2.letter {
            return p1.letter > p2.letter ? .orderedDescending : .orderedAscending
        }
        if p1.minor != p2.minor {
            return p1.minor > p2.minor ? .orderedDescending : .orderedAscending
        }
        return .orderedSame
    }
    
    private func isVersionNewer(_ latestBuildNumber: String) -> Bool {
        return compareBuildNumber(latestBuildNumber, currentBuildNumber) == .orderedDescending
    }
    
    // MARK: - 清理旧的更新文件
    private func cleanOldUpdateFile() {
        if FileManager.default.fileExists(atPath: downloadedDMGURL.path) {
            try? FileManager.default.removeItem(at: downloadedDMGURL)
        }
    }
    
    // MARK: - 检查更新
    func checkForUpdates(showIfNone: Bool = false, completion: ((Bool, String?) -> Void)? = nil) {
        isChecking = true
        cleanOldUpdateFile()
        
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases"
        guard let url = URL(string: urlString) else {
            isChecking = false
            completion?(false, "Invalid GitHub API URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                
                if let error = error {
                    completion?(false, error.localizedDescription)
                    return
                }
                
                guard let data = data else {
                    completion?(false, "No data received")
                    return
                }
                
                do {
                    guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                          let firstRelease = jsonArray.first,
                          let tagName = firstRelease["tag_name"] as? String,
                          let assets = firstRelease["assets"] as? [[String: Any]] else {
                        if showIfNone {
                            self?.showNoUpdateAlert()
                        }
                        completion?(false, "Failed to parse release data")
                        return
                    }
                    
                    let body = firstRelease["body"] as? String ?? ""
                    let buildNumber = self?.extractBuildNumber(from: tagName) ?? ""
                    
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
                    
                } catch {
                    completion?(false, error.localizedDescription)
                }
            }
        }.resume()
    }
    
    private func extractBuildNumber(from tagName: String) -> String {
        let pattern = "\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tagName, range: NSRange(location: 0, length: tagName.utf16.count)) else {
            return ""
        }
        
        if match.numberOfRanges >= 2 {
            let range = Range(match.range(at: 1), in: tagName)!
            return String(tagName[range])
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
                
                guard let self = self else { return }
                
                do {
                    try FileManager.default.createDirectory(at: self.appSupportFolder, withIntermediateDirectories: true)
                    
                    if FileManager.default.fileExists(atPath: self.downloadedDMGURL.path) {
                        try FileManager.default.removeItem(at: self.downloadedDMGURL)
                    }
                    
                    try FileManager.default.moveItem(at: tempURL, to: self.downloadedDMGURL)
                    print("✅ DMG 已保存到: \(self.downloadedDMGURL.path)")
                    
                    self.installUpdate(completion: completion)
                } catch {
                    self.isDownloading = false
                    completion(false, "Failed to save DMG: \(error.localizedDescription)")
                }
            }
        }
        
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
    
    // MARK: - 安装更新
    private func installUpdate(completion: @escaping (Bool, String) -> Void) {
        downloadStatus = "Preparing installation..."
        
        let appPath = Bundle.main.bundleURL
        let appName = appPath.lastPathComponent
        let destinationDir = appPath.deletingLastPathComponent()
        let targetPath = destinationDir.appendingPathComponent(appName)
        
        // 新 App 的临时路径（加 _New 后缀）
        let tempNewPath = destinationDir.appendingPathComponent(
            (appName as NSString).deletingPathExtension + "_New.app"
        )
        
        print("📁 源 App 位置（DMG 挂载后）: 待查找")
        print("📁 临时新 App 路径: \(tempNewPath.path)")
        print("📁 最终目标路径: \(targetPath.path)")
        
        // 检查 DMG 文件是否存在
        guard FileManager.default.fileExists(atPath: downloadedDMGURL.path) else {
            completion(false, "DMG file not found")
            return
        }
        
        downloadStatus = "Opening DMG..."
        
        // 使用 open 命令挂载 DMG
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = [downloadedDMGURL.path]
        
        do {
            try openProcess.run()
            openProcess.waitUntilExit()
            
            guard openProcess.terminationStatus == 0 else {
                completion(false, "Failed to open DMG")
                return
            }
            
            // 等待系统完成挂载
            Thread.sleep(forTimeInterval: 2.0)
            
            downloadStatus = "Finding mounted volume..."
            
            // 查找挂载点
            guard let mountPoint = findMountPoint() else {
                completion(false, "Could not find mounted DMG location")
                return
            }
            
            print("📂 挂载点: \(mountPoint.path)")
            
            downloadStatus = "Copying files..."
            
            // 查找 .app 文件
            let contents = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                _ = ejectDMG(mountPoint)
                completion(false, "No app found in DMG")
                return
            }
            
            print("✅ 找到 App: \(newApp.lastPathComponent)")
            
            // 1. 先复制到临时位置（加 _New 后缀）
            downloadStatus = "Copying to temporary location..."
            
            // 清理可能存在的旧临时文件
            if FileManager.default.fileExists(atPath: tempNewPath.path) {
                try FileManager.default.removeItem(at: tempNewPath)
            }
            
            try FileManager.default.copyItem(at: newApp, to: tempNewPath)
            print("✅ 已复制到临时位置: \(tempNewPath.path)")
            
            // 2. 卸载 DMG
            _ = ejectDMG(mountPoint)
            
            // 3. 删除旧版本
            downloadStatus = "Removing old version..."
            if FileManager.default.fileExists(atPath: targetPath.path) {
                try FileManager.default.removeItem(at: targetPath)
                print("🗑️ 已删除旧版本")
            }
            
            // 4. 将临时文件改名为正式名称
            downloadStatus = "Installing new version..."
            try FileManager.default.moveItem(at: tempNewPath, to: targetPath)
            print("✅ 已安装新版本: \(targetPath.path)")
            
            downloadStatus = "Installation complete. Restarting..."
            completion(true, "Installation complete")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.restartApp()
            }
            
        } catch {
            print("❌ 安装失败: \(error)")
            completion(false, error.localizedDescription)
        }
        
        isDownloading = false
    }
    
    // MARK: - 查找挂载点
    private func findMountPoint() -> URL? {
        Thread.sleep(forTimeInterval: 0.5)
        
        let volumes = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)
        
        for volume in volumes ?? [] {
            let volumeName = volume.lastPathComponent
            if volumeName != "Macintosh HD" && !volumeName.hasPrefix("Recovery") && !volumeName.hasPrefix("Preboot") {
                print("📁 发现卷: \(volumeName)")
                if volumeName.contains("Swift") || volumeName.contains("Zip") {
                    return volume
                }
            }
        }
        
        // 返回第一个非系统卷
        for volume in volumes ?? [] {
            let volumeName = volume.lastPathComponent
            if volumeName != "Macintosh HD" && !volumeName.hasPrefix("Recovery") && !volumeName.hasPrefix("Preboot") {
                return volume
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
    
    private func restartApp() {
        let appPath = Bundle.main.bundleURL.path
        
        guard FileManager.default.fileExists(atPath: appPath) else {
            print("❌ App 不存在，无法重启")
            return
        }
        
        let script = """
        do shell script "sleep 1; open '\(appPath)'"
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
