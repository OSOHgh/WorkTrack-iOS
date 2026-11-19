import Combine
import Foundation
import SwiftData
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // MARK: - Notification Constants

    static let taskCategoryIdentifier = "WORKTRACK_TASK_REMINDER"
    static let routineCategoryIdentifier = "WORKTRACK_ROUTINE_REMINDER"

    static let actionQuickLog = "ACTION_QUICK_LOG"
    static let actionSnoozeOneHour = "ACTION_SNOOZE_1H"
    static let actionFollowUpTomorrow = "ACTION_FOLLOWUP_TOMORROW"
    static let actionCompleteArchive = "ACTION_COMPLETE_ARCHIVE"
    static let actionOpenApp = "ACTION_OPEN_APP"

    private static let requestPrefix = "worktrack."
    private static let lastCertRefreshKey = "worktrack.lastCertRefreshDate"
    private static let certExpiryWarningKey = "worktrack.certExpiryWarningEnabled"
    private static let maxManagedTaskNotifications = 62

    // MARK: - Published State

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var pendingRequestCount: Int = 0

    @Published var lastCertificateRefreshDate: Date {
        didSet {
            UserDefaults.standard.set(lastCertificateRefreshDate.timeIntervalSince1970, forKey: Self.lastCertRefreshKey)
        }
    }

    @Published var certExpiryWarningEnabled: Bool {
        didSet {
            UserDefaults.standard.set(certExpiryWarningEnabled, forKey: Self.certExpiryWarningKey)
            Task { @MainActor in
                await resyncFromBoundContainer()
            }
        }
    }

    @Published var pendingDeepLinkTaskID: UUID? = nil

    // MARK: - Dependencies

    private var modelContainer: ModelContainer?

    // MARK: - Initialization

    override private init() {
        let defaults = UserDefaults.standard
        if let savedTimestamp = defaults.object(forKey: Self.lastCertRefreshKey) as? Double, savedTimestamp > 0 {
            self.lastCertificateRefreshDate = Date(timeIntervalSince1970: savedTimestamp)
        } else {
            let initialDate = Date()
            self.lastCertificateRefreshDate = initialDate
            defaults.set(initialDate.timeIntervalSince1970, forKey: Self.lastCertRefreshKey)
        }

        if defaults.object(forKey: Self.certExpiryWarningKey) != nil {
            self.certExpiryWarningEnabled = defaults.bool(forKey: Self.certExpiryWarningKey)
        } else {
            self.certExpiryWarningEnabled = true
            defaults.set(true, forKey: Self.certExpiryWarningKey)
        }

        super.init()

        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
    }

    // MARK: - 7-Day Free Sideload Certificate Helpers

    var nextCertExpiryDate: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: lastCertificateRefreshDate)
            ?? lastCertificateRefreshDate.addingTimeInterval(7 * 86_400)
    }

    var daysRemainingUntilCertExpiry: Int {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let expiryStart = calendar.startOfDay(for: nextCertExpiryDate)
        let rawDays = calendar.dateComponents([.day], from: todayStart, to: expiryStart).day ?? 0
        return min(7, max(0, rawDays))
    }

    func markCertificateRefreshedToday() {
        lastCertificateRefreshDate = Date()
        Task { @MainActor in
            await resyncFromBoundContainer()
        }
    }

    // MARK: - Container Binding & Permission

    func bindModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
    }

    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                let updatedSettings = await center.notificationSettings()
                authorizationStatus = updatedSettings.authorizationStatus
                return granted
            } catch {
                await refreshAuthorizationStatus()
                return false
            }
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        let pending = await center.pendingNotificationRequests()
        pendingRequestCount = pending.filter { $0.identifier.hasPrefix(Self.requestPrefix) }.count
    }

    func registerNotificationCategories() {
        let quickLogAction = UNTextInputNotificationAction(
            identifier: Self.actionQuickLog,
            title: "快速记进展",
            options: [],
            textInputButtonTitle: "保存进展",
            textInputPlaceholder: "输入当前工作推进情况..."
        )

        let snoozeAction = UNNotificationAction(
            identifier: Self.actionSnoozeOneHour,
            title: "延后1小时提醒",
            options: []
        )

        let followUpTomorrowAction = UNNotificationAction(
            identifier: Self.actionFollowUpTomorrow,
            title: "明早09:30继续追踪",
            options: []
        )

        let completeArchiveAction = UNNotificationAction(
            identifier: Self.actionCompleteArchive,
            title: "标记完成并归档",
            options: [.authenticationRequired]
        )

        let taskCategory = UNNotificationCategory(
            identifier: Self.taskCategoryIdentifier,
            actions: [
                quickLogAction,
                snoozeAction,
                followUpTomorrowAction,
                completeArchiveAction
            ],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let openAppAction = UNNotificationAction(
            identifier: Self.actionOpenApp,
            title: "打开 WorkTrack 盘点",
            options: [.foreground]
        )

        let routineCategory = UNNotificationCategory(
            identifier: Self.routineCategoryIdentifier,
            actions: [openAppAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([taskCategory, routineCategory])
    }

    // MARK: - 64-Slot Sliding Window Scheduler

    private struct CandidateTaskNotification {
        let identifier: String
        let taskID: UUID
        let fireDate: Date
        let title: String
        let subtitle: String
        let body: String
    }

    func syncAllNotifications(tasks: [WorkTask], routines: [RoutineReminderRule]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        // 1. Clear old worktrack.* managed pending requests
        let existingRequests = await center.pendingNotificationRequests()
        let managedIdentifiers = existingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.requestPrefix) }
        if !managedIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: managedIdentifiers)
        }

        let isAllowedToSchedule: Bool = {
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return true
            default:
                return false
            }
        }()

        guard isAllowedToSchedule else {
            pendingRequestCount = 0
            return
        }

        var usedSlots = 0
        let now = Date()
        let calendar = Calendar.current

        // 2. Schedule enabled RoutineReminderRule items (Morning Summary / Evening Review / Custom)
        for rule in routines where rule.isEnabled {
            let validWeekdays = Array(Set(rule.weekdays.filter { (1...7).contains($0) })).sorted()
            for weekday in validWeekdays {
                guard usedSlots < Self.maxManagedTaskNotifications else { break }

                let content = UNMutableNotificationContent()
                content.title = rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? rule.kind.displayName
                    : rule.title
                content.subtitle = rule.kind.displayName
                content.body = rule.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? rule.kind.defaultPrompt
                    : rule.note
                content.sound = .default
                content.categoryIdentifier = Self.routineCategoryIdentifier
                content.userInfo = [
                    "routineID": rule.id.uuidString,
                    "routineKind": rule.kind.rawValue
                ]

                var dateComponents = DateComponents()
                dateComponents.hour = max(0, min(23, rule.hour))
                dateComponents.minute = max(0, min(59, rule.minute))
                dateComponents.weekday = weekday

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let identifier = "\(Self.requestPrefix)routine.\(rule.id.uuidString).w\(weekday)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                do {
                    try await center.add(request)
                    usedSlots += 1
                } catch {
                    continue
                }
            }
        }

        // 3. Schedule Day 5 & Day 6 Sideload Certificate Renewal Reminders
        if certExpiryWarningEnabled {
            for dayOffset in [5, 6] {
                guard usedSlots < Self.maxManagedTaskNotifications else { break }
                guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: lastCertificateRefreshDate) else {
                    continue
                }

                let preferredMorning = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: targetDay) ?? targetDay
                let fireDate = preferredMorning > now ? preferredMorning : targetDay
                guard fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                if dayOffset == 5 {
                    content.title = "自签证书还有 2 天到期"
                    content.subtitle = "WorkTrack 证书续期提醒"
                    content.body = "建议在 Wi-Fi 下打开 SideStore 或连接电脑 Sideloadly 刷新 7 天签名，确保待办提醒持续生效。"
                } else {
                    content.title = "⚠️ 自签证书明天到期"
                    content.subtitle = "WorkTrack 证书紧急提醒"
                    content.body = "签名仅剩最后 1 天！请今日完成续签，或在设置页导出全量本地备份以防过期。"
                }
                content.sound = .default
                content.categoryIdentifier = Self.routineCategoryIdentifier
                content.userInfo = ["certWarningDay": dayOffset]

                let triggerComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
                let identifier = "\(Self.requestPrefix)cert.day\(dayOffset)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                do {
                    try await center.add(request)
                    usedSlots += 1
                } catch {
                    continue
                }
            }
        }

        // 4. Collect all future candidate task notifications across active tasks
        var candidates: [CandidateTaskNotification] = []

        for task in tasks where task.status.isActive {
            let categoryLabel = task.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "工作待办"
                : task.categoryTag

            if let dueDate = task.dueDate, dueDate > now {
                let descriptionText = task.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let bodyText = descriptionText.isEmpty
                    ? "该工作待办已到达截止时间，请记录最新结果或安排后续跟进。"
                    : descriptionText

                candidates.append(
                    CandidateTaskNotification(
                        identifier: "\(Self.requestPrefix)task.\(task.id.uuidString).due",
                        taskID: task.id,
                        fireDate: dueDate,
                        title: task.title,
                        subtitle: "待办到期提醒 · \(categoryLabel)",
                        body: bodyText
                    )
                )
            }

            if let nextFollowUp = task.nextFollowUpAt, nextFollowUp > now {
                let summaryText = task.outcomeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                let bodyText = summaryText.isEmpty
                    ? "已到达预设复追时间，请推进「\(task.title)」并记录最新进展或归档。"
                    : "阶段结果跟进：\(summaryText)"

                candidates.append(
                    CandidateTaskNotification(
                        identifier: "\(Self.requestPrefix)task.\(task.id.uuidString).followup",
                        taskID: task.id,
                        fireDate: nextFollowUp,
                        title: task.title,
                        subtitle: "需要继续追踪 · \(categoryLabel)",
                        body: bodyText
                    )
                )
            }

            for item in task.customFollowUpSchedules where !item.isCompleted && item.scheduledAt > now {
                let subtitleText = item.isOverdueRetry ? "逾期未处理复追提醒" : "自定义追踪提醒"
                let trimmedNote = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
                let bodyText = trimmedNote.isEmpty
                    ? "请及时跟进「\(task.title)」（\(categoryLabel)）并更新当前工作进展。"
                    : "\(trimmedNote) —— \(task.title)"

                candidates.append(
                    CandidateTaskNotification(
                        identifier: "\(Self.requestPrefix)task.\(task.id.uuidString).custom.\(item.id.uuidString)",
                        taskID: task.id,
                        fireDate: item.scheduledAt,
                        title: task.title,
                        subtitle: subtitleText,
                        body: bodyText
                    )
                )
            }
        }

        // 5. Sort chronologically & schedule up to max(0, 62 - usedSlots) soonest notifications
        candidates.sort { $0.fireDate < $1.fireDate }
        let availableTaskSlots = max(0, Self.maxManagedTaskNotifications - usedSlots)

        for candidate in candidates.prefix(availableTaskSlots) {
            let content = UNMutableNotificationContent()
            content.title = candidate.title
            content.subtitle = candidate.subtitle
            content.body = candidate.body
            content.sound = .default
            content.categoryIdentifier = Self.taskCategoryIdentifier
            content.userInfo = ["taskID": candidate.taskID.uuidString]

            let triggerComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: candidate.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: candidate.identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
                usedSlots += 1
            } catch {
                continue
            }
        }

        // 6. Update pendingRequestCount & application icon badge count
        let updatedPending = await center.pendingNotificationRequests()
        pendingRequestCount = updatedPending.filter { $0.identifier.hasPrefix(Self.requestPrefix) }.count

        let badgeCount = tasks.filter { task in
            guard task.status.isActive else { return false }
            if task.isOverdue { return true }
            if let dueDate = task.dueDate, calendar.isDateInToday(dueDate) { return true }
            if let followUp = task.nextFollowUpAt, calendar.isDateInToday(followUp) { return true }
            return false
        }.count

        try? await center.setBadgeCount(badgeCount)
    }

    func resyncFromBoundContainer() async {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let tasks = (try? context.fetch(FetchDescriptor<WorkTask>())) ?? []
        let routines = (try? context.fetch(FetchDescriptor<RoutineReminderRule>())) ?? []
        await syncAllNotifications(tasks: tasks, routines: routines)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let userText = (response as? UNTextInputNotificationResponse)?.userText
        let taskIDString = response.notification.request.content.userInfo["taskID"] as? String

        await NotificationManager.shared.handleNotificationResponse(
            actionIdentifier: actionIdentifier,
            taskIDString: taskIDString,
            userText: userText
        )
    }

    // MARK: - Action Handling on MainActor

    private func handleNotificationResponse(
        actionIdentifier: String,
        taskIDString: String?,
        userText: String?
    ) async {
        guard let taskIDString, let taskUUID = UUID(uuidString: taskIDString) else {
            return
        }

        if actionIdentifier == UNNotificationDefaultActionIdentifier || actionIdentifier == Self.actionOpenApp {
            pendingDeepLinkTaskID = taskUUID
            return
        }

        guard let container = modelContainer else {
            pendingDeepLinkTaskID = taskUUID
            return
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<WorkTask>(
            predicate: #Predicate<WorkTask> { $0.id == taskUUID }
        )

        guard let task = try? context.fetch(descriptor).first else {
            return
        }

        switch actionIdentifier {
        case Self.actionQuickLog:
            let trimmed = (userText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let content = trimmed.isEmpty ? "通过系统通知快捷记录进展" : trimmed
            task.addProgressLog(content: content, type: .update)
            if task.status == .todo {
                task.status = .inProgress
            }

        case Self.actionSnoozeOneHour:
            let snoozeDate = Date().addingTimeInterval(3600)
            task.addManualFollowUp(
                at: snoozeDate,
                note: "通知快捷延后 1 小时提醒",
                isOverdueRetry: true
            )

        case Self.actionFollowUpTomorrow:
            let calendar = Calendar.current
            let tomorrowBase = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
            let tomorrowMorning = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: tomorrowBase) ?? tomorrowBase
            task.nextFollowUpAt = tomorrowMorning
            task.status = .followUp
            task.updatedAt = Date()
            task.addProgressLog(content: "通过系统通知设置明早 09:30 继续追踪", type: .followUpNote)

        case Self.actionCompleteArchive:
            let existingOutcome = task.outcomeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let summaryToSave = existingOutcome.isEmpty ? "通过系统通知快捷完成并归档" : task.outcomeSummary
            task.recordOutcome(
                summary: summaryToSave,
                needsContinuedTracking: false
            )

        default:
            pendingDeepLinkTaskID = taskUUID
        }

        try? context.save()
        await resyncFromBoundContainer()
    }
}
