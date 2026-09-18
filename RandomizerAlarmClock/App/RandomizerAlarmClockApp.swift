//
//  RandomizerAlarmClockApp.swift
//  RandomizerAlarmClock
//

import SwiftUI
import SwiftData
import os

@main
struct RandomizerAlarmClockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private static let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "app")

    /// Static so `AppDelegate` can reach the SwiftData context the moment a notification
    /// arrives — including a cold launch from tapping one, where the delegate callback can
    /// run before any SwiftUI view's `onAppear`.
    static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Alarm.self, AudioFile.self)
        } catch {
            RandomizerAlarmClockApp.log.fault("Could not create SwiftData ModelContainer: \(error.localizedDescription, privacy: .public)")
            fatalError("Could not create SwiftData ModelContainer: \(error)")
        }
    }()

    init() {
        // Ask for permission as early as possible so the first alarm a user saves is
        // scheduled against an already-granted authorization rather than racing it.
        AlarmScheduler.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    AlarmScheduler.logPendingSummary()
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }
}
