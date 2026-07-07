import SwiftUI
import VisionKit

/// VisionKit live scanner for barcodes (cans/bottles) and text (tap lists).
struct DataScannerView: UIViewControllerRepresentable {
    @Binding var scanned: String?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(), .text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(scanned: $scanned) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var scanned: String?
        init(scanned: Binding<String?>) { _scanned = scanned }

        // Barcodes capture automatically; text captures on tap.
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let code = barcode.payloadStringValue {
                    scanned = code
                    return
                }
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case let .barcode(barcode): scanned = barcode.payloadStringValue
            case let .text(text): scanned = text.transcript
            @unknown default: break
            }
        }
    }
}
