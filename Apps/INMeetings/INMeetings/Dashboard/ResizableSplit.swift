import SwiftUI
import AppKit
import INMeetingsCore

/// A reusable two-pane splitter with a draggable handle. Persists the FIRST pane's fraction of the
/// container via an injected `@AppStorage` key, so divider positions survive relaunch. Chrome stays
/// LTR (the divider math is not RTL-mirrored); only pane *content* may be RTL. The clamp math lives in
/// Core (`SplitLayout`) and is unit-tested.
struct ResizableSplit<First: View, Second: View>: View {
    enum Axis { case horizontal, vertical }

    private let axis: Axis
    private let min0: Double
    private let min1: Double
    private let first: First
    private let second: Second
    @AppStorage private var fraction: Double
    @State private var dragStartFraction: Double?
    @State private var isCursorPushed = false

    private let handleThickness: Double = 7

    init(axis: Axis, min0: Double, min1: Double, storageKey: String, defaultFraction: Double,
         @ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
        self.axis = axis
        self.min0 = min0
        self.min1 = min1
        self.first = first()
        self.second = second()
        _fraction = AppStorage(wrappedValue: defaultFraction, storageKey)
    }

    var body: some View {
        GeometryReader { geo in
            let total = axis == .horizontal ? geo.size.width : geo.size.height
            let f = SplitLayout.clampFraction(fraction, total: total, min0: min0, min1: min1,
                                              divider: handleThickness)
            let firstLen = SplitLayout.firstLength(fraction: f, total: total, divider: handleThickness)
            Group {
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        first.frame(width: firstLen).frame(maxHeight: .infinity)
                        handle(total: total, current: f)
                        second.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        first.frame(height: firstLen).frame(maxWidth: .infinity)
                        handle(total: total, current: f)
                        second.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func handle(total: Double, current: Double) -> some View {
        let isH = axis == .horizontal
        ZStack {
            Rectangle().fill(.clear)
            Capsule().fill(.secondary.opacity(0.35))
                .frame(width: isH ? 2 : 28, height: isH ? 28 : 2)
        }
        .frame(width: isH ? handleThickness : nil, height: isH ? nil : handleThickness)
        .frame(maxWidth: isH ? nil : .infinity, maxHeight: isH ? .infinity : nil)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                if !isCursorPushed {
                    (isH ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                    isCursorPushed = true
                }
            } else if isCursorPushed {
                NSCursor.pop()
                isCursorPushed = false
            }
        }
        .onDisappear {
            if isCursorPushed { NSCursor.pop(); isCursorPushed = false }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let usable = max(total - handleThickness, 1)
                    if dragStartFraction == nil { dragStartFraction = current }
                    let startLen = (dragStartFraction ?? current) * usable
                    let delta = isH ? value.translation.width : value.translation.height
                    fraction = SplitLayout.clampFraction((startLen + delta) / usable,
                                                         total: total, min0: min0, min1: min1,
                                                         divider: handleThickness)
                }
                .onEnded { _ in dragStartFraction = nil }
        )
    }
}
