import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    
    let items = [
        ("📦 Open Archive", ["Click 'Open Archive' or press ⌘O to open", "Supported: ZIP, TAR, GZ, 7Z, RAR"]),
        ("🆕 New Archive", ["Click 'New Archive' or press ⌘N to create", "Add files, choose format, select destination"]),
        ("📤 Extract", ["Select files, click 'Extract'", "Supports all formats"]),
        ("✏️ Modify", ["Drag files to add", "Right-click to delete"]),
        ("⚙️ Settings", ["Change language", "Install tools", "Press ⌘, to open settings"]),
        ("⌨️ Shortcuts", ["⌘N - New Archive", "⌘O - Open Archive", "⌘, - Settings", "⌘? - Help"])
    ]
    
    var filtered: [(String, [String])] {
        if search.isEmpty { return items }
        return items.filter { item in
            let titleMatch = item.0.localizedCaseInsensitiveContains(search)
            let contentMatch = item.1.joined().localizedCaseInsensitiveContains(search)
            return titleMatch || contentMatch
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Help")
                .font(.largeTitle)
                .bold()
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 15)
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button(action: { search = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 15)
            
            Divider()
                .padding(.bottom, 15)
            
            ScrollView {
                if filtered.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No results found for \"\(search)\"")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(filtered.indices, id: \.self) { index in
                            let item = filtered[index]
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.0)
                                    .font(.headline)
                                    .padding(.leading, 12)
                                
                                ForEach(item.1, id: \.self) { line in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .foregroundColor(.accentColor)
                                        Text(line)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.leading, 28)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            
            Divider()
                .padding(.top, 10)
            
            HStack {
                Text("Version 1.0.0 Beta 2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 16)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.trailing, 16)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 550, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
