import Vision
import UIKit

/// On-device receipt text extraction using the Vision framework.
/// Runs entirely on-device — no server upload, maximum privacy.
/// Supports English and Spanish receipts.
enum ReceiptOCRService {

    // MARK: - Types

    struct ReceiptData {
        let totalAmount: Double?
        let vendor: String?
        let date: Date?
        let lineItems: [LineItem]
        let rawText: String
        let confidence: ConfidenceLevel

        struct LineItem {
            let description: String
            let amount: Double?
        }
    }

    enum ConfidenceLevel: String {
        case high    // >0.8 confidence on total + vendor
        case medium  // >0.5 confidence
        case low     // Partial extraction

        var displayName: String { rawValue.capitalized }
    }

    enum OCRError: Error {
        case imageConversionFailed
        case recognitionFailed(String)
        case noTextFound
    }

    // MARK: - Public API

    /// Extract receipt data from a UIImage using on-device Vision OCR.
    static func extractReceiptData(from image: UIImage) async throws -> ReceiptData {
        guard let cgImage = image.cgImage else {
            throw OCRError.imageConversionFailed
        }

        let recognizedLines = try await performTextRecognition(on: cgImage)

        guard !recognizedLines.isEmpty else {
            throw OCRError.noTextFound
        }

        let rawText = recognizedLines.joined(separator: "\n")
        let total = extractTotal(from: recognizedLines)
        let vendor = extractVendor(from: recognizedLines)
        let date = extractDate(from: recognizedLines)
        let lineItems = extractLineItems(from: recognizedLines)

        // Score confidence based on how many fields we extracted
        let fieldsFound = [total != nil, vendor != nil, date != nil].filter { $0 }.count
        let confidence: ConfidenceLevel
        switch fieldsFound {
        case 3: confidence = .high
        case 2: confidence = .medium
        default: confidence = .low
        }

        return ReceiptData(
            totalAmount: total,
            vendor: vendor,
            date: date,
            lineItems: lineItems,
            rawText: rawText,
            confidence: confidence
        )
    }

    // MARK: - Vision Text Recognition

    private static func performTextRecognition(on image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let lines = observations.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "es"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Total Extraction

    /// Finds the total/amount due on the receipt using multiple regex strategies.
    static func extractTotal(from lines: [String]) -> Double? {
        // Strategy 1: Look for explicit "TOTAL" or "AMOUNT DUE" lines
        let totalPatterns: [String] = [
            "(?i)(?:grand\\s*total|total\\s*due|amount\\s*due|balance\\s*due|total)\\s*[:$]?\\s*\\$?([\\d,]+\\.\\d{2})",
            "(?i)(?:total)\\s+\\$?([\\d,]+\\.\\d{2})",
        ]

        for pattern in totalPatterns {
            for line in lines.reversed() { // Start from bottom — totals are usually near the end
                if let match = line.range(of: pattern, options: .regularExpression),
                   let amount = extractDollarAmount(from: String(line[match])) {
                    return amount
                }
            }
        }

        // Strategy 2: Find the largest dollar amount (likely the total)
        var largestAmount: Double = 0
        let dollarPattern = "\\$?([\\d,]+\\.\\d{2})"
        for line in lines {
            let regex = try? NSRegularExpression(pattern: dollarPattern)
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex?.matches(in: line, range: range) ?? []
            for match in matches {
                if let amountRange = Range(match.range(at: 1), in: line) {
                    let amountStr = String(line[amountRange]).replacingOccurrences(of: ",", with: "")
                    if let value = Double(amountStr), value > largestAmount, value < 10_000 {
                        largestAmount = value
                    }
                }
            }
        }

        return largestAmount > 0 ? largestAmount : nil
    }

    // MARK: - Vendor Extraction

    /// Extracts the vendor/store name — usually the first or most prominent text line.
    static func extractVendor(from lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }

        // Skip very short lines and lines that look like dates/amounts/addresses
        let skipPatterns = [
            "^\\d+$",                           // Just numbers
            "^\\$",                             // Dollar amounts
            "^\\d{1,2}[/\\-]\\d{1,2}",         // Dates
            "(?i)^(tel|phone|fax|www|http)",    // Contact info
            "(?i)(receipt|transaction|invoice)",  // Generic receipt words
            "^\\d+\\s+(\\w+\\s+)*(st|ave|blvd|rd|dr|ln|way|ct)", // Addresses
        ]

        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3, trimmed.count <= 50 else { continue }

            var shouldSkip = false
            for pattern in skipPatterns {
                if trimmed.range(of: pattern, options: .regularExpression) != nil {
                    shouldSkip = true
                    break
                }
            }

            if !shouldSkip {
                return trimmed
            }
        }

        return lines.first?.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Date Extraction

    /// Extracts a date from receipt text using common date format patterns.
    static func extractDate(from lines: [String]) -> Date? {
        let dateFormatters: [(pattern: String, format: String)] = [
            // MM/DD/YYYY or MM-DD-YYYY
            ("(\\d{1,2})[/\\-](\\d{1,2})[/\\-](\\d{4})", "MM/dd/yyyy"),
            // MM/DD/YY
            ("(\\d{1,2})[/\\-](\\d{1,2})[/\\-](\\d{2})(?!\\d)", "MM/dd/yy"),
            // Month DD, YYYY
            ("(?i)(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\w*\\s+(\\d{1,2}),?\\s+(\\d{4})", ""),
        ]

        for line in lines {
            // Try numeric date formats first
            for (pattern, format) in dateFormatters where !format.isEmpty {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let matchRange = Range(match.range, in: line) {

                    let dateStr = String(line[matchRange])
                        .replacingOccurrences(of: "-", with: "/")
                    let formatter = DateFormatter()
                    formatter.dateFormat = format
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    if let date = formatter.date(from: dateStr) {
                        return date
                    }
                }
            }

            // Try named month format
            let namedPattern = "(?i)(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\s+(\\d{1,2}),?\\s+(\\d{4})"
            if let regex = try? NSRegularExpression(pattern: namedPattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let matchRange = Range(match.range, in: line) {
                let dateStr = String(line[matchRange])
                let formatters = ["MMMM d, yyyy", "MMMM d yyyy", "MMM d, yyyy", "MMM d yyyy"]
                for fmt in formatters {
                    let formatter = DateFormatter()
                    formatter.dateFormat = fmt
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    if let date = formatter.date(from: dateStr) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Line Items

    /// Extracts line items — lines that look like "description ... $amount".
    static func extractLineItems(from lines: [String]) -> [ReceiptData.LineItem] {
        var items: [ReceiptData.LineItem] = []
        let itemPattern = "^(.+?)\\s+\\$?([\\d,]+\\.\\d{2})\\s*$"

        for line in lines {
            guard let regex = try? NSRegularExpression(pattern: itemPattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }

            let descRange = Range(match.range(at: 1), in: line)
            let amountRange = Range(match.range(at: 2), in: line)

            guard let descRange, let amountRange else { continue }

            let description = String(line[descRange]).trimmingCharacters(in: .whitespaces)
            let amountStr = String(line[amountRange]).replacingOccurrences(of: ",", with: "")

            // Skip "total", "subtotal", "tax" lines — those aren't items
            let skipWords = ["total", "subtotal", "tax", "tip", "change", "cash", "credit", "debit", "visa", "mastercard"]
            if skipWords.contains(where: { description.lowercased().contains($0) }) { continue }

            guard description.count >= 2 else { continue }

            items.append(ReceiptData.LineItem(
                description: description,
                amount: Double(amountStr)
            ))
        }

        return items
    }

    // MARK: - Helpers

    private static func extractDollarAmount(from text: String) -> Double? {
        let pattern = "\\$?([\\d,]+\\.\\d{2})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
        return Double(numStr)
    }
}
