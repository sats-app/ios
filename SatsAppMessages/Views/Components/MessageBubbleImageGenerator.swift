import UIKit

/// Generates dynamic images for iMessage bubbles displaying Bitcoin amounts
struct MessageBubbleImageGenerator {

    enum MessageType {
        case send
        case request

        var color: UIColor {
            switch self {
            case .send:
                return UIColor.systemGreen
            case .request:
                return UIColor.systemOrange
            }
        }
    }

    /// Image dimensions for compact horizontal pill layout
    private static let imageWidth: CGFloat = 120
    private static let imageHeight: CGFloat = 60

    /// Generates a transparent image with the Bitcoin amount
    /// - Parameters:
    ///   - amount: The amount in sats
    ///   - type: Whether this is a send or request message
    /// - Returns: UIImage with transparent background showing the formatted amount
    static func generateImage(amount: UInt64, type: MessageType) -> UIImage {
        let size = CGSize(width: imageWidth, height: imageHeight)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            // Format the amount with Bitcoin symbol and comma grouping
            let formattedAmount = formatAmount(amount)

            // Configure text attributes
            let fontSize = calculateFontSize(for: formattedAmount)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: type.color,
                .paragraphStyle: paragraphStyle
            ]

            // Calculate text rect to center vertically
            let textSize = formattedAmount.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            // Draw the text
            formattedAmount.draw(in: textRect, withAttributes: attributes)
        }
    }

    /// Formats amount with Bitcoin symbol and comma grouping
    private static func formatAmount(_ sats: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return "\u{20BF}" + (formatter.string(from: NSNumber(value: sats)) ?? "0")
    }

    /// Calculates appropriate font size based on text length for compact pill layout
    private static func calculateFontSize(for text: String) -> CGFloat {
        let baseFontSize: CGFloat = 28
        let characterCount = text.count

        switch characterCount {
        case 0...4:
            return baseFontSize        // B1, B10, B100
        case 5...6:
            return baseFontSize * 0.85 // B1,000
        case 7...8:
            return baseFontSize * 0.70 // B10,000, B100,000
        case 9...10:
            return baseFontSize * 0.55 // B1,000,000
        default:
            return baseFontSize * 0.45 // B10,000,000+
        }
    }
}
