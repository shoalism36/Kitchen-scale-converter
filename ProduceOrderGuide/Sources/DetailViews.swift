import SwiftUI

// MARK: - Product detail

struct ProductDetailView: View {
    @EnvironmentObject var store: Store
    let productId: String

    @State private var loaded = false
    @State private var name = ""
    @State private var plu = ""
    @State private var barcode = ""
    @State private var notes = ""
    @State private var qty: Double = 1
    @State private var unit = "ea"
    @State private var message: String?
    @State private var messageIsError = false
    @State private var showScanner = false
    @State private var toast: String?

    var body: some View {
        if let p = store.product(productId) {
            content(p)
        } else {
            Text("Item not found").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(_ p: Product) -> some View {
        let cat = store.category(p.category)
        Form {
            Section {
                HStack(spacing: 14) {
                    Text(p.displayIcon)
                        .font(.largeTitle)
                        .frame(width: 60, height: 60)
                        .background(Color(hex: cat.tint))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $name)
                            .font(.title3.bold())
                        Text(cat.name)
                            .font(.caption)
                            .foregroundStyle(Color(hex: cat.tintText))
                    }
                    Spacer()
                    Button {
                        store.toggleFavorite(p.id)
                    } label: {
                        Image(systemName: p.favorite == true ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                }
                if let g = p.growType, !g.isEmpty {
                    LabeledContent("Grow type", value: g)
                }
            }

            Section {
                TextField("PLU (3–5 digits)", text: $plu)
                    .keyboardType(.numberPad)
                TextField("UPC / barcode (6–14 digits)", text: $barcode)
                    .keyboardType(.numberPad)
                Button {
                    showScanner = true
                } label: {
                    Label("Scan a code into this item", systemImage: "camera.viewfinder")
                }
                Button {
                    save(p)
                } label: {
                    Text("Save Codes & Notes").bold()
                }
            } header: {
                Text("Codes")
            } footer: {
                if let m = message {
                    Text(m).foregroundStyle(messageIsError ? Color.red : Color.green)
                }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            }

            if let code = p.barcodeForImage {
                Section("Barcode") {
                    BarcodeImageView(text: code)
                    if p.barcodeValue.isEmpty {
                        Text("Made from the PLU (zero-padded to 13 digits) because this item has no UPC yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Order") {
                Stepper(value: $qty, in: 0.5...999, step: 1) {
                    Text("Qty: \(qty.clean)")
                }
                Picker("Unit", selection: $unit) {
                    ForEach(unitChoices(p), id: \.self) { Text($0).tag($0) }
                }
                Button {
                    store.addToOrder(p, qty: qty, unit: unit)
                    toast = "Added \(qty.clean) \(unit) to the order"
                } label: {
                    Label("Add to Order", systemImage: "cart.badge.plus")
                }
                if let q = store.pendingQty(p.id) {
                    Text("Already on the order: \(q.clean)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let t = toast {
                    Text(t).font(.caption).foregroundStyle(.green)
                }
            }

            if p.supplier?.isEmpty == false || (p.caseSize ?? 1) > 1 {
                Section("Details") {
                    if let s = p.supplier, !s.isEmpty { LabeledContent("Supplier", value: s) }
                    if let c = p.caseSize, c > 1 { LabeledContent("Case size", value: c.clean) }
                }
            }
        }
        .navigationTitle(p.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded { load(p) }
        }
        .sheet(isPresented: $showScanner) {
            CodeCaptureSheet { code in applyScanned(code) }
        }
    }

    private func unitChoices(_ p: Product) -> [String] {
        var u = Units.all
        if !u.contains(p.unitValue) { u.append(p.unitValue) }
        return u
    }

    private func load(_ p: Product) {
        name = p.name
        plu = p.pluValue
        barcode = p.barcodeValue
        notes = p.notesValue
        qty = p.defaultQty
        unit = p.unitValue
        loaded = true
    }

    private func save(_ p: Product) {
        if let err = store.updateDetails(id: p.id, name: name, plu: plu, barcode: barcode, notes: notes) {
            message = err
            messageIsError = true
            return
        }
        var text = "Saved."
        if let other = store.conflict(plu: plu.trimmed, barcode: barcode.trimmed, excluding: p.id) {
            text += " Note: that code is also on \(other.name)."
        }
        message = text
        messageIsError = false
    }

    private func applyScanned(_ raw: String) {
        let c = Codes.classify(raw)
        guard c.isValid else {
            message = "That scan wasn't a usable code: \(raw)"
            messageIsError = true
            return
        }
        if let b = c.barcode { barcode = b }
        if let pl = c.plu { plu = pl }
        message = "Scanned \(Codes.digitsOnly(raw)). Tap Save Codes & Notes to keep it."
        messageIsError = false
    }
}

// MARK: - Add a new item (manual entry)

struct ManualEntryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var defaultCategory: String? = nil
    var prefillCode: String? = nil

    @State private var name = ""
    @State private var categoryId = ""
    @State private var unit = "ea"
    @State private var growType = ""
    @State private var plu = ""
    @State private var barcode = ""
    @State private var notes = ""
    @State private var error: String?
    @State private var started = false
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $categoryId) {
                        ForEach(store.visibleCategories) { c in
                            Text("\(c.icon) \(c.name)").tag(c.id)
                        }
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(Units.all, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Grow type", selection: $growType) {
                        Text("—").tag("")
                        Text("Conventional").tag("Conventional")
                        Text("Organic").tag("Organic")
                    }
                }
                Section {
                    TextField("PLU (3–5 digits)", text: $plu).keyboardType(.numberPad)
                    TextField("UPC / barcode (6–14 digits)", text: $barcode).keyboardType(.numberPad)
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan a code", systemImage: "camera.viewfinder")
                    }
                } header: {
                    Text("Codes")
                } footer: {
                    if let e = error { Text(e).foregroundStyle(.red) }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                guard !started else { return }
                started = true
                categoryId = defaultCategory ?? store.visibleCategories.first?.id ?? ""
                if let code = prefillCode { fill(code) }
            }
            .sheet(isPresented: $showScanner) {
                CodeCaptureSheet { fill($0) }
            }
        }
    }

    private func fill(_ raw: String) {
        let c = Codes.classify(raw)
        if let b = c.barcode { barcode = b }
        if let p = c.plu { plu = p }
    }

    private func save() {
        do {
            try store.addCustomProduct(name: name, category: categoryId, unit: unit, growType: growType,
                                       plu: plu, barcode: barcode, notes: notes)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Pick an existing item (to attach a scanned code)

struct ProductPickerSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var title: String = "Choose Item"
    var onPick: (Product) -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let results = store.search(query)
                if query.trimmed.isEmpty {
                    Text("Type a name to find the item.")
                        .foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text("No matches").foregroundStyle(.secondary)
                } else {
                    ForEach(results) { p in
                        Button {
                            onPick(p)
                            dismiss()
                        } label: {
                            ProductRow(product: p)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, PLU or barcode")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
