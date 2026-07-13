import SwiftUI
import VisionKit

/// VisionKit live scanner: barcodes + QR capture automatically, text lines are
/// tracked continuously (for menu mode) and captured on tap.
struct DataScannerView: UIViewControllerRepresentable {
    @Binding var scanned: String?
    @Binding var visibleLines: [String]
    @Binding var startError: String?

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
        guard !vc.isScanning else { return }
        do {
            try vc.startScanning()
            context.coordinator.reportStartError(nil)
        } catch {
            context.coordinator.reportStartError(
                "The camera scanner could not start. Close other camera apps and try again."
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scanned: $scanned, visibleLines: $visibleLines, startError: $startError)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var scanned: String?
        @Binding var visibleLines: [String]
        @Binding var startError: String?
        // Menu lines ACCUMULATE across frames (keyed by normalized text) so a
        // user can pan across a whole tap list and capture every beer, instead
        // of only what fits in one viewfinder. Bounded so it can't grow forever.
        private var accumulated: [String: String] = [:]
        private var order: [String] = []
        private let cap = 80

        init(
            scanned: Binding<String?>,
            visibleLines: Binding<[String]>,
            startError: Binding<String?>
        ) {
            _scanned = scanned
            _visibleLines = visibleLines
            _startError = startError
        }

        func reportStartError(_ message: String?) {
            guard startError != message else { return }
            DispatchQueue.main.async { self.startError = message }
        }

        private func sync(_ allItems: [RecognizedItem]) {
            for item in allItems {
                if case let .text(text) = item {
                    let line = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard line.count >= 3 else { continue }
                    let key = line.lowercased()
                    if accumulated[key] == nil, accumulated.count < cap {
                        accumulated[key] = line
                        order.append(key)
                    }
                }
            }
            visibleLines = order.compactMap { accumulated[$0] }
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
