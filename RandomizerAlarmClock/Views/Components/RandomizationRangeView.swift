//
//  RandomizationRangeView.swift
//  RandomizerAlarmClock
//
//  Pitch shift and playback speed range controls for an alarm being edited.
//

import SwiftUI

struct RandomizationRangeView: View {
    @Bindable var alarm: Alarm

    private let pitchBounds: ClosedRange<Float> = -300...300
    private let speedBounds: ClosedRange<Float> = 0.75...1.25

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pitch shift")
                    Spacer()
                    Text("\(alarm.pitchMinCents.asPitchLabel) to \(alarm.pitchMaxCents.asPitchLabel) cents")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                RangeSlider(lowValue: $alarm.pitchMinCents, highValue: $alarm.pitchMaxCents, bounds: pitchBounds)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Playback speed")
                    Spacer()
                    Text("\(alarm.speedMin.asSpeedLabel) to \(alarm.speedMax.asSpeedLabel)")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                RangeSlider(lowValue: $alarm.speedMin, highValue: $alarm.speedMax, bounds: speedBounds)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Randomization")
        } footer: {
            Text("Each time this alarm fires, a random sound from its pool plays at a random pitch and speed within these ranges.")
        }
    }
}
