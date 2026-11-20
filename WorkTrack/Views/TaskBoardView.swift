import SwiftUI
import SwiftData

struct TaskBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query(sort: \WorkTask.updatedAt, order: .reverse) private var allTasks: [WorkTask]
    @Query private var allRoutines: [RoutineReminderRule]

    @Binding var externalFilterRequest: BoardFilterRequest?

    @State private var searchText: String = ""
    @State private var selectedQuickFilter: BoardQuickFilter = .allActive
    @State private var selectedColorFilter: TaskTagColor? = nil
    @State private var selectedCategoryFilter: String? = nil

    @State private var showingNewTaskSheet: Bool = false
    @State private var selectedTaskForDetail: WorkTask?
    @State private var taskForProgressFollowUp: WorkTask?
    @State private var taskForOutcomeDecision: WorkTask?

    private let activeStatuses: [TaskStatus] = [.todo, .inProgress, .waiting, .followUp]

    init(externalFilterRequest: Binding<BoardFilterRequest?> = .constant(nil)) {
        self._externalFilterRequest = externalFilterRequest
    }

    private var availableCategories: [String] {
        let tags = allTasks
            .filter { $0.status.isActive }
            .map { $0.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(tags)).sorted()
    }

    private var activeTasksCount: Int {
        allTasks.filter(\.status.isActive).count
    }

    private var todayFocusTasksCount: Int {
        allTasks.filter { isTodayFocus($0) }.count
    }

    private var overdueTasksCount: Int {
        allTasks.filter { $0.status.isActive && $0.isOverdue }.count
    }

    private var filteredTasks: [WorkTask] {
        allTasks
            .filter { task in
                switch selectedQuickFilter {
                case .allActive:
                    guard task.status.isActive else { return false }
                case .todayFocus:
                    guard isTodayFocus(task) else { return false }
                case .overdue:
                    guard task.status.isActive && task.isOverdue else { return false }
                case .status(let targetStatus):
                    guard task.status == targetStatus else { return false }
                }

                if let colorFilter = selectedColorFilter {
                    guard task.tagColor == colorFilter else { return false }
                }

                if let categoryFilter = selectedCategoryFilter {
                    guard task.categoryTag == categoryFilter else { return false }
                }

                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let matchesTitle = task.title.localizedCaseInsensitiveContains(query)
                    let matchesDesc = task.taskDescription.localizedCaseInsensitiveContains(query)
                    let matchesTag = task.categoryTag.localizedCaseInsensitiveContains(query)
                    let matchesOutcome = task.outcomeSummary.localizedCaseInsensitiveContains(query)
                    let matchesLogs = task.logs.contains { $0.content.localizedCaseInsensitiveContains(query) }
                    return matchesTitle || matchesDesc || matchesTag || matchesOutcome || matchesLogs
                }
                return true
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

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                List {
                    Section {
                        filterHeaderSection
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                            .adaptiveScreenContainer()
                    }

                    if filteredTasks.isEmpty {
                        Section {
                            emptyBoardStateCard
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 16, trailing: 0))
                                .adaptiveScreenContainer()
                        }
                    } else {
                        Section {
                            ForEach(filteredTasks) { task in
                                FocusTaskGlassCard(
                                    task: task,
                                    onOpenDetail: {
                                        selectedTaskForDetail = task
                                    },
                                    onProgressAndFollowUp: {
                                        taskForProgressFollowUp = task
                                    },
                                    onOutcomeDecision: {
                                        taskForOutcomeDecision = task
                                    }
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                                .adaptiveScreenContainer()
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteTask(task)
                                    } label: {
                                        Label("删除", systemImage: "trash.fill")
                                    }
                                }
                                .contextMenu {
                                    ForEach(activeStatuses) { newStatus in
                                        Button {
                                            task.status = newStatus
                                            task.addProgressLog(content: "切换工作状态为「\(newStatus.displayName)」", type: .update)
                                            try? modelContext.save()
                                        } label: {
                                            Label("设为\(newStatus.displayName)", systemImage: newStatus.systemImage)
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        deleteTask(task)
                                    } label: {
                                        Label("删除该工作待办", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom, alignment: .trailing) {
                    // Floating + 新建工作待办 Liquid Glass button
                    Button {
                        showingNewTaskSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("新建工作待办")
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.sky.gradient)
                                .shadow(color: TaskTagColor.sky.swiftUIColor.opacity(0.35), radius: 14, x: 0, y: 6)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("全部工作与追踪看板")
            .searchable(text: $searchText, prompt: "搜索工作标题、分类标签、进展或结果...")
            .navigationDestination(item: $selectedTaskForDetail) { task in
                TaskDetailView(task: task)
            }
            .onChange(of: externalFilterRequest, initial: true) { _, request in
                guard let request else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedQuickFilter = request.quickFilter
                    selectedCategoryFilter = request.category
                    selectedColorFilter = nil
                    searchText = ""
                }
                externalFilterRequest = nil
            }
            .sheet(isPresented: $showingNewTaskSheet) {
                TaskEditorSheet()
            }
            .sheet(item: $taskForProgressFollowUp) { task in
                ProgressFollowUpSheet(
                    task: task,
                    defaultEnableFollowUp: task.isOverdue,
                    defaultIsOverdueRetry: task.isOverdue
                )
            }
            .sheet(item: $taskForOutcomeDecision) { task in
                OutcomeDecisionSheet(task: task)
            }
        }
    }

    // MARK: - Filter Header

    private var filterHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Quick & Status Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    statusFilterPill(
                        title: "全部活动 (\(activeTasksCount))",
                        icon: "tray.full.fill",
                        isSelected: selectedQuickFilter == .allActive,
                        color: TaskTagColor.sky.swiftUIColor
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedQuickFilter = .allActive
                        }
                    }

                    statusFilterPill(
                        title: "今日聚焦 (\(todayFocusTasksCount))",
                        icon: "sun.max.fill",
                        isSelected: selectedQuickFilter == .todayFocus,
                        color: TaskTagColor.indigo.swiftUIColor
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedQuickFilter = (selectedQuickFilter == .todayFocus) ? .allActive : .todayFocus
                        }
                    }

                    statusFilterPill(
                        title: "逾期未处理 (\(overdueTasksCount))",
                        icon: "exclamationmark.circle.fill",
                        isSelected: selectedQuickFilter == .overdue,
                        color: TaskTagColor.coral.swiftUIColor
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedQuickFilter = (selectedQuickFilter == .overdue) ? .allActive : .overdue
                        }
                    }

                    ForEach(activeStatuses) { status in
                        let count = allTasks.filter { $0.status == status }.count
                        let isSelected = selectedQuickFilter == .status(status)
                        statusFilterPill(
                            title: "\(status.displayName) (\(count))",
                            icon: status.systemImage,
                            isSelected: isSelected,
                            color: status.themeColor
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                selectedQuickFilter = isSelected ? .allActive : .status(status)
                            }
                        }
                    }
                }
            }

            // Row 2: Tag Color & Category Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TaskTagColor.allCases) { tagColor in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                selectedColorFilter = (selectedColorFilter == tagColor) ? nil : tagColor
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(tagColor.gradient)
                                    .frame(width: 9, height: 9)
                                Text(tagColor.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(selectedColorFilter == tagColor ? .white : .primary)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        selectedColorFilter == tagColor
                                            ? AnyShapeStyle(tagColor.gradient)
                                            : AnyShapeStyle(tagColor.swiftUIColor.opacity(0.12))
                                    )
                            )
                        }
                        .buttonStyle(.borderless)
                    }

                    if !availableCategories.isEmpty {
                        Divider()
                            .frame(height: 18)

                        ForEach(availableCategories, id: \.self) { category in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    selectedCategoryFilter = (selectedCategoryFilter == category) ? nil : category
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "tag.fill")
                                        .font(.caption2)
                                    Text(category)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(selectedCategoryFilter == category ? .white : .primary)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            selectedCategoryFilter == category
                                                ? AnyShapeStyle(TaskTagColor.indigo.gradient)
                                                : AnyShapeStyle(Color.primary.opacity(0.07))
                                        )
                                )
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(tint: TaskTagColor.indigo.swiftUIColor, cornerRadius: 20)
    }

    private func statusFilterPill(
        title: String,
        icon: String,
        isSelected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : color)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? color : color.opacity(0.13))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(color.opacity(0.35), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.borderless)
    }

    private var emptyBoardStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("没有匹配当前筛选条件的工作待办")
                .font(.subheadline.weight(.semibold))
            if selectedQuickFilter != .allActive || selectedColorFilter != nil || selectedCategoryFilter != nil || !searchText.isEmpty {
                Button("重置全部筛选条件") {
                    selectedQuickFilter = .allActive
                    selectedColorFilter = nil
                    selectedCategoryFilter = nil
                    searchText = ""
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .liquidGlassCard()
    }

    // MARK: - Helpers

    private func isTodayFocus(_ task: WorkTask) -> Bool {
        guard task.status.isActive else { return false }
        if task.isOverdue || task.status == .inProgress || task.status == .followUp {
            return true
        }
        let calendar = Calendar.current
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

    private func deleteTask(_ task: WorkTask) {
        for attachment in task.attachments {
            AttachmentStore.shared.deleteAttachment(attachment)
        }
        for log in task.logs {
            for attachment in log.attachments {
                AttachmentStore.shared.deleteAttachment(attachment)
            }
        }
        modelContext.delete(task)
        try? modelContext.save()

        let updatedTasks = (try? modelContext.fetch(FetchDescriptor<WorkTask>())) ?? []
        let routines = (try? modelContext.fetch(FetchDescriptor<RoutineReminderRule>())) ?? allRoutines
        Task { @MainActor in
            await notificationManager.syncAllNotifications(tasks: updatedTasks, routines: routines)
        }
    }
}

// MARK: - Task Board Liquid Glass Card

struct FocusTaskGlassCard: View {
    @Bindable var task: WorkTask
    var onOpenDetail: () -> Void
    var onProgressAndFollowUp: () -> Void
    var onOutcomeDecision: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpenDetail) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Divider()

            // Unified 2-Button Card Footer
            HStack(spacing: 10) {
                Button(action: onProgressAndFollowUp) {
                    Label("进展与复追", systemImage: "text.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(TaskTagColor.sky.swiftUIColor)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(TaskTagColor.sky.swiftUIColor.opacity(0.13))
                        )
                }
                .buttonStyle(.borderless)

                Button(action: onOutcomeDecision) {
                    Label("结果与归档", systemImage: "flag.checkered")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(TaskTagColor.emerald.swiftUIColor.opacity(0.13))
                        )
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .liquidGlassCard(tint: task.tagColor.swiftUIColor)
    }
}
