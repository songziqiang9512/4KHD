import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AlbumImageFormatConverter {
    /// WebP 数据转无损 PNG,返回替换后的数据与扩展名("png");
    /// 非 WebP 数据原样返回。转换失败时退回原数据,不丢图。
    nonisolated static func convertingToPNGIfWebP(_ data: Data) -> (data: Data, extensionName: String?) {
        guard isWebP(data) else { return (data, nil) }
        guard let pngData = convert(data, to: UTType.png.identifier as CFString) else {
            return (data, nil)
        }
        return (pngData, "png")
    }

    /// RIFF....WEBP 魔数检测(WebP 容器头,偏移 8 处为 "WEBP")。
    nonisolated static func isWebP(_ data: Data) -> Bool {
        guard data.count > 12 else { return false }
        return data.prefix(4) == Data("RIFF".utf8) && data.dropFirst(8).prefix(4) == Data("WEBP".utf8)
    }

    /// ImageIO 解码原图(不降采样)后重新编码,保留最高画质。
    private nonisolated static func convert(_ data: Data, to type: CFString) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
