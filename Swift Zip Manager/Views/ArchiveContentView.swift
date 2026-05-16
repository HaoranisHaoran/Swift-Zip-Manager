import SwiftUI

struct ArchiveContentView: View {
    @ObservedObject var manager: ArchiveManager
    @State private var showPasswordDialog = false
    @State private var pendingFileName: String?
    @State private var pendingDestination: URL?
    @State private var passwordInput = ""
    
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
                    Button("Extract") {
                        extractFile(entry)
                    }
                    if !entry.isFolder {
                        Button("Delete") {
                            deleteFromArchive(entry)
                        }
                    }
                    Divider()
                    Button("Extract All") {
                        extractAllFiles()
                    }
                }
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $showPasswordDialog) {
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                
                Text("Password Required")
                    .font(.headline)
                
                if let fileName = pendingFileName {
                    Text(fileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                SecureField("Password", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                
                HStack(spacing: 20) {
                    Button("Cancel") {
                        showPasswordDialog = false
                        passwordInput = ""
                        pendingFileName = nil
                        pendingDestination = nil
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Extract") {
                        if let fileName = pendingFileName, let dest = pendingDestination {
                            extractWithPassword(fileName: fileName, destination: dest, password: passwordInput)
                        }
                        showPasswordDialog = false
                        passwordInput = ""
                        pendingFileName = nil
                        pendingDestination = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(passwordInput.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 350, height: 280)
        }
        // 快捷键响应
        .onReceive(NotificationCenter.default.publisher(for: .extractSelectedNotification)) { _ in
            if let firstID = manager.selectedArchiveIDs.first,
               let entry = manager.entries.first(where: { $0.id == firstID }) {
                extractFile(entry)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .extractAllNotification)) { _ in
            extractAllFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedNotification)) { _ in
            for id in manager.selectedArchiveIDs {
                if let entry = manager.entries.first(where: { $0.id == id }) {
                    deleteFromArchive(entry)
                }
            }
        }
    }
    
    func extractFile(_ entry: ArchiveEntry) {
        guard let archive = manager.currentArchive else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select destination for: \(entry.name)"
        
        panel.begin { response in
            if response == .OK, let destination = panel.url {
                let ext = archive.pathExtension.lowercased()
                
                if ext == "zip" || ext == "rar" || ext == "7z" {
                    pendingFileName = entry.name
                    pendingDestination = destination
                    passwordInput = ""
                    showPasswordDialog = true
                } else {
                    extractDirect(fileName: entry.name, archive: archive, destination: destination)
                }
            }
        }
    }
    
    func extractDirect(fileName: String, archive: URL, destination: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archive.path, "-C", destination.path, fileName]
        
        try? process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            DispatchQueue.main.async {
                manager.error = "Extracted: \(fileName)"
                manager.showAlert = true
            }
        }
    }
    
    func extractWithPassword(fileName: String, destination: URL, password: String) {
        guard let archive = manager.currentArchive else { return }
        let ext = archive.pathExtension.lowercased()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            
            if ext == "zip" {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-P", password, archive.path, fileName, "-d", destination.path]
            } else {
                guard let toolPath = self.manager.findCommand("7zz") else {
                    DispatchQueue.main.async {
                        self.manager.error = "7zz not found"
                        self.manager.showAlert = true
                    }
                    return
                }
                process.executableURL = URL(fileURLWithPath: toolPath)
                process.arguments = ["x", archive.path, "-o\(destination.path)", fileName, "-y", "-p\(password)"]
            }
            
            try? process.run()
            process.waitUntilExit()
            
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    self.manager.error = "Extracted: \(fileName)"
                } else {
                    self.manager.error = "Wrong password"
                }
                self.manager.showAlert = true
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
            manager.loadArchive(archive)
        }
    }
    
    func extractAllFiles() {
        guard let archive = manager.currentArchive else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let ext = archive.pathExtension.lowercased()
                
                if ext == "zip" || ext == "rar" || ext == "7z" {
                    pendingFileName = nil
                    pendingDestination = url
                    passwordInput = ""
                    showPasswordDialog = true
                } else {
                    manager.extractArchive(to: url)
                }
            }
        }
    }
}
