import SwiftUI
import SwiftData
import UserNotifications

@main
struct WorkTrackApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationManager = NotificationManager.shared

    let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            WorkTask.self,
            ProgressLog.self,
            RoutineReminderRule.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("无法初始化 WorkTrack SwiftData 容器: \(error)")
        }
        self.sharedModelContainer = container

        Self.seedDefaultDataIfNeeded(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(notificationManager)
                .task {
                    notificationManager.bindModelContainer(sharedModelContainer)
                    notificationManager.registerNotificationCategories()
                    _ = await notificationManager.requestPermissionIfNeeded()
                    await syncNotificationsFromMainContext()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { @MainActor in
                            await notificationManager.refreshAuthorizationStatus()
                            await syncNotificationsFromMainContext()
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func syncNotificationsFromMainContext() async {
        let context = sharedModelContainer.mainContext
        let tasks = (try? context.fetch(FetchDescriptor<WorkTask>())) ?? []
        let routines = (try? context.fetch(FetchDescriptor<RoutineReminderRule>())) ?? []
        await notificationManager.syncAllNotifications(tasks: tasks, routines: routines)
    }

    @MainActor
    private static func seedDefaultDataIfNeeded(in context: ModelContext) {
        let existingRoutines = (try? context.fetch(FetchDescriptor<RoutineReminderRule>())) ?? []
        if existingRoutines.isEmpty {
            let morningRule = RoutineReminderRule(
                title: "早间工作待办汇总",
                note: DailyRoutineKind.morningSummary.defaultPrompt,
                kind: .morningSummary,
                hour: 9,
                minute: 0,
                weekdays: [2, 3, 4, 5, 6],
                isEnabled: true
            )
            let eveningRule = RoutineReminderRule(
                title: "晚间工作复盘与结果核对",
                note: DailyRoutineKind.eveningReview.defaultPrompt,
                kind: .eveningReview,
                hour: 18,
                minute: 30,
                weekdays: [2, 3, 4, 5, 6],
                isEnabled: true
            )
            context.insert(morningRule)
            context.insert(eveningRule)
            try? context.save()
        }
    }
}
