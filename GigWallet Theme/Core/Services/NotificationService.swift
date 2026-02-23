import Foundation
import UserNotifications

/// Manages push notifications for tax deadlines, earnings summaries, and deduction alerts
enum NotificationService {

    // MARK: - Permission

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            #if DEBUG
            print("Notification permission error: \(error)")
            #endif
            return false
        }
    }

    static func checkPermission() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Tax Deadline Reminders

    /// Schedules reminders for all upcoming quarterly tax deadlines
    /// Call this on app launch and whenever tax data changes
    static func scheduleQuarterlyReminders(estimatedPayment: Double, year: Int) {
        let center = UNUserNotificationCenter.current()

        // Remove old quarterly reminders
        center.removePendingNotificationRequests(withIdentifiers:
            TaxQuarter.allCases.flatMap { quarter in
                [30, 14, 7, 1].map { "tax-\(quarter.rawValue)-\($0)d" }
            }
        )

        guard estimatedPayment > 0 else { return }

        for quarter in TaxQuarter.allCases {
            let dueDate = DateHelper.quarterDueDate(quarter: quarter, year: year)

            // Schedule at 30, 14, 7, and 1 day(s) before
            for daysBeforeCount in [30, 14, 7, 1] {
                guard let reminderDate = Calendar.current.date(byAdding: .day, value: -daysBeforeCount, to: dueDate) else { continue }
                guard reminderDate > Date.now else { continue } // Don't schedule past reminders

                let content = UNMutableNotificationContent()
                content.sound = .default

                let formattedAmount = CurrencyFormatter.format(estimatedPayment)
                if daysBeforeCount == 1 {
                    content.title = "Tax Payment Due Tomorrow!"
                    content.body = "\(quarter.shortName) estimated tax payment of \(formattedAmount) is due tomorrow."
                    content.interruptionLevel = .timeSensitive
                } else {
                    content.title = "\(quarter.shortName) Tax Due in \(daysBeforeCount) Days"
                    content.body = "Your estimated payment of \(formattedAmount) is due \(quarter.dueDescription)."
                }

                // Schedule for 9 AM on the reminder date
                var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: reminderDate)
                dateComponents.hour = 9
                dateComponents.minute = 0

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "tax-\(quarter.rawValue)-\(daysBeforeCount)d",
                    content: content,
                    trigger: trigger
                )

                center.add(request)
            }
        }
    }

    // MARK: - Weekly Earnings Summary

    /// Schedules a weekly earnings summary notification for Sunday at 7 PM
    static func scheduleWeeklyEarningsSummary(weeklyEarnings: Double, platformCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-summary"])

        guard weeklyEarnings > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Weekly Earnings Summary"
        content.body = "You earned \(CurrencyFormatter.format(weeklyEarnings)) this week across \(platformCount) platform\(platformCount == 1 ? "" : "s"). Keep it up!"
        content.sound = .default

        // Sunday at 7 PM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 19

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "weekly-summary", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Goal Progress

    /// Schedules a mid-week goal check notification (Wednesday 6 PM)
    static func scheduleGoalReminder(currentEarnings: Double, weeklyGoal: Double) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["goal-check"])

        guard weeklyGoal > 0 else { return }

        let progress = currentEarnings / weeklyGoal
        let remaining = max(weeklyGoal - currentEarnings, 0)

        let content = UNMutableNotificationContent()
        content.sound = .default

        if progress >= 1.0 {
            content.title = "Weekly Goal Reached!"
            content.body = "You've hit your \(CurrencyFormatter.format(weeklyGoal)) earnings goal. Great work!"
        } else {
            content.title = "Earnings Goal: \(Int(progress * 100))% Complete"
            content.body = "You need \(CurrencyFormatter.format(remaining)) more to hit your weekly goal. You've got this!"
        }

        // Wednesday at 6 PM
        var dateComponents = DateComponents()
        dateComponents.weekday = 4 // Wednesday
        dateComponents.hour = 18

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "goal-check", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - 1099-K Threshold Alert

    static func schedule1099KAlert(currentIncome: Double, platform: String? = nil) {
        let center = UNUserNotificationCenter.current()
        let threshold = TaxEngine.TaxConstants.form1099KThreshold
        let remaining = threshold - currentIncome

        guard remaining > 0 && remaining < 1000 else { return }

        let content = UNMutableNotificationContent()
        content.title = "1099-K Threshold Alert"
        let platformText = platform != nil ? " on \(platform!)" : ""
        content.body = "You're \(CurrencyFormatter.format(remaining)) away from the \(CurrencyFormatter.format(threshold)) 1099-K reporting threshold\(platformText)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "1099k-alert",
            content: content,
            trigger: nil // Deliver immediately
        )
        center.add(request)
    }

    // MARK: - Remove All

    static func removeAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
