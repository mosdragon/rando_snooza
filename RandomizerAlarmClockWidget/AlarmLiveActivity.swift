//
//  AlarmLiveActivity.swift
//  RandomizerAlarmClockWidget
//
//  The non-alerting presentations for an alarm: Lock Screen / StandBy, and the Dynamic
//  Island. In practice what gets seen here is the snooze countdown.
//
//  `AlarmAttributes` conforms to ActivityAttributes and its ContentState is an
//  `AlarmPresentationState`, so `context.attributes` is what the app passed to AlarmKit
//  (static: label, tint, button text) and `context.state` is what the system maintains
//  (dynamic: current mode, fire date).
//

import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

struct AlarmLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RandomizerAlarmMetadata>.self) { context in
            lockScreenView(context)
                .padding()
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(for: context.state.mode))
                        .font(.title2)
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    statusText(context)
                        .font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(label(context))
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: icon(for: context.state.mode))
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                statusText(context)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: icon(for: context.state.mode))
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    // MARK: - Lock Screen / StandBy

    @ViewBuilder
    private func lockScreenView(
        _ context: ActivityViewContext<AlarmAttributes<RandomizerAlarmMetadata>>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon(for: context.state.mode))
                .font(.title)
                .foregroundStyle(context.attributes.tintColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(label(context))
                    .font(.headline)
                Text(subtitle(for: context.state.mode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusText(context)
                .font(.title2.monospacedDigit())
        }
    }

    /// `AlarmAttributes.metadata` is declared `Metadata?`, so every read has to unwrap.
    /// Falling back to a generic title keeps the widget rendering rather than showing
    /// nothing if the metadata ever arrives empty.
    private func label(
        _ context: ActivityViewContext<AlarmAttributes<RandomizerAlarmMetadata>>
    ) -> String {
        context.attributes.metadata?.label ?? "Alarm"
    }

    // MARK: - Mode-driven pieces
    //
    // `AlarmPresentationState.Mode` has three cases — alert, countdown, paused — each
    // carrying a payload. A plain `default` rather than `@unknown default` keeps this
    // compiling whether or not the enum is frozen.

    @ViewBuilder
    private func statusText(
        _ context: ActivityViewContext<AlarmAttributes<RandomizerAlarmMetadata>>
    ) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            // Live-updating countdown to the moment the alarm rings again.
            Text(countdown.fireDate, style: .timer)
        case .paused:
            Text("Paused")
        default:
            Text("Now")
        }
    }

    private func icon(for mode: AlarmPresentationState.Mode) -> String {
        switch mode {
        case .countdown: return "zzz"
        case .paused: return "pause.circle.fill"
        default: return "alarm.fill"
        }
    }

    private func subtitle(for mode: AlarmPresentationState.Mode) -> String {
        switch mode {
        case .countdown: return "Snoozed — ringing again in"
        case .paused: return "Paused"
        default: return "Alarm"
        }
    }
}
