import UIKit
import ImageIO
import Photos

enum StampCorner: String, CaseIterable, Identifiable {
    case left = "左下", right = "右下"
    var id: String { rawValue }
}

enum DateStamp {
    static func metadataDate(in data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let candidates = [
            exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String,
            exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String,
            tiff?[kCGImagePropertyTIFFDateTime as String] as? String
        ]
        for value in candidates {
            guard let value else { continue }
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.calendar = Calendar(identifier: .gregorian)
            // Keep the calendar day recorded by the camera, regardless of the device time zone.
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
            parser.isLenient = false
            if let date = parser.date(from: value) { return date }
        }
        return nil
    }

    static func calendarDay(_ date: Date) -> Date {
        let local = Calendar(identifier: .gregorian)
        var utc = local
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: local.dateComponents([.year, .month, .day], from: date)) ?? date
    }

    static func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    static func render(_ image: UIImage, date: Date, corner: StampCorner) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
            let shortEdge = min(size.width, size.height)
            let font = UIFont.monospacedDigitSystemFont(ofSize: shortEdge * 0.042, weight: .medium)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor(red: 1, green: 0.23, blue: 0.02, alpha: 0.9)
            shadow.shadowBlurRadius = shortEdge * 0.004
            shadow.shadowOffset = .zero
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 1, green: 0.57, blue: 0.19, alpha: 1),
                .kern: shortEdge * 0.002,
                .shadow: shadow
            ]
            let text = label(for: date) as NSString
            let textSize = text.size(withAttributes: attributes)
            let margin = shortEdge * 0.045
            let x = corner == .right ? size.width - margin - textSize.width : margin
            text.draw(at: CGPoint(x: x, y: size.height - margin - textSize.height), withAttributes: attributes)
        }
    }
}
