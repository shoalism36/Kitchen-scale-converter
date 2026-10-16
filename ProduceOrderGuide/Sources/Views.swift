import SwiftUI

// MARK: - Row

struct ProductRow: View {
    @EnvironmentObject var store: Store
    let product: Product

    var body: some View {
        let cat = store.category(product.category)
        HStack(spacing: 12) {
            Text(product.displayIcon)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(Color(hex: cat.tint))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).font(.body).lineLimit(2)
                HStack(spacing: 6) {
                    if !product.pluValue.isEmpty { Text("PLU \(product.pluValue)") }
                    if product.growType == "Organic" { Text("Organic").foregroundStyle(.green) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if product.favorite == true {
                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
            }
            if let q = store.pendingQty(product.id) {
                Text(q.clean)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Browse

struct BrowseView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var showScanner = false
    @State private var showManual = false
    @State private var scanned: String?
    @State private var pickForCode: String?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !query.trimmed.isEmpty {
                    let results = store.search(query)
                    if results.isEmpty {
                        Text("No matches").foregroundStyle(.secondary)
                    }
                    ForEach(results) { p in
                        NavigationLink(value: p.id) { ProductRow(product: p) }
                    }
                } else {
                    if !store.favorites.isEmpty {
                        Section("Favorites") {
                            ForEach(store.favorites) { p in
                                NavigationLink(value: p.id) { ProductRow(product: p) }
                            }
                        }
                    }
                    Section("Categories") {
                        ForEach(store.visibleCategories) { c in
                            NavigationLink {
                                CategoryView(category: c)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(c.icon)
                                        .font(.title3)
                                        .frame(width: 36, height: 36)
                                        .background(Color(hex: c.tint))
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                    Text(c.name)
                                    Spacer()
                                    Text("\(store.products(in: c.id).count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Name, PLU or barcode")
            .navigationTitle("Order Guide")
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                    Button { showManual = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showScanner) {
                CodeCaptureSheet { handleScan($0) }
            }
            .sheet(isPresented: $showManual) {
                ManualEntryView()
            }
            .sheet(item: Binding(get: { pickForCode.map(Identified.init) },
                                 set: { pickForCode = $0?.value })) { item in
                ScanMissSheet(code: item.value) { id in path.append(id) }
            }
        }
    }

    private func handleScan(_ code: String) {
        if let p = store.lookup(code: code) {
            path.append(p.id)
        } else {
            // dismiss of scanner sheet finishes first, then show the miss sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pickForCode = code }
        }
    }
}

private struct Identified: Identifiable { let value: String; var id: String { value } }

/// Shown when a scanned code matches nothing: attach it to an item or add a new one.
private struct ScanMissSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let code: String
    var openProduct: (String) -> Void
    @State private var mode: Mode = .menu
    enum Mode { case menu, pick, new }

    var body: some View {
        switch mode {
        case .menu:
            NavigationStack {
                List {
                    Section { Text("No item has code \(Codes.digitsOnly(code)).") }
                    Button { mode = .pick } label: { Label("Attach to existing item", systemImage: "link") }
                    Button { mode = .new } label: { Label("Create new item", systemImage: "plus.circle") }
                }
                .navigationTitle("Unknown Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
            .presentationDetents([.medium])
        case .pick:
            ProductPickerSheet(title: "Attach Code") { p in
                let c = Codes.classify(code)
                _ = store.updateDetails(id: p.id, name: p.name,
                                        plu: c.plu ?? p.pluValue,
                                        barcode: c.barcode ?? p.barcodeValue,
                                        notes: p.notesValue)
                openProduct(p.id)
            }
        case .new:
            ManualEntryView(prefillCode: code)
        }
    }
}

// MARK: - Category

struct CategoryView: View {
    @EnvironmentObject var store: Store
    let category: Category
    @State private var query = ""
    @State private var showManual = false

    var body: some View {
        let all = store.products(in: category.id)
        let items = query.trimmed.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.pluValue.hasPrefix(query.trimmed)
        }
        List(items) { p in
            NavigationLink { ProductDetailView(productId: p.id) } label: { ProductRow(product: p) }
        }
        .searchable(text: $query, prompt: "Filter \(category.name)")
        .navigationTitle(category.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showManual = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showManual) { ManualEntryView(defaultCategory: category.id) }
    }
}

// MARK: - Order

struct OrderView: View {
    @EnvironmentObject var store: Store
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if store.order.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "cart").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Order is empty").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.order) { line in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(line.name)
                                    if let p = store.product(line.productId), !p.pluValue.isEmpty {
                                        Text("PLU \(p.pluValue)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Stepper(value: Binding(get: { line.qty },
                                                       set: { store.setQty(line, $0) }),
                                        in: 0...999, step: 1) {
                                    Text("\(line.qty.clean) \(line.unit)")
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .frame(maxWidth: 190)
                            }
                        }
                        .onDelete { store.removeOrderLines(at: $0) }
                    }
                }
            }
            .navigationTitle("Order")
            .toolbar {
                if !store.order.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear", role: .destructive) { confirmClear = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: store.orderText) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .confirmationDialog("Clear the whole order?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Order", role: .destructive) { store.clearOrder() }
            }
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TabView {
            BrowseView()
                .tabItem { Label("Guide", systemImage: "list.bullet") }
            OrderView()
                .tabItem { Label("Order", systemImage: "cart") }
                .badge(store.order.count)
        }
    }
}
