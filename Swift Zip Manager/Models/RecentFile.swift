import Foundation

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
