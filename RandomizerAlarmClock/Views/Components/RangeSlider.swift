//
//  RangeSlider.swift
//  RandomizerAlarmClock
//
//  A simple two-thumb slider for picking a min/max range within bounds. SwiftUI has no
//  built-in equivalent, so this is a small custom control built on GeometryReader + DragGesture.
//

import SwiftUI

struct RangeSlider: View {
    @Binding var lowValue: Float
    @Binding var highValue: Float
    let bounds: ClosedRange<Float>

    private let trackHeight: CGFloat = 4
    private let thumbDiameter: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let lowX = position(for: lowValue, width: width)
            let highX = position(for: highValue, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, highX - lowX), height: trackHeight)
                    .offset(x: lowX)

                thumb(atX: lowX) { dragX in
                    let value = clampedValue(for: dragX, width: width)
                    lowValue = min(value, highValue)
                }

                thumb(atX: highX) { dragX in
                    let value = clampedValue(for: dragX, width: width)
                    highValue = max(value, lowValue)
                }
            }
            .frame(height: thumbDiameter)
        }
        .frame(height: thumbDiameter)
    }

    private func thumb(atX x: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(radius: 2, y: 1)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .offset(x: x - thumbDiameter / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        onDrag(drag.location.x)
                    }
            )
    }

    private func position(for value: Float, width: CGFloat) -> CGFloat {
        guard bounds.upperBound > bounds.lowerBound else { return 0 }
        let fraction = CGFloat((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
        return min(max(fraction, 0), 1) * width
    }

    private func clampedValue(for x: CGFloat, width: CGFloat) -> Float {
        guard width > 0 else { return bounds.lowerBound }
        let fraction = min(max(x / width, 0), 1)
        return bounds.lowerBound + Float(fraction) * (bounds.upperBound - bounds.lowerBound)
    }
}

#Preview {
    RangeSlider(lowValue: .constant(-200), highValue: .constant(200), bounds: -300...300)
        .padding()
}
