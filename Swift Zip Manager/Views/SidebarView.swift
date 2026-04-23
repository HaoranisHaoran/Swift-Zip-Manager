import SwiftUI
import UniformTypeIdentifiers

// MARK: - 侧边栏行
struct SidebarRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(title)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 侧边栏视图
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var manager: ArchiveManager
    @ObservedObject var recentManager: RecentFilesManager
    @Binding var currentDirectory: URL?
    @State private var selectedSidebarItem: String? = "home"
    
    // 获取系统本地化名称
    private func getLocalizedName(for url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.localizedNameKey]) {
            return values.localizedName ?? url.lastPathComponent
        }
        return url.lastPathComponent
    }
    
    var body: some View {
        List {
            // MARK: - Quick Actions
            Section("Quick Actions") {
                SidebarRow(icon: "doc.badge.plus", title: "New Archive", isSelected: false) {
                    appState.showNewArchive = true
                }
                SidebarRow(icon: "folder", title: "Open Archive", isSelected: false) {
                    openArchive()
                }
            }
            
            // MARK: - Locations (跟随系统语言)
            Section("Locations") {
                // Desktop
                if let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                    SidebarRow(icon: "desktopcomputer", title: getLocalizedName(for: url), isSelected: selectedSidebarItem == "desktop") {
                        currentDirectory = url
                        manager.currentArchive = nil
                        selectedSidebarItem = "desktop"
                    }
                }
                
                // Documents
                if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    SidebarRow(icon: "documents", title: getLocalizedName(for: url), isSelected: selectedSidebarItem == "documents") {
                        currentDirectory = url
                        manager.currentArchive = nil
                        selectedSidebarItem = "documents"
                    }
                }
                
                // Downloads
                if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    SidebarRow(icon: "arrow.down.circle", title: getLocalizedName(for: url), isSelected: selectedSidebarItem == "downloads") {
                        currentDirectory = url
                        manager.currentArchive = nil
                        selectedSidebarItem = "downloads"
                    }
                }
                
                // Home
                let homeURL = FileManager.default.homeDirectoryForCurrentUser
                SidebarRow(icon: "house", title: getLocalizedName(for: homeURL), isSelected: selectedSidebarItem == "home") {
                    currentDirectory = homeURL
                    manager.currentArchive = nil
                    selectedSidebarItem = "home"
                }
            }
            
            // MARK: - Volumes (外置磁盘)
            Section("Volumes") {
                ForEach(getVolumes(), id: \.url) { volume in
                    SidebarRow(icon: "externaldrive", title: volume.name, isSelected: selectedSidebarItem == volume.url.path) {
                        currentDirectory = volume.url
                        manager.currentArchive = nil
                        selectedSidebarItem = volume.url.path
                    }
                }
            }
            
            // MARK: - Recent Files
            if !recentManager.recentFiles.isEmpty {
                Section("Recent") {
                    ForEach(recentManager.recentFiles.prefix(10), id: \.self) { file in
                        Button(action: {
                            manager.loadArchive(file.url, recentManager: recentManager)
                            selectedSidebarItem = nil
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.zipper")
                                    .frame(width: 24)
                                    .foregroundColor(.blue)
                                Text(file.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove") {
                                if let index = recentManager.recentFiles.firstIndex(where: { $0.id == file.id }) {
                                    recentManager.recentFiles.remove(at: index)
                                }
                            }
                        }
                    }
                    
                    if recentManager.recentFiles.count > 10 {
                        Button("Clear All") {
                            recentManager.clear()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // MARK: - Settings (底部)
            Section {
                SidebarRow(icon: "gear", title: "Settings", isSelected: false) {
                    appState.showSettings = true
                }
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 220, maxWidth: 280)
    }
    
    // 获取磁盘列表
    func getVolumes() -> [(url: URL, name: String)] {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: .skipHiddenVolumes) ?? []
        return volumes.compactMap { url in
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
            return (url: url, name: name)
        }
    }
    
    // 打开归档文件
    func openArchive() {
        let panel = NSOpenPanel()
        var contentTypes: [UTType] = []
        
        if let zip = UTType(filenameExtension: "zip") { contentTypes.append(zip) }
        if let sevenZ = UTType(filenameExtension: "7z") { contentTypes.append(sevenZ) }
        if let rar = UTType(filenameExtension: "rar") { contentTypes.append(rar) }
        if let tar = UTType(filenameExtension: "tar") { contentTypes.append(tar) }
        if let gz = UTType(filenameExtension: "gz") { contentTypes.append(gz) }
        if let tgz = UTType(filenameExtension: "tgz") { contentTypes.append(tgz) }
        
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select an archive file"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                manager.loadArchive(url, recentManager: recentManager)
                selectedSidebarItem = nil
            }
        }
    }
}
