import Foundation
import CryptoKit

final class CryptoManager {
    static let shared = CryptoManager()
    
    private init() {}
    
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
        guard data.count > 64 else { throw CryptoError.invalidData }
        
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
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passwordData),
            salt: salt,
            outputByteCount: 32
        )
    }
    
    enum CryptoError: Error {
        case invalidData
        case decryptionFailed
    }
}

// MARK: - ZIP 加密
extension CryptoManager {
    func createEncryptedZip(sourceURLs: [URL], destinationURL: URL, password: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        
        var args = ["-r"]
        if !password.isEmpty {
            args.append("-P")
            args.append(password)
        }
        args.append(destinationURL.path)
        args.append(contentsOf: sourceURLs.map { $0.path })
        
        process.arguments = args
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

// MARK: - TAR/GZ
extension CryptoManager {
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

// MARK: - 7Z 加密
extension CryptoManager {
    func createEncrypted7z(sourceURLs: [URL], destinationURL: URL, password: String, toolPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        
        var args = ["a", destinationURL.path]
        if !password.isEmpty {
            args.append("-p\(password)")
            args.append("-mhe=on")
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

// MARK: - RAR 加密
extension CryptoManager {
    func createEncryptedRar(sourceURLs: [URL], destinationURL: URL, password: String, toolPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        
        var args = ["a", "-r"]
        if !password.isEmpty {
            args.append("-hp\(password)")
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
