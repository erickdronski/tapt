import SwiftUI

/// The three resting positions a `RadarSheet` snaps between, like Apple Maps or
/// Uber. Each value is the fraction of the available height the sheet occupies
/// when it rests there.
enum RadarSheetDetent: CaseIterable {
    case peek   // just the handle plus a row or two
    case half   // map and list share the screen
    case full   // list takes over, a sliver of map stays

    var fraction: CGFloat {
        switch self {
        case .peek: return 0.16
        case .half: return 0.5
        case .full: return 0.92
        }
    }
}

/// A draggable bottom sheet that floats over a full-bleed map. Swipe the handle
/// up to expand the list, swipe down to collapse it back to a peek. It snaps to
/// three detents with velocity awareness, so a quick flick carries it to the
/// next stop rather than the nearest one.
///
/// This is deliberately NOT a system `.sheet`. A system sheet dims the screen
/// and covers the tab bar, which stays visible on the guest-reachable Near You
/// tab. This sheet lives inside its parent's bounds and leaves the map above it
/// fully interactive: only the handle bar captures the drag, so the map pans and
/// the list scrolls without fighting each other.
struct RadarSheet<Content: View>: View {
    @Binding var detent: RadarSheetDetent
    private let content: Content

    /// Live finger travel during a drag. Down is positive, up is negative, which
    /// matches `DragGesture` translation. Reset to zero once a drag settles.
    @State private var dragTranslation: CGFloat = 0

    init(detent: Binding<RadarSheetDetent>, @ViewBuilder content: () -> Content) {
        self._detent = detent
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            let resting = available * detent.fraction
            let minHeight = available * RadarSheetDetent.peek.fraction
            let maxHeight = available * RadarSheetDetent.full.fraction
            // Dragging up grows the sheet (subtracting a negative translation).
            let height = min(max(resting - dragTranslation, minHeight), maxHeight)

            VStack(spacing: 0) {
                handle(available: available)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(height: height, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(Brand.background)
            .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                    .stroke(Brand.malt.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Brand.malt.opacity(0.16), radius: 22, y: -4)
            // Pin the fixed-height sheet to the bottom. The empty space above it
            // has no background and no hit testing, so map touches pass through.
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        // Stay inside the bottom safe area so the sheet always rests above the
        // tab bar and home indicator, never underlapping them.
    }

    /// The grab handle. The whole bar is the drag target (via `contentShape`), so
    /// there is a comfortable area to grab without stealing scroll from the list.
    private func handle(available: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Brand.muted.opacity(0.45))
                .frame(width: 40, height: 5)
                .padding(.top, 9)
                .padding(.bottom, 11)
        }
        .frame(maxWidth: .infinity)
        .background(Brand.background)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    dragTranslation = value.translation.height
                }
                .onEnded { value in
                    // Project where the flick would land, then snap to the
                    // closest detent by height. Fast swipes carry further.
                    let projectedHeight = available * detent.fraction
                        - value.predictedEndTranslation.height
                    let target = nearestDetent(toHeight: projectedHeight, available: available)
                    if target != detent { Haptic.tap() }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        detent = target
                        dragTranslation = 0
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Nearby list")
        .accessibilityHint("Swipe up to expand, swipe down to collapse")
        .accessibilityAddTraits(.isButton)
    }

    private func nearestDetent(toHeight height: CGFloat, available: CGFloat) -> RadarSheetDetent {
        RadarSheetDetent.allCases.min { a, b in
            abs(available * a.fraction - height) < abs(available * b.fraction - height)
        } ?? detent
    }
}
