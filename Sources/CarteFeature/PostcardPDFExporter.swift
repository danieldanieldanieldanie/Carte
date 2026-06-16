import Foundation
import CarteCore

public protocol LocalPostcardExporter: Sendable {
    func export(_ delivery: CardDelivery) async throws -> URL
    func archiveDirectory() throws -> URL
}

public enum CartePDFExportError: Error, LocalizedError, Sendable {
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "PDF export is unavailable on this platform."
        }
    }
}

#if canImport(UIKit)
import UIKit

public struct PostcardPDFExporter: LocalPostcardExporter {
    public init() {}

    public func archiveDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = documents.appendingPathComponent("Carte Postcards", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func export(_ delivery: CardDelivery) async throws -> URL {
        let directory = try archiveDirectory()
        let safeSender = delivery.card.senderDisplayName
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "-", options: .regularExpression)
        let filename = "Carte-\(safeSender)-\(delivery.deliveredAt.ISO8601Format().replacingOccurrences(of: ":", with: "-"))-\(delivery.id.uuidString.prefix(8)).pdf"
        let url = directory.appendingPathComponent(filename)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Carte postcard from \(delivery.card.senderDisplayName)",
            kCGPDFContextAuthor as String: delivery.card.senderDisplayName,
            kCGPDFContextCreator as String: "Carte"
        ]
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 396)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)
        try renderer.writePDF(to: url) { context in
            for side in delivery.card.sides.sorted(by: { $0.index.rawValue < $1.index.rawValue }) {
                context.beginPage()
                draw(side: side, delivery: delivery, in: pageBounds)
            }
        }
        return url
    }

    private func draw(side: CardSide, delivery: CardDelivery, in bounds: CGRect) {
        UIColor(red: 1.0, green: 0.992, blue: 0.966, alpha: 1).setFill()
        UIBezierPath(rect: bounds).fill()

        let inset = bounds.insetBy(dx: 36, dy: 32)
        UIColor(white: 0, alpha: 0.12).setStroke()
        let border = UIBezierPath(roundedRect: inset, cornerRadius: 18)
        border.lineWidth = 1
        border.stroke()

        let label = side.index == .front ? "front" : "back"
        drawText(label.uppercased(), in: CGRect(x: inset.minX + 20, y: inset.minY + 18, width: 120, height: 18), font: .systemFont(ofSize: 10, weight: .medium), color: UIColor(white: 0.25, alpha: 0.65))
        drawText("from \(delivery.card.senderDisplayName)", in: CGRect(x: inset.minX + 20, y: inset.maxY - 38, width: inset.width - 40, height: 20), font: .systemFont(ofSize: 11), color: UIColor(white: 0.25, alpha: 0.65))

        let contentRect = CGRect(x: inset.minX + 44, y: inset.minY + 62, width: inset.width - 88, height: inset.height - 124)
        switch side.content {
        case .text(let text):
            drawText(text, in: contentRect, font: .serifPreferred(size: 24), color: .black)
        case .photo(let assetID):
            if let image = CarteImageLoader.image(for: assetID) {
                drawImage(image, in: contentRect)
            } else {
                drawText("Photo unavailable", in: contentRect, font: .systemFont(ofSize: 18), color: UIColor(white: 0.3, alpha: 0.7))
            }
        case .drawing:
            drawText("Drawing", in: contentRect, font: .systemFont(ofSize: 18), color: UIColor(white: 0.3, alpha: 0.7))
        }
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        text.draw(in: rect, withAttributes: attributes)
    }

    private func drawImage(_ image: UIImage, in rect: CGRect) {
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let imageRect = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        image.draw(in: imageRect)
    }
}

private extension UIFont {
    static func serifPreferred(size: CGFloat) -> UIFont {
        UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2).withDesign(.serif) ?? .preferredFontDescriptor(withTextStyle: .title2), size: size)
    }
}
#else
public struct PostcardPDFExporter: LocalPostcardExporter {
    public init() {}
    public func archiveDirectory() throws -> URL { throw CartePDFExportError.unsupportedPlatform }
    public func export(_ delivery: CardDelivery) async throws -> URL { throw CartePDFExportError.unsupportedPlatform }
}
#endif
