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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Set by RandomizerAlarmClockApp once the SwiftData container exists.
    var modelContext: ModelContext?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Alarm fired while the app was in the foreground: still show the alert/sound rather
    /// than silently swallowing it, then reschedule.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handleAlarmUserInfo(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    /// User tapped/dismissed the notification (app was backgrounded or terminated).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleAlarmUserInfo(response.notification.request.content.userInfo)
        completionHandler()
    }

    private func handleAlarmUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let alarmID = userInfo["alarmID"] as? String, let context = modelContext else { return }
        AlarmScheduler.handleFired(alarmID: alarmID, in: context)
    }
}
