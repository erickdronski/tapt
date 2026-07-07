import SwiftUI
import VisionKit

/// The hero loop entry: scan a label/barcode/tap list, then (next) match to the catalog and rate.
struct ScanView: View {
    @State private var scanned: String?
    @State private var showResult = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerAvailable {
                    DataScannerView(scanned: $scanned)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { hint }
                } else {
                    unsupported
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scanned) { _, value in if value != nil { showResult = true } }
            .sheet(isPresented: $showResult, onDismiss: { scanned = nil }) { resultSheet }
        }
    }

    private var hint: some View {
        Text("Point at a can, bottle barcode, or tap list")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Brand.foam)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(.bottom, 28)
    }

    private var unsupported: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "viewfinder").font(.system(size: 46)).foregroundStyle(Brand.accent)
                Text("Scanning needs a device camera")
                    .font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Text("Run Tapt on your iPhone to scan labels and barcodes.")
                    .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
    }

    private var resultSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 42)).foregroundStyle(Brand.hop).padding(.top, 28)
            Text("Scanned").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            Text(scanned ?? "")
                .font(.system(.body, design: .monospaced)).foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center).padding(.horizontal)
            Text("Beer matching comes next: we look this code up in the catalog, then you rate it and log the pour to your Cellar.")
                .font(.footnote).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
            Button("Scan another") { showResult = false }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.malt).padding(.horizontal)
            Spacer()
        }
        .presentationDetents([.medium])
        .background(Brand.background)
    }
}
