import SwiftUI
import SwiftData

enum AppTab: Int, Hashable {
    case focus = 0
    case board = 1
    case archiveAndReport = 2
    case settings = 3
}

enum BoardQuickFilter: Equatable, Hashable {
    case allActive
    case todayFocus
    case overdue
    case status(TaskStatus)
}

struct BoardFilterRequest: Equatable {
    var id: UUID = UUID()
    var quickFilter: BoardQuickFilter
    var category: String? = nil
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query(sort: \WorkTask.updatedAt, order: .reverse) private var allTasks: [WorkTask]

    @State private var selectedTab: AppTab = .focus
    @State private var deepLinkedTask: WorkTask?
    @State private var boardFilterRequest: BoardFilterRequest? = nil

    private var overdueAndFollowUpCount: Int {
        allTasks.filter { $0.status.isActive && ($0.isOverdue || $0.status == .followUp) }.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FocusDashboardView { request in
                boardFilterRequest = request
                selectedTab = .board
            }
            .tabItem {
                Label("工作概况", systemImage: "chart.bar.doc.horizontal.fill")
            }
            .badge(overdueAndFollowUpCount > 0 ? overdueAndFollowUpCount : 0)
            .tag(AppTab.focus)

            TaskBoardView(externalFilterRequest: $boardFilterRequest)
                .tabItem {
                    Label("全部待办", systemImage: "rectangle.grid.1x2.fill")
                }
                .tag(AppTab.board)

            ArchiveAndReportView()
                .tabItem {
                    Label("归档与周报", systemImage: "archivebox.circle.fill")
                }
                .tag(AppTab.archiveAndReport)

            ReminderSettingsView()
                .tabItem {
                    Label("提醒与备份", systemImage: "bell.badge.fill")
                }
                .tag(AppTab.settings)
        }
        .tint(TaskTagColor.sky.swiftUIColor)
        .onChange(of: notificationManager.pendingDeepLinkTaskID, initial: true) { _, _ in
            resolvePendingDeepLinkIfNeeded()
        }
        .onChange(of: allTasks.count) { _, _ in
            resolvePendingDeepLinkIfNeeded()
        }
        .sheet(item: $deepLinkedTask) { task in
            NavigationStack {
                TaskDetailView(task: task)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                deepLinkedTask = nil
                            }
                        }
                    }
            }
        }
    }

    private func resolvePendingDeepLinkIfNeeded() {
        guard let targetID = notificationManager.pendingDeepLinkTaskID else { return }
        if let matched = allTasks.first(where: { $0.id == targetID }) {
            deepLinkedTask = matched
            notificationManager.pendingDeepLinkTaskID = nil
        }
    }
}
