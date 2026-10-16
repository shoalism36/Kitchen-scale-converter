import SwiftUI

// MARK: - Helpers

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Double {
    /// 2.0 -> "2", 2.5 -> "2.5"
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%g", self)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Units {
    static let all = ["lb", "ea", "bunch", "case", "bag", "box"]
}

// MARK: - Codes

enum Codes {
    struct Result {
        var barcode: String?
        var plu: String?
        var isValid: Bool { barcode != nil || plu != nil }
    }

    static func digitsOnly(_ s: String) -> String { s.filter(\.isNumber) }

    /// 3–5 digits => PLU. 6–14 digits => barcode. A barcode that is just a
    /// zero-padded PLU (0000000004770) yields both.
    static func classify(_ raw: String) -> Result {
        let d = digitsOnly(raw)
        var r = Result()
        if (3...5).contains(d.count) {
            r.plu = d
        } else if (6...14).contains(d.count) {
            r.barcode = d
            let stripped = String(d.drop(while: { $0 == "0" }))
            if (3...5).contains(stripped.count), d.count >= 8 { r.plu = stripped }
        }
        return r
    }

    static func normalized(_ barcode: String) -> String {
        String(digitsOnly(barcode).drop(while: { $0 == "0" }))
    }
}

// MARK: - Models

struct Product: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var plu: String?
    var barcode: String?
    var sku: String?
    var category: String
    var unit: String?
    var caseSize: Double?
    var supplier: String?
    var cost: Double?
    var retail: Double?
    var minOrder: Double?
    var season: String?
    var growType: String?
    var notes: String?
    var favorite: Bool?
    var active: Bool?
    var icon: String?
    var dbSource: String?

    var pluValue: String { plu ?? "" }
    var barcodeValue: String { barcode ?? "" }
    var notesValue: String { notes ?? "" }
    var unitValue: String { unit ?? "ea" }
    var defaultQty: Double { max(minOrder ?? 1, 0.5) }
    var displayIcon: String { (icon?.isEmpty == false ? icon! : "🥬") }

    /// Barcode to render: real UPC if present, else the PLU zero-padded to 13 digits.
    var barcodeForImage: String? {
        if !barcodeValue.isEmpty { return barcodeValue }
        if !pluValue.isEmpty { return String(repeating: "0", count: max(0, 13 - pluValue.count)) + pluValue }
        return nil
    }
}

struct Category: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let tint: String
    let tintText: String
}

struct OrderLine: Codable, Identifiable, Hashable {
    var id: String { "\(productId)|\(unit)" }
    var productId: String
    var name: String
    var qty: Double
    var unit: String
}

struct StoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
