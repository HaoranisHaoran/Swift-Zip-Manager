import SwiftUI
import UniformTypeIdentifiers

struct RightContentView: View {
    @ObservedObject var manager: ArchiveManager
    @ObservedObject var recentManager: RecentFilesManager
    @Binding var currentDirectory: URL?
    @Binding var viewMode: RightContentView.ViewMode

    @State private var items: [FileItem] = []
    @State private var selectedItemIDs = Set<UUID>()
    @State private var isLoading = false
    @State private var isDragTarget = false

    enum ViewMode: String, CaseIterable {
        case list = "list.bullet"
        case grid = "square.grid.2x2"

        var icon: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Button(action: goUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .help("Go Up")

                Spacer()

                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)

                if manager.currentArchive != nil {
                    Button("Extract All") {
                        selectFolderAndExtract()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            // 内容区域
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.currentArchive != nil {
                ArchiveContentView(manager: manager)
            } else if viewMode == .list {
                Table(items, selection: $selectedItemIDs) {
                    TableColumn("Name") { item in
                        HStack {
                            Image(systemName: item.isDirectory ? "folder" : (item.isArchive ? "doc.zipper" : "doc"))
                                .foregroundColor(item.isDirectory ? .yellow : (item.isArchive ? .blue : .secondary))
                            Text(item.name)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if item.isDirectory {
                                currentDirectory = item.url
                                loadContents()
                            } else if item.isArchive {
                                manager.loadArchive(item.url, recentManager: recentManager)
                            }
                        }
                        .contextMenu {
                            if item.isDirectory {
                                Button("Open in New Tab") {
                                    // 预留：可扩展多标签
                                }
                            } else if item.isArchive {
                                Button("Open Archive") {
                                    manager.loadArchive(item.url, recentManager: recentManager)
                                }
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                            } else {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                            }
                        }
                    }
                    TableColumn("Size", value: \.sizeFormatted).width(100)
                    TableColumn("Modified", value: \.dateFormatted).width(150)
                }
                .tableStyle(.inset)
            } else {
                // 网格模式
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
                        ForEach(items) { item in
                            VStack {
                                Image(systemName: item.isDirectory ? "folder" : (item.isArchive ? "doc.zipper" : "doc"))
                                    .font(.system(size: 40))
                                    .foregroundColor(item.isDirectory ? .yellow : (item.isArchive ? .blue : .secondary))
                                Text(item.name).font(.caption).lineLimit(1)
                                if !item.isDirectory {
                                    Text(item.sizeFormatted).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 90)
                            .padding(8)
                            .background(selectedItemIDs.contains(item.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                            .onTapGesture {
                                if item.isDirectory {
                                    currentDirectory = item.url
                                    loadContents()
                                } else if item.isArchive {
                                    manager.loadArchive(item.url, recentManager: recentManager)
                                } else {
                                    if selectedItemIDs.contains(item.id) {
                                        selectedItemIDs.remove(item.id)
                                    } else {
                                        selectedItemIDs.insert(item.id)
                                    }
                                }
                            }
                            .contextMenu {
                                if item.isDirectory {
                                    Button("Open") {
                                        currentDirectory = item.url
                                        loadContents()
                                    }
                                } else if item.isArchive {
                                    Button("Open Archive") {
                                        manager.loadArchive(item.url, recentManager: recentManager)
                                    }
                                }
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            if currentDirectory == nil {
                currentDirectory = FileManager.default.homeDirectoryForCurrentUser
            }
            loadContents()
        }
        .onChange(of: currentDirectory) { _ in
            loadContents()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTarget) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            let ext = url.pathExtension.lowercased()
                            if ["zip", "7z", "rar", "tar", "gz", "tgz"].contains(ext) {
                                manager.loadArchive(url, recentManager: recentManager)
                            } else {
                                // 如果是普通文件，可以跳转到所在目录并选中
                                currentDirectory = url.deletingLastPathComponent()
                                loadContents()
                            }
                        }
                    }
                }
            }
            return true
        }
    }

    // MARK: - 加载目录内容
    func loadContents() {
        guard let dir = currentDirectory else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedItems = loadDirectoryContents(dir)
            DispatchQueue.main.async {
                items = loadedItems
                isLoading = false
            }
        }
    }

    func loadDirectoryContents(_ url: URL) -> [FileItem] {
        var fileItems: [FileItem] = []
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey]) else {
            return fileItems
        }
        for url in contents {
            if let isHidden = try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden, isHidden { continue }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isArchive = !isDirectory && ["zip", "7z", "rar", "tar", "gz", "tgz"].contains(url.pathExtension.lowercased())
            let size = isDirectory ? nil : (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64)
            let modDate = try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            fileItems.append(FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                isArchive: isArchive,
                size: size,
                modificationDate: modDate
            ))
        }
        fileItems.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return fileItems
    }

    func goUp() {
        if let dir = currentDirectory?.deletingLastPathComponent() {
            currentDirectory = dir
            loadContents()
        }
    }

    func selectFolderAndExtract() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                manager.extractArchive(to: url)
            }
        }
    }
}
