import AppKit
import CommonCrypto
import Foundation
import Nuke

/// pic.sbhioa.cn stores AES-128-CBC ciphertext. The browser plugin decrypts with
/// a UTF-8 key/IV before creating an image blob; display and save must do the same.
enum MrdsImageDecryptor {
    private nonisolated static let aesKey = Data("f5d965df75336270".utf8)
    private nonisolated static let aesIV = Data("97b60394abc2fbe1".utf8)

    private nonisolated static let registration: Void = {
        RemoteImageResponseMapper.register(
            RemoteImageResponseMapper.Record(
                matches: { url in
                    url.host?.lowercased() == "pic.sbhioa.cn"
                        && OnlineSourcePolicy.allows(url, source: .mrds, resource: .media)
                },
                map: { plaintext(from: $0) }
            )
        )
        ImageDecoderRegistry.shared.register { context in
            guard context.isCompleted else { return nil }
            let url = context.request.url ?? context.urlResponse?.url
            guard let url,
                  url.host?.lowercased() == "pic.sbhioa.cn",
                  !isImageMagic(context.data),
                  plaintext(from: context.data) != nil
            else { return nil }
            return Decoder()
        }
        return ()
    }()

    nonisolated static func prepare() {
        _ = registration
    }

    /// Returns already-plain image bytes, or decrypted bytes when the payload is
    /// a valid ciphertext. Returns `nil` when neither works.
    nonisolated static func plaintext(from data: Data) -> Data? {
        if isImageMagic(data) { return data }
        guard let plain = crypt(operation: CCOperation(kCCDecrypt), data: data),
              isImageMagic(plain)
        else { return nil }
        return plain
    }

    nonisolated static func encryptForTesting(_ data: Data) -> Data? {
        crypt(operation: CCOperation(kCCEncrypt), data: data)
    }

    nonisolated static func isImageMagic(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return true }
        if data.starts(with: [0x47, 0x49, 0x46]) { return true }
        if data.prefix(4) == Data("RIFF".utf8), data.dropFirst(8).prefix(4) == Data("WEBP".utf8) {
            return true
        }
        return false
    }

    private nonisolated static func crypt(operation: CCOperation, data: Data) -> Data? {
        let key = aesKey
        let iv = aesIV
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128, !data.isEmpty else {
            return nil
        }
        var outLength = 0
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let status = output.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outBytes.baseAddress,
                            outBytes.count,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.count = outLength
        return output
    }

    private final class Decoder: ImageDecoding, @unchecked Sendable {
        func decode(_ data: Data) throws -> ImageContainer {
            guard let plain = MrdsImageDecryptor.plaintext(from: data),
                  let image = NSImage(data: plain)
            else {
                throw ImageDecodingError.unknown
            }
            var container = ImageContainer(image: image)
            container.type = AssetType(plain)
            if container.type == .gif {
                container.data = plain
            }
            return container
        }
    }
}
