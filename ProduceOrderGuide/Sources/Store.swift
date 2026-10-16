import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var order: [OrderLine] = []

    static let categories: [Category] = [
        .init(id: "apple-pod", name: "Apple Pod", icon: "🍎", tint: "FDECEA", tintText: "B3261E"),
        .init(id: "bagged-apples-citrus", name: "Bagged Apples & Citrus", icon: "🍊", tint: "FFF1E0", tintText: "B35C00"),
        .init(id: "citrus", name: "Citrus", icon: "🍋", tint: "FFF8D6", tintText: "8A6D00"),
        .init(id: "citrus-pears-stone-fruit", name: "Citrus, Pears & Stone Fruit", icon: "🍑", tint: "FFE9DD", tintText: "A8481C"),
        .init(id: "tropical-pod", name: "Tropical Pod", icon: "🥭", tint: "FFF3D1", tintText: "8F5E00"),
        .init(id: "tomato-pod", name: "Tomato Pod", icon: "🍅", tint: "FDE4E1", tintText: "B3261E"),
        .init(id: "root", name: "Potato / Onion / Garlic", icon: "🥕", tint: "FDEBD9", tintText: "9A4D0A"),
        .init(id: "bagged-potatoes-onions", name: "Bagged Potatoes & Onions", icon: "🥔", tint: "F3EBDD", tintText: "6B4E1F"),
        .init(id: "conventional-green-wet-rack", name: "Conventional Wet Rack", icon: "🥬", tint: "E4F4E3", tintText: "1E6B2A"),
        .init(id: "organic-wet-rack", name: "Organic Wet Rack", icon: "🥗", tint: "DDF3EA", tintText: "0F6B4A"),
        .init(id: "herbs", name: "Herbs", icon: "🌿", tint: "E6F5DC", tintText: "3B6B14"),
        .init(id: "vegetables", name: "Vegetables", icon: "🥦", tint: "E1F2E1", tintText: "21632B"),
        .init(id: "mushrooms", name: "Mushrooms", icon: "🍄", tint: "EFE8E2", tintText: "5E4A3A"),
        .init(id: "prepared", name: "Prepared", icon: "🥙", tint: "E8EAF6", tintText: "3949AB"),
    ]

    private var docsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var productsURL: URL { docsURL.appendingPathComponent("products.json") }
    private var orderURL: URL { docsURL.appendingPathComponent("order.json") }

    init() { load() }

    // MARK: Load / save

    private func load() {
        let dec = JSONDecoder()
        if let d = try? Data(contentsOf: productsURL), let p = try? dec.decode([Product].self, from: d) {
            products = p
        } else if let u = Bundle.main.url(forResource: "products", withExtension: "json"),
                  let d = try? Data(contentsOf: u), let p = try? dec.decode([Product].self, from: d) {
            products = p
            persistProducts()
        }
        if let d = try? Data(contentsOf: orderURL), let o = try? dec.decode([OrderLine].self, from: d) {
            order = o
        }
    }

    private func persistProducts() { try? JSONEncoder().encode(products).write(to: productsURL, options: .atomic) }
    private func persistOrder() { try? JSONEncoder().encode(order).write(to: orderURL, options: .atomic) }

    /// Discard local edits and reload the bundled catalog.
    func resetCatalog() {
        try? FileManager.default.removeItem(at: productsURL)
        products = []
        load()
    }

    // MARK: Lookup

    var visibleCategories: [Category] {
        let used = Set(products.filter { $0.active != false }.map(\.category))
        return Self.categories.filter { used.contains($0.id) }
    }

    func category(_ id: String) -> Category {
        Self.categories.first { $0.id == id }
            ?? Category(id: id, name: id.capitalized, icon: "🥬", tint: "EEEEEE", tintText: "444444")
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func products(in category: String) -> [Product] {
        products.filter { $0.category == category && $0.active != false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var favorites: [Product] {
        products.filter { $0.favorite == true && $0.active != false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func search(_ query: String) -> [Product] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        let active = products.filter { $0.active != false }
        let digits = Codes.digitsOnly(q)
        if digits.count == q.count {
            let n = Codes.normalized(digits)
            return Array(active.filter {
                $0.pluValue.hasPrefix(digits) || (!n.isEmpty && Codes.normalized($0.barcodeValue).contains(n))
            }.prefix(50))
        }
        let tokens = q.split(separator: " ").map(String.init)
        return Array(active.filter { p in
            let hay = p.name.lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }.sorted { $0.name < $1.name }.prefix(50))
    }

    /// Find an item by a scanned/typed code.
    func lookup(code raw: String) -> Product? {
        let c = Codes.classify(raw)
        if let b = c.barcode {
            let n = Codes.normalized(b)
            if let p = products.first(where: { !$0.barcodeValue.isEmpty && Codes.normalized($0.barcodeValue) == n }) { return p }
        }
        if let pl = c.plu { return products.first { $0.pluValue == pl } }
        return nil
    }

    func conflict(plu: String, barcode: String, excluding id: String) -> Product? {
        let nb = Codes.normalized(barcode)
        return products.first { p in
            p.id != id &&
            ((!plu.isEmpty && p.pluValue == plu) ||
             (!nb.isEmpty && Codes.normalized(p.barcodeValue) == nb))
        }
    }

    // MARK: Edit

    private func validate(name: String, plu: String, barcode: String) -> String? {
        if name.trimmed.isEmpty { return "Name can't be empty." }
        if !plu.isEmpty && !((3...5).contains(plu.count) && plu.allSatisfy(\.isNumber)) {
            return "PLU must be 3–5 digits."
        }
        if !barcode.isEmpty && !((6...14).contains(barcode.count) && barcode.allSatisfy(\.isNumber)) {
            return "Barcode must be 6–14 digits."
        }
        return nil
    }

    func updateDetails(id: String, name: String, plu: String, barcode: String, notes: String) -> String? {
        let plu = plu.trimmed, barcode = barcode.trimmed
        if let e = validate(name: name, plu: plu, barcode: barcode) { return e }
        guard let i = products.firstIndex(where: { $0.id == id }) else { return "Item not found." }
        products[i].name = name.trimmed
        products[i].plu = plu.isEmpty ? nil : plu
        products[i].barcode = barcode.isEmpty ? nil : barcode
        products[i].notes = notes
        persistProducts()
        return nil
    }

    func toggleFavorite(_ id: String) {
        guard let i = products.firstIndex(where: { $0.id == id }) else { return }
        products[i].favorite = !(products[i].favorite ?? false)
        persistProducts()
    }

    func addCustomProduct(name: String, category: String, unit: String, growType: String,
                          plu: String, barcode: String, notes: String) throws {
        let plu = plu.trimmed, barcode = barcode.trimmed
        if let e = validate(name: name, plu: plu, barcode: barcode) { throw StoreError(message: e) }
        if let other = conflict(plu: plu, barcode: barcode, excluding: "") {
            throw StoreError(message: "That code is already on \(other.name).")
        }
        let base = name.trimmed.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        var id = "custom-\(base)", n = 2
        while products.contains(where: { $0.id == id }) { id = "custom-\(base)-\(n)"; n += 1 }
        let cat = Self.categories.first { $0.id == category }
        products.append(Product(
            id: id, name: name.trimmed, plu: plu.isEmpty ? nil : plu,
            barcode: barcode.isEmpty ? nil : barcode, sku: "", category: category, unit: unit,
            caseSize: 1, supplier: "", cost: 0, retail: 0, minOrder: 1, season: "",
            growType: growType.isEmpty ? nil : growType, notes: notes, favorite: false,
            active: true, icon: cat?.icon, dbSource: "Custom"))
        persistProducts()
    }

    // MARK: Order

    func addToOrder(_ p: Product, qty: Double, unit: String) {
        if let i = order.firstIndex(where: { $0.productId == p.id && $0.unit == unit }) {
            order[i].qty += qty
        } else {
            order.append(OrderLine(productId: p.id, name: p.name, qty: qty, unit: unit))
        }
        persistOrder()
    }

    func pendingQty(_ id: String) -> Double? {
        let q = order.filter { $0.productId == id }.reduce(0) { $0 + $1.qty }
        return q > 0 ? q : nil
    }

    func setQty(_ line: OrderLine, _ qty: Double) {
        guard let i = order.firstIndex(where: { $0.id == line.id }) else { return }
        if qty <= 0 { order.remove(at: i) } else { order[i].qty = qty }
        persistOrder()
    }

    func removeOrderLines(at offsets: IndexSet) {
        order.remove(atOffsets: offsets)
        persistOrder()
    }

    func clearOrder() { order = []; persistOrder() }

    var orderText: String {
        let df = DateFormatter(); df.dateStyle = .medium
        var out = "Produce order — \(df.string(from: Date()))\n"
        for l in order {
            let plu = product(l.productId)?.pluValue ?? ""
            out += "\n• \(l.name)\(plu.isEmpty ? "" : " [\(plu)]") — \(l.qty.clean) \(l.unit)"
        }
        return out
    }
}
