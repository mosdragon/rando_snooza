//
//  AlarmWidgetBundle.swift
//  RandomizerAlarmClockWidget
//
//  This extension exists for ONE reason: snooze. Snooze is AlarmKit's `.countdown`
//  secondary-button behavior, and while an alarm is snoozed it shows its *countdown*
//  presentation — which Apple says requires a widget extension:
//
//    "AlarmKit expects a widget extension if an app supports a countdown presentation.
//     Otherwise, the system may unexpectedly dismiss alarms and fail to alert."
//
//  Nothing here calls Activity.request(). AlarmManager.schedule(id:configuration:) creates
//  the Live Activity and the system owns its content state; this target only supplies views.
//

import SwiftUI
import WidgetKit

@main
struct AlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlarmLiveActivity()
    }
}
