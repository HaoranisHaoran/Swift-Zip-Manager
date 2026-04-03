import SwiftUI

struct ArchiveContentView: View {
    @ObservedObject var manager: ArchiveManager
    
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
            }
            .listStyle(.inset)
        }
    }
}
