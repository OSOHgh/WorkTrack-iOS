import SwiftUI
import SwiftData

struct TaskEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query private var allTasks: [WorkTask]
    @Query private var allRoutines: [RoutineReminderRule]

    let existingTask: WorkTask?

    @State private var title: String = ""
    @State private var taskDescription: String = ""
    @State private var categoryTag: String = "日常工作"
    @State private var tagColor: TaskTagColor = .sky
    @State private var priority: TaskPriority = .medium
    @State private var status: TaskStatus = .todo

    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date().addingTimeInterval(3600 * 4)

    @State private var hasFollowUpDate: Bool = false
    @State private var nextFollowUpAt: Date = Date().addingTimeInterval(3600 * 24)

    @State private var subtasks: [SubtaskItem] = []
    @State private var newSubtaskTitle: String = ""

    @State private var customSchedules: [FollowUpScheduleItem] = []
    @State private var pendingScheduleDate: Date = Date().addingTimeInterval(3600 * 3)
    @State private var pendingScheduleNote: String = ""
    @State private var pendingScheduleIsOverdueRetry: Bool = false

    private let presetCategoryTags: [String] = [
        "日常工作", "项目推进", "跨部门协同", "客户跟进", "汇报材料", "紧急专项"
    ]

    init(existingTask: WorkTask? = nil) {
        self.existingTask = existingTask
        if let task = existingTask {
            _title = State(initialValue: task.title)
            _taskDescription = State(initialValue: task.taskDescription)
            _categoryTag = State(initialValue: task.categoryTag)
            _tagColor = State(initialValue: task.tagColor)
            _priority = State(initialValue: task.priority)
            _status = State(initialValue: task.status)
            _hasDueDate = State(initialValue: task.dueDate != nil)
            _dueDate = State(initialValue: task.dueDate ?? Date().addingTimeInterval(3600 * 4))
            _hasFollowUpDate = State(initialValue: task.nextFollowUpAt != nil)
            _nextFollowUpAt = State(initialValue: task.nextFollowUpAt ?? Date().addingTimeInterval(3600 * 24))
            _subtasks = State(initialValue: task.subtasks)
            _customSchedules = State(initialValue: task.customFollowUpSchedules)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        basicInfoCard
                        tagAndColorCard
                        scheduleAndFollowUpCard
                        subtasksEditorCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle(existingTask == nil ? "新建工作待办" : "编辑工作待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveTask()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Sections

    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("核心任务信息", systemImage: "doc.text.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tagColor.swiftUIColor)

            TextField("输入工作事项标题（必填）", text: $title)
                .font(.headline)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            TextField("补充任务背景、交付标准或对接人说明（选填）", text: $taskDescription, axis: .vertical)
                .lineLimit(3...6)
                .font(.subheadline)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("优先级")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("优先级", selection: $priority) {
                        ForEach(TaskPriority.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("当前状态")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(TaskStatus.allCases.filter(\.isActive)) { item in
                            Button {
                                status = item
                            } label: {
                                Label(item.displayName, systemImage: item.systemImage)
                            }
                        }
                    } label: {
                        TaskStatusBadge(status: status)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: tagColor.swiftUIColor)
    }

    private var tagAndColorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("分类标签与轻快卡片色彩", systemImage: "paintpalette.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tagColor.swiftUIColor)
                Spacer()
                TagColorBadge(categoryTag: categoryTag, tagColor: tagColor)
            }

            TextField("输入分类标签（如：季度汇报 / 研发协同）", text: $categoryTag)
                .font(.subheadline)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presetCategoryTags, id: \.self) { preset in
                        Button {
                            categoryTag = preset
                        } label: {
                            Text(preset)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .foregroundStyle(categoryTag == preset ? .white : .primary)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(categoryTag == preset ? AnyShapeStyle(tagColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(TaskTagColor.allCases) { colorOption in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            tagColor = colorOption
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colorOption.gradient)
                                .frame(width: 14, height: 14)
                            Text(colorOption.displayName)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colorOption.swiftUIColor.opacity(tagColor == colorOption ? 0.22 : 0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            tagColor == colorOption ? colorOption.swiftUIColor : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: tagColor.swiftUIColor)
    }

    private var scheduleAndFollowUpCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("时间节点与自定义复追提醒", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tagColor.swiftUIColor)

            Toggle("设置计划截止时间 (Due Date)", isOn: $hasDueDate.animation())
                .font(.subheadline.weight(.medium))

            if hasDueDate {
                DatePicker(
                    "截止时间",
                    selection: $dueDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline)
            }

            Divider()

            Toggle("设置下次继续追踪时间 (Follow-Up)", isOn: $hasFollowUpDate.animation())
                .font(.subheadline.weight(.medium))

            if hasFollowUpDate {
                DatePicker(
                    "下次复追时间",
                    selection: $nextFollowUpAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("手动添加多节点复追 / 逾期提醒")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                DatePicker(
                    "提醒时间",
                    selection: $pendingScheduleDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.caption)

                HStack(spacing: 8) {
                    TextField("复追备注（如：催促法务反馈合同）", text: $pendingScheduleNote)
                        .font(.caption)
                        .padding(9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )

                    Toggle("逾期复追", isOn: $pendingScheduleIsOverdueRetry)
                        .labelsHidden()
                        .tint(.orange)

                    Text(pendingScheduleIsOverdueRetry ? "逾期追" : "常规追")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(pendingScheduleIsOverdueRetry ? .orange : .secondary)

                    Button {
                        let newItem = FollowUpScheduleItem(
                            scheduledAt: pendingScheduleDate,
                            note: pendingScheduleNote.trimmingCharacters(in: .whitespacesAndNewlines),
                            isOverdueRetry: pendingScheduleIsOverdueRetry,
                            isCompleted: false
                        )
                        customSchedules.append(newItem)
                        customSchedules.sort { $0.scheduledAt < $1.scheduledAt }
                        pendingScheduleNote = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(tagColor.swiftUIColor)
                    }
                    .buttonStyle(.plain)
                }

                if !customSchedules.isEmpty {
                    ForEach(customSchedules) { schedule in
                        HStack {
                            Image(systemName: schedule.isOverdueRetry ? "exclamationmark.arrow.circlepath" : "clock.badge.checkmark")
                                .foregroundStyle(schedule.isOverdueRetry ? .orange : tagColor.swiftUIColor)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(schedule.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption.weight(.semibold))
                                if !schedule.note.isEmpty {
                                    Text(schedule.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                customSchedules.removeAll { $0.id == schedule.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: tagColor.swiftUIColor)
    }

    private var subtasksEditorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("子步骤拆解清单 (\(subtasks.count))", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tagColor.swiftUIColor)

            HStack(spacing: 8) {
                TextField("添加具体执行子步骤...", text: $newSubtaskTitle)
                    .font(.subheadline)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .onSubmit {
                        appendSubtask()
                    }

                Button {
                    appendSubtask()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(tagColor.swiftUIColor)
                }
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !subtasks.isEmpty {
                ForEach($subtasks) { $subtask in
                    HStack(spacing: 10) {
                        Button {
                            subtask.isCompleted.toggle()
                            subtask.completedAt = subtask.isCompleted ? Date() : nil
                        } label: {
                            Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(subtask.isCompleted ? TaskTagColor.emerald.swiftUIColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        TextField("子步骤内容", text: $subtask.title)
                            .font(.subheadline)
                            .strikethrough(subtask.isCompleted)

                        Spacer()

                        Button(role: .destructive) {
                            let targetID = subtask.id
                            subtasks.removeAll { $0.id == targetID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: tagColor.swiftUIColor)
    }

    // MARK: - Actions

    private func appendSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtasks.append(SubtaskItem(title: trimmed))
        newSubtaskTitle = ""
    }

    private func saveTask() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedCategory = categoryTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCategory = trimmedCategory.isEmpty ? "日常工作" : trimmedCategory

        if let task = existingTask {
            task.title = trimmedTitle
            task.taskDescription = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            task.categoryTag = finalCategory
            task.tagColor = tagColor
            task.priority = priority
            task.status = status
            task.dueDate = hasDueDate ? dueDate : nil
            task.nextFollowUpAt = hasFollowUpDate ? nextFollowUpAt : nil
            task.subtasks = subtasks
            task.customFollowUpSchedules = customSchedules
            task.updatedAt = Date()
        } else {
            let newTask = WorkTask(
                title: trimmedTitle,
                taskDescription: taskDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryTag: finalCategory,
                tagColor: tagColor,
                priority: priority,
                status: status,
                dueDate: hasDueDate ? dueDate : nil,
                nextFollowUpAt: hasFollowUpDate ? nextFollowUpAt : nil,
                subtasks: subtasks,
                customFollowUpSchedules: customSchedules
            )
            modelContext.insert(newTask)
            newTask.addProgressLog(
                content: "创建工作待办「\(trimmedTitle)」",
                type: .update
            )
        }

        try? modelContext.save()

        let updatedTasks = (try? modelContext.fetch(FetchDescriptor<WorkTask>())) ?? allTasks
        let routines = (try? modelContext.fetch(FetchDescriptor<RoutineReminderRule>())) ?? allRoutines
        Task { @MainActor in
            await notificationManager.syncAllNotifications(tasks: updatedTasks, routines: routines)
        }

        dismiss()
    }
}
