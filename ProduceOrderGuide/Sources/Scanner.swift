import SwiftUI
import VisionKit
import CoreImage.CIFilterBuiltins

// MARK: - Barcode image (Code 128)

struct BarcodeImageView: View {
    let text: String

    var body: some View {
        if let img = Self.render(text) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 90)
                .padding(.vertical, 6)
                .background(Color.white)
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity)
        }
    }

    static func render(_ text: String) -> UIImage? {
        let f = CIFilter.code128BarcodeGenerator()
        f.message = Data(text.utf8)
        f.quietSpace = 10
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Camera scanner sheet

struct CodeCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCode: (String) -> Void
    @State private var manual = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable { code in
                        onCode(code)
                        dismiss()
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.metering.unknown").font(.largeTitle)
                        Text("Camera scanning isn't available.\nType the code below.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    TextField("Or type PLU / UPC", text: $manual)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Use") {
                        let m = manual.trimmed
                        guard !m.isEmpty else { return }
                        onCode(m)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Scan Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let s = b.payloadStringValue, !s.isEmpty {
                    done = true
                    scanner.stopScanning()
                    onCode(s)
                    return
                }
            }
        }
    }
}
