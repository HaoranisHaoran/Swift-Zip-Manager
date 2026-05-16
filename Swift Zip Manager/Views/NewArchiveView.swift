import SwiftUI

// MARK: - New Archive View
struct NewArchiveView: View {
    @ObservedObject var manager: ArchiveManager
    @State private var files: [URL] = []
    @State private var format = "zip"
    @State private var name = ""
    @State private var destination: URL?
    @State private var showPicker = false
    @State private var encryptArchive = false
    @State private var encryptionPassword = ""
    @State private var confirmPassword = ""
    @State private var showPasswordMismatch = false
    @Environment(\.dismiss) var dismiss
    
    private var supportsEncryption: Bool {
        format == "zip" || format == "7z" || format == "rar"
    }
    
    var body: some View {
        VStack {
            Text("New Archive").font(.title2).padding()
            
            List(files, id: \.self) { file in
                HStack {
                    Text(file.lastPathComponent)
                    Spacer()
                    Text(size(file)).font(.caption)
                }
            }
            .frame(height: 150)
            
            HStack {
                Button("Add Files") { showPicker = true }
                Button("Add Folder") { showPicker = true }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Name:").font(.caption).frame(width: 50, alignment: .trailing)
                    TextField("Archive name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)
                    Text(".\(manager.getExtension(for: format))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Format:").font(.caption).frame(width: 50, alignment: .trailing)
                    Picker("", selection: $format) {
                        ForEach(manager.formats, id: \.self) {
                            Text($0.uppercased())
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                    Spacer()
                }
                HStack {
                    Text("Save to:").font(.caption).frame(width: 50, alignment: .trailing)
                    Text(destination?.lastPathComponent ?? "Not selected")
                        .font(.caption)
                        .frame(width: 200, alignment: .leading)
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.begin { if $0 == .OK { destination = panel.url } }
                    }
                    .buttonStyle(.bordered)
                }
                
                if supportsEncryption {
                    Toggle("Encrypt Archive", isOn: $encryptArchive)
                        .padding(.top, 8)
                        .padding(.leading, 58)
                    
                    if encryptArchive {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Password", text: $encryptionPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 200)
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 200)
                            if showPasswordMismatch {
                                Text("Passwords do not match")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.leading, 58)
                        .padding(.top, 4)
                    }
                }
            }
            .padding()
            
            HStack {
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard let dest = destination else { return }
                    let archiveName = name.isEmpty ? "Archive" : name
                    
                    if encryptArchive {
                        if encryptionPassword != confirmPassword {
                            showPasswordMismatch = true
                            return
                        }
                        if encryptionPassword.isEmpty {
                            return
                        }
                        manager.createArchiveWithEncryption(
                            files: files,
                            format: format,
                            name: archiveName,
                            destination: dest,
                            password: encryptionPassword
                        )
                    } else {
                        manager.createArchive(
                            files: files,
                            format: format,
                            name: archiveName,
                            destination: dest
                        )
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(files.isEmpty || destination == nil || (encryptArchive && encryptionPassword.isEmpty))
            }
        }
        .frame(width: 600, height: 550)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                files.append(contentsOf: urls)
            }
        }
    }
    
    func size(_ url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
