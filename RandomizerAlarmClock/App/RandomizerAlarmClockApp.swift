//
//  RandomizerAlarmClockApp.swift
//  RandomizerAlarmClock
//

import SwiftUI
import SwiftData

@main
struct RandomizerAlarmClockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Alarm.self, AudioFile.self)
        } catch {
            fatalError("Could not create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    appDelegate.modelContext = modelContainer.mainContext
                    AlarmScheduler.requestAuthorizationIfNeeded()
                }
        }
        .modelContainer(modelContainer)
    }
}
