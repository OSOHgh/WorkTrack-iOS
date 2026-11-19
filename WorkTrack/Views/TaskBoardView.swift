import SwiftUI
import SwiftData

struct TaskBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query(sort: \WorkTask.updatedAt, order: .reverse) private var allTasks: [WorkTask]
    @Query private var allRoutines: [RoutineReminderRule]

    @State private var searchText: String = ""
    @State private var selectedStatusFilter: TaskStatus? = nil // nil means all active tasks
    @State private var selectedColorFilter: TaskTagColor? = nil
    @State private var selectedCategoryFilter: String? = nil

    @State private var showingNewTaskSheet: Bool = false
    @State private var taskForQuickProgress: WorkTask?
    @State private var taskForOutcomeDecision: WorkTask?
    @State private var taskForQuickFollowUp: WorkTask?

    private let activeStatuses: [TaskStatus] = [.todo, .inProgress, .waiting, .followUp]

    private var availableCategories: [String] {
        let tags = allTasks
            .filter { $0.status.isActive }
            .map { $0.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(tags)).sorted()
    }

    private var filteredTasks: [WorkTask] {
        allTasks
            .filter { task in
                if let statusFilter = selectedStatusFilter {
                    guard task.status == statusFilter else { return false }
                } else {
                    guard task.status.isActive else { return false }
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

                ScrollView {
                    VStack(spacing: 16) {
                        filterHeaderSection
                        taskListSection
                    }
                    .adaptiveScreenContainer()
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
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
                QuickManualFollowUpSheet(task: task, defaultIsOverdueRetry: task.isOverdue)
            }
        }
    }

    // MARK: - Filter Header

    private var filterHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Status Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    statusFilterPill(
                        title: "全部活动 (\(allTasks.filter(\.status.isActive).count))",
                        icon: "tray.full.fill",
                        isSelected: selectedStatusFilter == nil,
                        color: TaskTagColor.sky.swiftUIColor
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedStatusFilter = nil
                        }
                    }

                    ForEach(activeStatuses) { status in
                        let count = allTasks.filter { $0.status == status }.count
                        statusFilterPill(
                            title: "\(status.displayName) (\(count))",
                            icon: status.systemImage,
                            isSelected: selectedStatusFilter == status,
                            color: status.themeColor
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                selectedStatusFilter = (selectedStatusFilter == status) ? nil : status
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
                        .buttonStyle(.plain)
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
                            .buttonStyle(.plain)
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
        .buttonStyle(.plain)
    }

    // MARK: - Task List

    private var taskListSection: some View {
        VStack(spacing: 14) {
            if filteredTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("没有匹配当前筛选条件的工作待办")
                        .font(.subheadline.weight(.semibold))
                    if selectedStatusFilter != nil || selectedColorFilter != nil || selectedCategoryFilter != nil || !searchText.isEmpty {
                        Button("重置全部筛选条件") {
                            selectedStatusFilter = nil
                            selectedColorFilter = nil
                            selectedCategoryFilter = nil
                            searchText = ""
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .liquidGlassCard()
            } else {
                ForEach(filteredTasks) { task in
                    FocusTaskGlassCard(
                        task: task,
                        onQuickProgress: {
                            taskForQuickProgress = task
                        },
                        onOutcomeDecision: {
                            taskForOutcomeDecision = task
                        },
                        onAddFollowUp: {
                            taskForQuickFollowUp = task
                        }
                    )
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
