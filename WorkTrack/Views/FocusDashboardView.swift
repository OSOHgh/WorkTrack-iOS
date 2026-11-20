import SwiftUI
import SwiftData

struct FocusDashboardView: View {
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query(sort: \WorkTask.updatedAt, order: .reverse) private var allTasks: [WorkTask]
    @Query(sort: \RoutineReminderRule.hour, order: .forward) private var allRoutines: [RoutineReminderRule]

    var onNavigateToBoard: (BoardFilterRequest) -> Void = { _ in }

    @State private var showingNewTaskSheet: Bool = false
    @State private var showingCertRenewedToast: Bool = false

    // MARK: - Computed Overview Metrics

    private var activeTasks: [WorkTask] {
        allTasks.filter { $0.status.isActive }
    }

    private var overdueTasks: [WorkTask] {
        activeTasks.filter { $0.isOverdue }
    }

    private var followUpTasks: [WorkTask] {
        activeTasks.filter { $0.status == .followUp }
    }

    private var waitingTasks: [WorkTask] {
        activeTasks.filter { $0.status == .waiting }
    }

    private var archivedTasks: [WorkTask] {
        allTasks.filter { $0.status == .archived }
    }

    private var todayFocusCount: Int {
        let calendar = Calendar.current
        return activeTasks.filter { task in
            if task.isOverdue || task.status == .inProgress || task.status == .followUp {
                return true
            }
            if let due = task.dueDate, calendar.isDateInToday(due) {
                return true
            }
            if let nextFollow = task.nextFollowUpAt, calendar.isDateInToday(nextFollow) {
                return true
            }
            if task.customFollowUpSchedules.contains(where: { !$0.isCompleted && calendar.isDateInToday($0.scheduledAt) }) {
                return true
            }
            return calendar.isDateInToday(task.createdAt)
        }.count
    }

    private var completionRatio: Double {
        let validTotal = activeTasks.count + archivedTasks.count
        guard validTotal > 0 else { return 0 }
        return Double(archivedTasks.count) / Double(validTotal)
    }

    private struct CategorySummary: Identifiable {
        let id: String
        let category: String
        let color: TaskTagColor
        let activeCount: Int
        let overdueCount: Int
    }

    private var categorySummaries: [CategorySummary] {
        let grouped = Dictionary(grouping: activeTasks) { task in
            let trimmed = task.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "日常工作" : trimmed
        }
        return grouped
            .map { key, items in
                CategorySummary(
                    id: key,
                    category: key,
                    color: items.first?.tagColor ?? .sky,
                    activeCount: items.count,
                    overdueCount: items.filter(\.isOverdue).count
                )
            }
            .sorted {
                if $0.activeCount != $1.activeCount {
                    return $0.activeCount > $1.activeCount
                }
                return $0.category < $1.category
            }
    }

    private struct UpcomingReminderSummary: Identifiable {
        let id = UUID()
        let taskTitle: String
        let date: Date
        let color: TaskTagColor
    }

    private var upcomingRemindersPreview: [UpcomingReminderSummary] {
        activeTasks
            .compactMap { task -> UpcomingReminderSummary? in
                guard let nextDate = task.upcomingReminderDates.first else { return nil }
                return UpcomingReminderSummary(
                    taskTitle: task.title,
                    date: nextDate,
                    color: task.tagColor
                )
            }
            .sorted { $0.date < $1.date }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        overviewHeaderCard
                        statusDistributionCard
                        if !categorySummaries.isEmpty {
                            categoryBreakdownCard
                        }
                        scheduleAndActionCard
                    }
                    .adaptiveScreenContainer()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("工作概况")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewTaskSheet = true
                    } label: {
                        Label("新建待办", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingNewTaskSheet) {
                TaskEditorSheet()
            }
        }
    }

    // MARK: - 1. Global Overview Header Card

    private var overviewHeaderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Date().formatted(.dateTime.month().day().weekday()))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("工作事项总概况")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        notificationManager.markCertificateRefreshedToday()
                        showingCertRenewedToast = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation {
                            showingCertRenewedToast = false
                        }
                    }
                } label: {
                    let daysLeft = notificationManager.daysRemainingUntilCertExpiry
                    let pillColor: Color = daysLeft <= 2 ? TaskTagColor.coral.swiftUIColor : TaskTagColor.teal.swiftUIColor
                    HStack(spacing: 5) {
                        Image(systemName: daysLeft <= 2 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                            .font(.caption2)
                        Text(showingCertRenewedToast ? "已重置 7 天" : "签名剩 \(daysLeft) 天")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(pillColor)
                    .background(
                        Capsule(style: .continuous)
                            .fill(pillColor.opacity(0.14))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(pillColor.opacity(0.35), lineWidth: 0.9)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 10)], spacing: 10) {
                tappableMetricTile(
                    title: "全部活动中",
                    value: "\(activeTasks.count)",
                    subtitle: "点击查看全部待办",
                    icon: "tray.full.fill",
                    color: TaskTagColor.sky.swiftUIColor
                ) {
                    onNavigateToBoard(BoardFilterRequest(quickFilter: .allActive))
                }

                tappableMetricTile(
                    title: "今日聚焦",
                    value: "\(todayFocusCount)",
                    subtitle: "到期或推进中",
                    icon: "sun.max.fill",
                    color: TaskTagColor.indigo.swiftUIColor
                ) {
                    onNavigateToBoard(BoardFilterRequest(quickFilter: .todayFocus))
                }

                tappableMetricTile(
                    title: "逾期未处理",
                    value: "\(overdueTasks.count)",
                    subtitle: overdueTasks.isEmpty ? "当前无逾期" : "点击立即处理",
                    icon: "exclamationmark.circle.fill",
                    color: TaskTagColor.coral.swiftUIColor
                ) {
                    onNavigateToBoard(BoardFilterRequest(quickFilter: .overdue))
                }

                tappableMetricTile(
                    title: "需继续追踪",
                    value: "\(followUpTasks.count)",
                    subtitle: "阶段结果跟进",
                    icon: "arrow.clockwise.circle.fill",
                    color: TaskTagColor.violet.swiftUIColor
                ) {
                    onNavigateToBoard(BoardFilterRequest(quickFilter: .status(.followUp)))
                }

                tappableMetricTile(
                    title: "等待外部反馈",
                    value: "\(waitingTasks.count)",
                    subtitle: "待对接回复",
                    icon: "hourglass.circle.fill",
                    color: TaskTagColor.amber.swiftUIColor
                ) {
                    onNavigateToBoard(BoardFilterRequest(quickFilter: .status(.waiting)))
                }

                metricDisplayTile(
                    title: "累计已归档",
                    value: "\(archivedTasks.count)",
                    subtitle: "闭环率 \(Int((completionRatio * 100).rounded()))%",
                    icon: "checkmark.seal.fill",
                    color: TaskTagColor.emerald.swiftUIColor
                )
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.sky.swiftUIColor)
    }

    private func tappableMetricTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            metricDisplayTile(title: title, value: value, subtitle: subtitle, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }

    private func metricDisplayTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(color.opacity(0.24), lineWidth: 0.8)
                )
        )
    }

    // MARK: - 2. Status Distribution Overview Card

    private var statusDistributionCard: some View {
        let totalValid = max(1, activeTasks.count + archivedTasks.count)
        let statusesToDisplay: [TaskStatus] = [.todo, .inProgress, .waiting, .followUp, .archived]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("事项状态分布概况", systemImage: "chart.pie.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TaskTagColor.indigo.swiftUIColor)
                Spacer()
                Text("共 \(activeTasks.count + archivedTasks.count) 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("整体完成归档率")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((completionRatio * 100).rounded()))%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                        Capsule()
                            .fill(TaskTagColor.emerald.gradient)
                            .frame(width: max(8, geo.size.width * completionRatio), height: 8)
                    }
                }
                .frame(height: 8)
            }

            VStack(spacing: 8) {
                ForEach(statusesToDisplay) { status in
                    let count = allTasks.filter { $0.status == status }.count
                    let ratio = Double(count) / Double(totalValid)

                    let rowContent = HStack(spacing: 10) {
                        Image(systemName: status.systemImage)
                            .font(.caption)
                            .foregroundStyle(status.themeColor)
                            .frame(width: 18)

                        Text(status.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 72, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(status.themeColor.opacity(0.85))
                                    .frame(width: count > 0 ? max(8, geo.size.width * ratio) : 0, height: 6)
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 16)

                        Text("\(count) 项")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    if status.isActive {
                        Button {
                            onNavigateToBoard(BoardFilterRequest(quickFilter: .status(status)))
                        } label: {
                            rowContent
                        }
                        .buttonStyle(.plain)
                    } else {
                        rowContent
                    }
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.indigo.swiftUIColor)
    }

    // MARK: - 3. Category Breakdown Card

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("分类标签活动概况", systemImage: "tag.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TaskTagColor.teal.swiftUIColor)
                Spacer()
                Text("点击标签直达筛选")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            AdaptiveFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(categorySummaries) { item in
                    Button {
                        onNavigateToBoard(BoardFilterRequest(quickFilter: .allActive, category: item.category))
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.color.gradient)
                                .frame(width: 8, height: 8)
                            Text(item.category)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text("\(item.activeCount)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(item.color.swiftUIColor.opacity(0.18)))
                            if item.overdueCount > 0 {
                                Text("逾期\(item.overdueCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(TaskTagColor.coral.swiftUIColor)
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .foregroundStyle(.primary)
                        .background(
                            Capsule(style: .continuous)
                                .fill(item.color.swiftUIColor.opacity(0.10))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(item.color.swiftUIColor.opacity(0.28), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.teal.swiftUIColor)
    }

    // MARK: - 4. Schedule Overview & Direct Board Entry

    private var scheduleAndActionCard: some View {
        let enabledRoutinesCount = allRoutines.filter(\.isEnabled).count

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("近期提醒安排与快捷入口", systemImage: "bell.badge.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                Spacer()
                Text("队列 \(notificationManager.pendingRequestCount)/64")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("早晚定时盘点：\(enabledRoutinesCount) 条已启用", systemImage: "alarm")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if upcomingRemindersPreview.isEmpty {
                Text("近期暂无待触发的任务节点提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(upcomingRemindersPreview) { reminder in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(reminder.color.gradient)
                                .frame(width: 7, height: 7)
                            Text(reminder.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(reminder.color.swiftUIColor)
                            Text(reminder.taskTitle)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }

            Button {
                onNavigateToBoard(BoardFilterRequest(quickFilter: .allActive))
            } label: {
                Label("进入「全部待办」管理事项", systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(
                        Capsule(style: .continuous)
                            .fill(TaskTagColor.sky.gradient)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.violet.swiftUIColor)
    }
}
