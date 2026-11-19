import SwiftUI
import SwiftData

struct FocusDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query(sort: \WorkTask.updatedAt, order: .reverse) private var allTasks: [WorkTask]
    @Query(sort: \RoutineReminderRule.hour, order: .forward) private var allRoutines: [RoutineReminderRule]

    @State private var showingNewTaskSheet: Bool = false
    @State private var taskForQuickProgress: WorkTask?
    @State private var taskForOutcomeDecision: WorkTask?
    @State private var taskForQuickFollowUp: WorkTask?
    @State private var quickFollowUpIsOverdueRetry: Bool = false
    @State private var showingCertRenewedToast: Bool = false

    // MARK: - Computed Task Collections

    private var activeTasks: [WorkTask] {
        allTasks.filter { $0.status.isActive }
    }

    private var overdueTasks: [WorkTask] {
        activeTasks
            .filter { $0.isOverdue }
            .sorted { ($0.dueDate ?? $0.nextFollowUpAt ?? $0.updatedAt) < ($1.dueDate ?? $1.nextFollowUpAt ?? $1.updatedAt) }
    }

    private var followUpTasks: [WorkTask] {
        activeTasks
            .filter { $0.status == .followUp }
            .sorted { ($0.nextFollowUpAt ?? $0.updatedAt) < ($1.nextFollowUpAt ?? $1.updatedAt) }
    }

    private var todayFocusTasks: [WorkTask] {
        let calendar = Calendar.current
        return activeTasks
            .filter { task in
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
            }
            .sorted {
                if $0.isOverdue != $1.isOverdue {
                    return $0.isOverdue && !$1.isOverdue
                }
                if $0.priority.rawValue != $1.priority.rawValue {
                    return $0.priority.rawValue > $1.priority.rawValue
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var completedTodayCount: Int {
        let calendar = Calendar.current
        return allTasks.filter { task in
            task.status == .archived && calendar.isDateInToday(task.completedAt ?? task.updatedAt)
        }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        summaryGlassHeader
                        if !overdueTasks.isEmpty {
                            overdueSpotlightSection
                        }
                        todayFocusTasksSection
                    }
                    .adaptiveScreenContainer()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("今日聚焦")
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
            .sheet(item: $taskForQuickProgress) { task in
                QuickProgressLogSheet(task: task)
            }
            .sheet(item: $taskForOutcomeDecision) { task in
                OutcomeDecisionSheet(task: task)
            }
            .sheet(item: $taskForQuickFollowUp) { task in
                QuickManualFollowUpSheet(
                    task: task,
                    defaultIsOverdueRetry: quickFollowUpIsOverdueRetry
                )
            }
        }
    }

    // MARK: - Top Summary Liquid Glass Header

    private var summaryGlassHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Date().formatted(.dateTime.month().day().weekday()))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("工作推进与结果闭环")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                // Compact 7-day sideload certificate pill
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        notificationManager.markCertificateRefreshedToday()
                        showingCertRenewedToast = true
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
                metricTile(
                    title: "今日待办",
                    value: "\(todayFocusTasks.count)",
                    icon: "sun.max.fill",
                    color: TaskTagColor.sky.swiftUIColor
                )
                metricTile(
                    title: "逾期未处理",
                    value: "\(overdueTasks.count)",
                    icon: "exclamationmark.circle.fill",
                    color: TaskTagColor.coral.swiftUIColor
                )
                metricTile(
                    title: "需继续追踪",
                    value: "\(followUpTasks.count)",
                    icon: "arrow.clockwise.circle.fill",
                    color: TaskTagColor.violet.swiftUIColor
                )
                metricTile(
                    title: "今日已完成",
                    value: "\(completedTodayCount)",
                    icon: "checkmark.seal.fill",
                    color: TaskTagColor.emerald.swiftUIColor
                )
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.sky.swiftUIColor)
    }

    private func metricTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
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

    // MARK: - Overdue & Needs-Follow-Up Spotlight Section

    private var overdueSpotlightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("逾期未处理 · 重点催办与手动复追", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TaskTagColor.coral.swiftUIColor)
                Spacer()
                Text("\(overdueTasks.count) 项逾期")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskTagColor.coral.swiftUIColor)
            }

            ForEach(overdueTasks) { task in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink {
                        TaskDetailView(task: task)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(TaskTagColor.coral.gradient)
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)

                                HStack(spacing: 8) {
                                    TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                                    if let due = task.dueDate, due < Date() {
                                        Text("截止逾期：\(due.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(TaskTagColor.coral.swiftUIColor)
                                    } else if let follow = task.nextFollowUpAt, follow < Date() {
                                        Text("复追逾期：\(follow.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(TaskTagColor.coral.swiftUIColor)
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    AdaptiveFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        Button {
                            quickFollowUpIsOverdueRetry = true
                            taskForQuickFollowUp = task
                        } label: {
                            Label("手动添加逾期复追时间", systemImage: "calendar.badge.plus")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(.white)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(TaskTagColor.coral.gradient)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            taskForOutcomeDecision = task
                        } label: {
                            Label("录入结果/归档", systemImage: "flag.checkered")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(TaskTagColor.emerald.swiftUIColor.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(TaskTagColor.coral.swiftUIColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(TaskTagColor.coral.swiftUIColor.opacity(0.28), lineWidth: 1)
                        )
                )
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.coral.swiftUIColor)
    }

    // MARK: - Today's Active Task Cards Section

    private var todayFocusTasksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("今日待办与持续追踪事项", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text("共 \(activeTasks.count) 项活动中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if activeTasks.isEmpty {
                emptyFocusStateCard
            } else {
                let displayList = todayFocusTasks.isEmpty ? activeTasks : todayFocusTasks
                ForEach(displayList) { task in
                    FocusTaskGlassCard(
                        task: task,
                        onQuickProgress: {
                            taskForQuickProgress = task
                        },
                        onOutcomeDecision: {
                            taskForOutcomeDecision = task
                        },
                        onAddFollowUp: {
                            quickFollowUpIsOverdueRetry = task.isOverdue
                            taskForQuickFollowUp = task
                        }
                    )
                }
            }
        }
    }

    private var emptyFocusStateCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(TaskTagColor.sky.gradient)

            Text("当前暂无待推进的工作事项")
                .font(.headline)

            Text("点击右上角或下方按钮创建新的工作待办，支持附加截图/文档、设定自定义复追提醒与早晚盘点。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingNewTaskSheet = true
            } label: {
                Label("立即新建工作待办", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(
                        Capsule(style: .continuous)
                            .fill(TaskTagColor.sky.gradient)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .liquidGlassCard(tint: TaskTagColor.sky.swiftUIColor)
    }
}

// MARK: - Focus Task Liquid Glass Card

struct FocusTaskGlassCard: View {
    @Bindable var task: WorkTask
    var onQuickProgress: () -> Void
    var onOutcomeDecision: () -> Void
    var onAddFollowUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                TaskDetailView(task: task)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    AdaptiveFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                        TaskStatusBadge(status: task.status)
                        TaskPriorityBadge(priority: task.priority)
                        if task.isOverdue {
                            Text("已逾期")
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .foregroundStyle(.white)
                                .background(Capsule().fill(TaskTagColor.coral.gradient))
                        }
                    }

                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if !task.taskDescription.isEmpty {
                        Text(task.taskDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    // Progress bar & counters
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(task.tagColor.gradient)
                                    .frame(width: max(8, geo.size.width * task.progressFraction), height: 6)
                            }
                        }
                        .frame(height: 6)

                        AdaptiveFlowLayout(horizontalSpacing: 10, verticalSpacing: 6) {
                            let subs = task.subtasks
                            if !subs.isEmpty {
                                let done = subs.filter(\.isCompleted).count
                                Label("\(done)/\(subs.count) 子步骤", systemImage: "checklist")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            let totalAttachments = task.attachments.count + task.logs.reduce(0) { $0 + $1.attachments.count }
                            if totalAttachments > 0 {
                                Label("\(totalAttachments) 附件", systemImage: "paperclip")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            let uncompletedSchedules = task.customFollowUpSchedules.filter { !$0.isCompleted }.count
                            if uncompletedSchedules > 0 {
                                Label("\(uncompletedSchedules) 复追提醒", systemImage: "bell.badge.fill")
                                    .font(.caption2)
                                    .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                                    .lineLimit(1)
                            }

                            if let nextReminder = task.upcomingReminderDates.first {
                                HStack(spacing: 3) {
                                    Image(systemName: "clock")
                                    Text(nextReminder.formatted(date: .abbreviated, time: .shortened))
                                        .lineLimit(1)
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(task.tagColor.swiftUIColor)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Divider()

            // 3 Quick Action Buttons right on the card
            HStack(spacing: 8) {
                Button(action: onQuickProgress) {
                    Label("记进展", systemImage: "text.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(TaskTagColor.sky.swiftUIColor)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(TaskTagColor.sky.swiftUIColor.opacity(0.13))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onOutcomeDecision) {
                    Label("结果/归档", systemImage: "flag.checkered")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(TaskTagColor.emerald.swiftUIColor.opacity(0.13))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onAddFollowUp) {
                    Label("加复追", systemImage: "calendar.badge.plus")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(TaskTagColor.violet.swiftUIColor.opacity(0.13))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .liquidGlassCard(tint: task.tagColor.swiftUIColor)
    }
}

// MARK: - Quick Progress Log Composer Sheet

struct QuickProgressLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var task: WorkTask

    @State private var content: String = ""
    @State private var entryType: ProgressEntryType = .update

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                VStack(alignment: .leading, spacing: 16) {
                    Text(task.title)
                        .font(.headline)

                    Picker("记录类型", selection: $entryType) {
                        ForEach(ProgressEntryType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("输入当前最新进展、卡点或关键决策...", text: $content, axis: .vertical)
                        .lineLimit(4...8)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )

                    Spacer()
                }
                .adaptiveScreenContainer()
                .padding(.vertical, 14)
            }
            .navigationTitle("快速记录工作进展")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存进展") {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        task.addProgressLog(content: trimmed, type: entryType)
                        if task.status == .todo {
                            task.status = .inProgress
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Quick Manual Follow-Up / Overdue Reminder Sheet

struct QuickManualFollowUpSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query private var allTasks: [WorkTask]
    @Query private var allRoutines: [RoutineReminderRule]

    @Bindable var task: WorkTask
    let defaultIsOverdueRetry: Bool

    @State private var scheduledDate: Date = Date().addingTimeInterval(3600 * 2)
    @State private var note: String = ""
    @State private var isOverdueRetry: Bool = false

    init(task: WorkTask, defaultIsOverdueRetry: Bool = false) {
        self._task = Bindable(wrappedValue: task)
        self.defaultIsOverdueRetry = defaultIsOverdueRetry
        _isOverdueRetry = State(initialValue: defaultIsOverdueRetry)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                            Text(task.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }

                        DatePicker(
                            "复追提醒时间",
                            selection: $scheduledDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .padding(10)
                        .liquidGlassCard(tint: task.tagColor.swiftUIColor, cornerRadius: 18)

                        Toggle("标记为逾期未处理重点复追提醒", isOn: $isOverdueRetry)
                            .font(.subheadline.weight(.medium))
                            .tint(TaskTagColor.coral.swiftUIColor)

                        TextField("复追备注（如：确认客户是否签署盖章版）", text: $note)
                            .font(.subheadline)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                    .adaptiveScreenContainer()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle(isOverdueRetry ? "手动添加逾期复追时间" : "添加自定义复追提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加并同步通知") {
                        task.addManualFollowUp(
                            at: scheduledDate,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            isOverdueRetry: isOverdueRetry
                        )
                        let logPrefix = isOverdueRetry ? "手动添加逾期复追时间" : "手动添加复追提醒"
                        task.addProgressLog(
                            content: "\(logPrefix)：\(scheduledDate.formatted(date: .abbreviated, time: .shortened)) \(note)",
                            type: .followUpNote
                        )
                        try? modelContext.save()

                        let updatedTasks = (try? modelContext.fetch(FetchDescriptor<WorkTask>())) ?? allTasks
                        let routines = (try? modelContext.fetch(FetchDescriptor<RoutineReminderRule>())) ?? allRoutines
                        Task { @MainActor in
                            await notificationManager.syncAllNotifications(tasks: updatedTasks, routines: routines)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
