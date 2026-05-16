import SwiftUI

class RecentFilesManager: ObservableObject {
    @Published var recentFiles: [RecentFile] = []
    private let maxCount = 15
    private let key = "RecentFiles"
    
    init() {
        print("RecentFilesManager init, loading data...")
        loadData()
    }
    
    func loadData() {
        if let data = UserDefaults.standard.data(forKey: key),
           let files = try? JSONDecoder().decode([RecentFile].self, from: data) {
            DispatchQueue.main.async {
                self.recentFiles = files
                print("Loaded \(files.count) recent files")
            }
        } else {
            print("No recent files found")
        }
    }
    
    func add(_ url: URL) {
        print("Adding recent file: \(url.lastPathComponent)")
        var files = recentFiles
        files.removeAll { $0.url.path == url.path }
        let newFile = RecentFile(url: url)
        files.insert(newFile, at: 0)
        if files.count > maxCount {
            files = Array(files.prefix(maxCount))
        }
        
        DispatchQueue.main.async {
            self.recentFiles = files
            print("Now have \(files.count) recent files")
        }
        
        saveData(files)
    }
    
    func remove(at indexSet: IndexSet) {
        var files = recentFiles
        files.remove(atOffsets: indexSet)
        
        DispatchQueue.main.async {
            self.recentFiles = files
        }
        
        saveData(files)
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.recentFiles = []
        }
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
        print("Cleared all recent files")
    }
    
    func refresh() {
        loadData()
    }
    
    private func saveData(_ files: [RecentFile]) {
        if let data = try? JSONEncoder().encode(files) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.synchronize()
            print("Saved \(files.count) recent files to UserDefaults")
        }
    }
}
