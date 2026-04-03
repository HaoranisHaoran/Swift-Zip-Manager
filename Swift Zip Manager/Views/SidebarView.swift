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

// MARK: - 文件树节点
struct FileTreeNode: View {
    let item: FileItem
    let level: Int
    @Binding var expandedItems: Set<URL>
    let onSelect: (URL) -> Void
    @State private var children: [FileItem] = []
    @State private var isLoading = false
    
    var isExpanded: Bool {
        expandedItems.contains(item.url)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: CGFloat(level * 16))
                
                if item.isDirectory {
                    Button(action: toggleExpand) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .frame(width: 16, height: 16)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 16)
                }
                
                Image(systemName: item.isDirectory ? "folder" : (item.isArchive ? "doc.zipper" : "doc"))
                    .frame(width: 20)
                    .foregroundColor(item.isDirectory ? .yellow : (item.isArchive ? .blue : .secondary))
                
                Text(item.name)
                    .lineLimit(1)
                    .font(.system(size: 13))
                
                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if item.isDirectory {
                    toggleExpand()
                } else if item.isArchive {
                    onSelect(item.url)
                }
            }
            
            if isExpanded && !isLoading {
                ForEach(children) { child in
                    FileTreeNode(
                        item: child,
                        level: level + 1,
                        expandedItems: $expandedItems,
                        onSelect: onSelect
                    )
                }
            }
        }
        .onAppear {
            if isExpanded && children.isEmpty {
                loadChildren()
            }
        }
    }
    
    func toggleExpand() {
        if isExpanded {
            expandedItems.remove(item.url)
        } else {
            expandedItems.insert(item.url)
            if children.isEmpty {
                loadChildren()
            }
        }
    }
    
    func loadChildren() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedChildren = loadDirectoryContents(item.url)
            DispatchQueue.main.async {
                children = loadedChildren
                isLoading = false
            }
        }
    }
    
    func loadDirectoryContents(_ url: URL) -> [FileItem] {
        var items: [FileItem] = []
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey]) else {
            return items
        }
        
        for url in contents {
            if let isHidden = try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden, isHidden { continue }
            
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isArchive = !isDirectory && ["zip", "7z", "rar", "tar", "gz", "tgz"].contains(url.pathExtension.lowercased())
            let size = isDirectory ? nil : (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64)
            let modDate = try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            
            items.append(FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                isArchive: isArchive,
                size: size,
                modificationDate: modDate
            ))
        }
        
        items.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        
        return items
    }
}

// MARK: - 侧边栏视图
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var manager: ArchiveManager
    @ObservedObject var recentManager: RecentFilesManager
    @Binding var currentDirectory: URL?
    @State private var expandedItems: Set<URL> = []
    @State private var rootItems: [FileItem] = []
    @State private var selectedSidebarItem: String? = "home"
    
    var body: some View {
        List {
            Section("Quick Actions") {
                SidebarRow(icon: "doc.badge.plus", title: "New Archive", isSelected: false) {
                    appState.showNewArchive = true
                }
                SidebarRow(icon: "folder", title: "Open Archive", isSelected: false) {
                    openArchive()
                }
            }
            
            Section("Locations") {
                SidebarRow(icon: "desktopcomputer", title: "Desktop", isSelected: selectedSidebarItem == "desktop") {
                    if let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                        currentDirectory = url
                        manager.currentArchive = nil
                        selectedSidebarItem = "desktop"
                    }
                }
                SidebarRow(icon: "documents", title: "Documents", isSelected: selectedSidebarItem == "documents") {
                    if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        currentDirectory = url
                        manager.currentArchive = nil
                        selectedSidebarItem = "documents"
                    }
                }
                SidebarRow(icon: "arrow.down.circle", title: "Downloads", isSelected: selectedSidebarItem == "downloads") {
                    if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                        currentDirectory = url
                        manager.currentArchive = nil
                        selectedSidebarItem = "downloads"
                    }
                }
                SidebarRow(icon: "house", title: "Home", isSelected: selectedSidebarItem == "home") {
                    currentDirectory = FileManager.default.homeDirectoryForCurrentUser
                    manager.currentArchive = nil
                    selectedSidebarItem = "home"
                }
            }
            
            Section("Volumes") {
                ForEach(getVolumes(), id: \.url) { volume in
                    SidebarRow(icon: "externaldrive", title: volume.name, isSelected: selectedSidebarItem == volume.url.path) {
                        currentDirectory = volume.url
                        manager.currentArchive = nil
                        selectedSidebarItem = volume.url.path
                    }
                }
            }
            
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
            
            Section("File Browser") {
                ForEach(rootItems) { item in
                    FileTreeNode(
                        item: item,
                        level: 0,
                        expandedItems: $expandedItems,
                        onSelect: { url in
                            let ext = url.pathExtension.lowercased()
                            if ["zip", "7z", "rar", "tar", "gz", "tgz"].contains(ext) {
                                manager.loadArchive(url, recentManager: recentManager)
                                selectedSidebarItem = nil
                            } else {
                                currentDirectory = url
                                manager.currentArchive = nil
                                selectedSidebarItem = url.path
                            }
                        }
                    )
                }
            }
            
            Section {
                SidebarRow(icon: "gear", title: "Settings", isSelected: false) {
                    appState.showSettings = true
                }
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 220, maxWidth: 280)
        .onAppear {
            loadRootItems()
        }
    }
    
    func loadRootItems() {
        var items: [FileItem] = []
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        items.append(FileItem(
            url: home,
            name: "Home",
            isDirectory: true,
            isArchive: false,
            size: nil,
            modificationDate: nil
        ))
        
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            items.append(FileItem(
                url: desktop,
                name: "Desktop",
                isDirectory: true,
                isArchive: false,
                size: nil,
                modificationDate: nil
            ))
        }
        
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            items.append(FileItem(
                url: documents,
                name: "Documents",
                isDirectory: true,
                isArchive: false,
                size: nil,
                modificationDate: nil
            ))
        }
        
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            items.append(FileItem(
                url: downloads,
                name: "Downloads",
                isDirectory: true,
                isArchive: false,
                size: nil,
                modificationDate: nil
            ))
        }
        
        rootItems = items
    }
    
    func getVolumes() -> [(url: URL, name: String)] {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: .skipHiddenVolumes) ?? []
        return volumes.compactMap { url in
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
            return (url: url, name: name)
        }
    }
    
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
