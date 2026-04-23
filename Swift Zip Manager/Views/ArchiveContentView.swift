import SwiftUI

struct ArchiveContentView: View {
    @ObservedObject var manager: ArchiveManager
    @State private var selectedEntry: ArchiveEntry?
    
    var body: some View {
        VStack(spacing: 0) {
            if let archive = manager.currentArchive {
                HStack {
                    Image(systemName: "doc.zipper").foregroundColor(.blue)
                    Text(archive.lastPathComponent).font(.headline)
                    Spacer()
                    Text("\(manager.entries.count) items").font(.caption).foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                Divider()
            }
            
            List(manager.entries) { entry in
                HStack {
                    Image(systemName: entry.isFolder ? "folder" : "doc")
                        .foregroundColor(entry.isFolder ? .yellow : .blue)
                    Text(entry.name)
                    Spacer()
                    Text(entry.size).font(.caption).foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    if !entry.isFolder {
                        Button("Extract") {
                            extractSingleFile(entry)
                        }
                        Button("Delete from Archive") {
                            deleteFromArchive(entry)
                        }
                    }
                    Divider()
                    Button("Extract All") {
                        selectFolderAndExtract()
                    }
                }
            }
            .listStyle(.inset)
        }
    }
    
    func extractSingleFile(_ entry: ArchiveEntry) {
        guard let archive = manager.currentArchive else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select destination for: \(entry.name)"
        
        panel.begin { response in
            if response == .OK, let destination = panel.url {
                extractFile(entry.name, from: archive, to: destination)
            }
        }
    }
    
    func extractFile(_ fileName: String, from archive: URL, to destination: URL) {
        guard let sevenzz = manager.findCommand("7zz") else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sevenzz)
        process.arguments = ["x", archive.path, "-o" + destination.path, fileName, "-y"]
        
        try? process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            DispatchQueue.main.async {
                manager.error = "Extracted: \(fileName)"
                manager.showAlert = true
            }
        }
    }
    
    func deleteFromArchive(_ entry: ArchiveEntry) {
        guard let archive = manager.currentArchive,
              let sevenzz = manager.findCommand("7zz") else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sevenzz)
        process.arguments = ["d", archive.path, entry.name]
        
        try? process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            // 刷新列表
            manager.loadArchive(archive)
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
