import SwiftUI

// MARK: - 最近文件管理器
class RecentFilesManager: ObservableObject {
    @Published var recentFiles: [RecentFile] = []
    private let maxCount = 15
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
