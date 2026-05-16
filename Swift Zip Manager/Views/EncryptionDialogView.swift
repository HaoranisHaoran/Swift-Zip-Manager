import Foundation
import CryptoKit
import CommonCrypto

// MARK: - 加密管理器
class EncryptionManager: ObservableObject {
    static let shared = EncryptionManager()
    
    enum EncryptionType: String, CaseIterable {
        case none = "None"
        case aes256 = "AES-256"
        case zip20 = "Zip 2.0 (Legacy)"
        case zipAES = "Zip AES-256"
    }
    
    // 系统加密方法
    func encryptData(_ data: Data, with password: String) throws -> Data {
        let salt = generateSalt()
        let key = deriveKey(from: password, salt: salt)
        let iv = generateIV()
        
        let encrypted = try AES.GCM.seal(data, using: key, nonce: AES.GCM.Nonce(data: iv))
        
        var result = Data()
        result.append(salt)
        result.append(iv)
        result.append(encrypted.ciphertext)
        result.append(encrypted.tag)
        
        return result
    }
    
    func decryptData(_ data: Data, with password: String) throws -> Data {
        guard data.count > 64 else { throw EncryptionError.invalidData }
        
        let salt = data.prefix(32)
        let iv = data.subdata(in: 32..<48)
        let tag = data.suffix(16)
        let ciphertext = data.subdata(in: 48..<data.count - 16)
        
        let key = deriveKey(from: password, salt: salt)
        
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    private func generateSalt() -> Data {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        return salt
    }
    
    private func generateIV() -> Data {
        var iv = Data(count: 12)
        _ = iv.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 12, bytes.baseAddress!)
        }
        return iv
    }
    
    private func deriveKey(from password: String, salt: Data) -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passwordData),
            salt: salt,
            outputByteCount: 32
        )
        return key
    }
    
    enum EncryptionError: Error {
        case invalidData
        case decryptionFailed
    }
}

// MARK: - Zip 加密扩展 (使用系统 libz)
extension EncryptionManager {
    func createEncryptedZip(sourceURLs: [URL], destinationURL: URL, password: String, progress: @escaping (Double) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        
        var args = ["-j", "-r"]
        
        if !password.isEmpty {
            args.append("-P")
            args.append(password)
        }
        
        args.append(destinationURL.path)
        args.append(contentsOf: sourceURLs.map { $0.path })
        
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "ZipError", code: Int(process.terminationStatus))
        }
    }
    
    func extractEncryptedZip(sourceURL: URL, destinationURL: URL, password: String?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        
        var args = ["-o", sourceURL.path, "-d", destinationURL.path]
        
        if let pwd = password, !pwd.isEmpty {
            args.append("-P")
            args.append(pwd)
        }
        
        process.arguments = args
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "UnzipError", code: Int(process.terminationStatus))
        }
    }
}

// MARK: - Tar/Gz 处理 (使用系统 libarchive)
extension EncryptionManager {
    func createTar(from sourceURLs: [URL], destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-cf", destinationURL.path] + sourceURLs.map { $0.path }
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "TarError", code: Int(process.terminationStatus))
        }
    }
    
    func extractTar(sourceURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", sourceURL.path, "-C", destinationURL.path]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "UntarError", code: Int(process.terminationStatus))
        }
    }
    
    func createGzip(from sourceURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", sourceURL.path]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        try outputData.write(to: destinationURL)
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "GzipError", code: Int(process.terminationStatus))
        }
    }
    
    func extractGzip(sourceURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", sourceURL.path]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        try outputData.write(to: destinationURL)
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "GunzipError", code: Int(process.terminationStatus))
        }
    }
}

// MARK: - 7z 加密 (使用 7zz)
extension EncryptionManager {
    func createEncrypted7z(sourceURLs: [URL], destinationURL: URL, password: String, toolPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        
        var args = ["a", destinationURL.path]
        
        if !password.isEmpty {
            args.append("-p\(password)")
            args.append("-mhe=on") // 加密文件名
        }
        
        args.append(contentsOf: sourceURLs.map { $0.path })
        
        process.arguments = args
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "SevenZipError", code: Int(process.terminationStatus))
        }
    }
    
    func extractEncrypted7z(sourceURL: URL, destinationURL: URL, password: String?, toolPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        
        var args = ["x", sourceURL.path, "-o\(destinationURL.path)", "-y"]
        
        if let pwd = password, !pwd.isEmpty {
            args.append("-p\(pwd)")
        }
        
        process.arguments = args
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "SevenZipError", code: Int(process.terminationStatus))
        }
    }
}

// MARK: - RAR 加密 (使用 rar)
extension EncryptionManager {
    func createEncryptedRar(sourceURLs: [URL], destinationURL: URL, password: String, toolPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        
        var args = ["a", "-r"]
        
        if !password.isEmpty {
            args.append("-hp\(password)") // 加密文件头和文件名
        }
        
        args.append(destinationURL.path)
        args.append(contentsOf: sourceURLs.map { $0.path })
        
        process.arguments = args
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "RarError", code: Int(process.terminationStatus))
        }
    }
    
    func extractEncryptedRar(sourceURL: URL, destinationURL: URL, password: String?, toolPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        
        var args = ["x"]
        
        if let pwd = password, !pwd.isEmpty {
            args.append("-p\(pwd)")
        }
        
        args.append(sourceURL.path)
        args.append(destinationURL.path)
        
        process.arguments = args
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "RarError", code: Int(process.terminationStatus))
        }
    }
}
