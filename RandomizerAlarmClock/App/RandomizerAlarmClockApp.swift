//
//  RandomizerAlarmClockApp.swift
//  RandomizerAlarmClock
//

import SwiftUI
import SwiftData
import os

@main
struct RandomizerAlarmClockApp: App {

    private static let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "app")

    /// Static so anything outside the view tree can reach the SwiftData context without
    /// waiting for a view's `onAppear`.
    static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Alarm.self, AudioFile.self)
        } catch {
            RandomizerAlarmClockApp.log.fault("Could not create SwiftData ModelContainer: \(error.localizedDescription, privacy: .public)")
            fatalError("Could not create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    // Ask up front so the first alarm a user saves isn't racing the prompt.
                    await AlarmKitScheduler.requestAuthorization()
                    AlarmKitScheduler.logScheduledSummary()
                    Self.log.info("Bundled alarm sounds available: \(BundledAlarmSound.all.count)")
                }
                .task {
                    // Long-lived: runs for as long as this scene is alive.
                    await AlarmKitScheduler.observeAlarmUpdates()
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }
}
