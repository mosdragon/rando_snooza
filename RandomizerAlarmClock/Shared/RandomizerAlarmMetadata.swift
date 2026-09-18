//
//  RandomizerAlarmMetadata.swift
//  RandomizerAlarmClock
//
//  SHARED BETWEEN THE APP AND THE WIDGET EXTENSION — see project.yml, where this single
//  file is listed in both targets' sources. The widget receives the same
//  `AlarmAttributes<RandomizerAlarmMetadata>` the app passes to AlarmManager, so both sides
//  must compile the identical type.
//
//  AlarmMetadata is "custom content or other information" for the alarm UI, and may be
//  empty. Carrying the label here rather than reading it back out of the presentation is
//  deliberate: `AlarmPresentation.Alert.title` is a `LocalizedStringResource`, which is
//  awkward to render in a widget, whereas this is a plain String.
//

import AlarmKit
import Foundation

struct RandomizerAlarmMetadata: AlarmMetadata {
    /// The alarm's user-facing label, for the Live Activity / Dynamic Island presentations.
    let label: String

    init(label: String = "Alarm") {
        self.label = label
    }
}
