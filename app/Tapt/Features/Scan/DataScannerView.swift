import SwiftUI
import VisionKit

/// VisionKit live scanner: barcodes + QR capture automatically, text lines are
/// tracked continuously (for menu mode) and captured on tap.
struct DataScannerView: UIViewControllerRepresentable {
    @Binding var scanned: String?
    @Binding var visibleLines: [String]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(), .text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(scanned: $scanned, visibleLines: $visibleLines) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var scanned: String?
        @Binding var visibleLines: [String]
        private var lines: [UUID: String] = [:]

        init(scanned: Binding<String?>, visibleLines: Binding<[String]>) {
            _scanned = scanned
            _visibleLines = visibleLines
        }

        private func sync(_ allItems: [RecognizedItem]) {
            lines = [:]
            for item in allItems {
                if case let .text(text) = item {
                    let line = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.count >= 3 { lines[item.id] = line }
                }
            }
            visibleLines = Array(lines.values)
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let code = barcode.payloadStringValue {
                    scanned = code
                    return
                }
            }
            sync(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            sync(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            sync(allItems)
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
