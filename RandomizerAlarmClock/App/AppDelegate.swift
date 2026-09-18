//
//  AppDelegate.swift
//  RandomizerAlarmClock
//
//  Handles notification presentation while the app is foregrounded, and reschedules
//  a repeating alarm's next batch of occurrences after one of its notifications fires.
//

import UIKit
import UserNotifications
import SwiftData
import os

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "delegate")

    /// Always resolves, even on a cold launch from a notification tap, because it reads the
    /// app-wide container rather than waiting for a view's `onAppear` to hand one over.
    @MainActor
    private var modelContext: ModelContext {
        RandomizerAlarmClockApp.sharedModelContainer.mainContext
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must be set before the app finishes launching, or a notification that arrives
        // during launch is never routed to this delegate.
        UNUserNotificationCenter.current().delegate = self
        // Categories must be registered before any notification is delivered, or iOS shows
        // the alarm with no Stop / Snooze actions attached.
        AlarmScheduler.registerNotificationCategories()
        log.info("Notification center delegate installed.")
        return true
    }

    /// Alarm fired while the app was in the foreground: still show the alert/sound rather
    /// than silently swallowing it, then reschedule.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        log.info("willPresent: \(notification.request.identifier, privacy: .public)")
        handleAlarmUserInfo(notification.request.content.userInfo)
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// User tapped/dismissed the notification (app was backgrounded or terminated).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        log.info("didReceive: \(response.notification.request.identifier, privacy: .public), action: \(response.actionIdentifier, privacy: .public)")

        let userInfo = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case AlarmScheduler.snoozeActionIdentifier:
            if let alarmID = userInfo["alarmID"] as? String {
                Task { @MainActor in
                    AlarmScheduler.snooze(alarmID: alarmID, in: modelContext)
                    AlarmScheduler.handleFired(alarmID: alarmID, in: modelContext)
                }
            }
        default:
            // Stop, tap-to-open, and swipe-to-dismiss all resolve the same way: the alarm
            // is done, so top the repeating schedule back up (or retire a one-shot).
            handleAlarmUserInfo(userInfo)
        }
        completionHandler()
    }

    private func handleAlarmUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let alarmID = userInfo["alarmID"] as? String else {
            log.info("Notification carried no alarmID (test firing?); nothing to reschedule.")
            return
        }
        Task { @MainActor in
            AlarmScheduler.handleFired(alarmID: alarmID, in: modelContext)
        }
    }
}
