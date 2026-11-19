import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query private var allTasks: [WorkTask]
    @Query private var allRoutines: [RoutineReminderRule]

    @Bindable var task: WorkTask

    // Sheets & Modals
    @State private var showingEditSheet: Bool = false
    @State private var showingOutcomeSheet: Bool = false
    @State private var showingLogComposerSheet: Bool = false
    @State private var previewingImageAttachment: AttachmentItem?

    // Inline Subtask Input
    @State private var newSubtaskTitle: String = ""

    // Inline Custom Follow-Up / Overdue Reminder Input
    @State private var newReminderDate: Date = Date().addingTimeInterval(3600 * 3)
    @State private var newReminderNote: String = ""
    @State private var newReminderIsOverdueRetry: Bool = false

    // Task-level Attachments
    @State private var selectedTaskPhotos: [PhotosPickerItem] = []
    @State private var showingTaskFileImporter: Bool = false
    @State private var attachmentError: String?

    var body: some View {
        ZStack {
            LiquidGlassAmbientBackground()

            ScrollView {
                VStack(spacing: 18) {
                    headerOverviewCard
                    customFollowUpRemindersCard
                    subtasksChecklistCard
                    attachmentsGalleryCard
                    progressTimelineCard
                }
                .adaptiveScreenContainer()
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) {
                bottomFloatingActionBar
                    .adaptiveScreenContainer()
                    .padding(.bottom, 6)
            }
        }
        .navigationTitle("工作详情与进展追踪")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("编辑", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            TaskEditorSheet(existingTask: task)
        }
        .sheet(isPresented: $showingOutcomeSheet) {
            OutcomeDecisionSheet(task: task)
        }
        .sheet(isPresented: $showingLogComposerSheet) {
            DetailedProgressLogComposerSheet(task: task)
        }
        .sheet(item: $previewingImageAttachment) { item in
            AttachmentImagePreviewSheet(item: item)
        }
        .fileImporter(
            isPresented: $showingTaskFileImporter,
            allowedContentTypes: [.item, .data, .content, .pdf, .plainText, .image, .archive],
            allowsMultipleSelection: true
        ) { result in
            handleTaskFileImport(result)
        }
        .onChange(of: selectedTaskPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { @MainActor in
                await handleTaskPhotoSelection(items)
            }
        }
        .alert(
            "附件操作提示",
            isPresented: Binding(
                get: { attachmentError != nil },
                set: { if !$0 { attachmentError = nil } }
            )
        ) {
            Button("确定", role: .cancel) {
                attachmentError = nil
            }
        } message: {
            Text(attachmentError ?? "")
        }
    }

    // MARK: - 1. Header Overview Card

    private var headerOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                AdaptiveFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                    TaskPriorityBadge(priority: task.priority)
                }
                Spacer(minLength: 8)

                Menu {
                    ForEach(TaskStatus.allCases) { statusOption in
                        Button {
                            task.status = statusOption
                            task.addProgressLog(
                                content: "切换状态为「\(statusOption.displayName)」",
                                type: .update
                            )
                            saveAndSyncNotifications()
                        } label: {
                            Label(statusOption.displayName, systemImage: statusOption.systemImage)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        TaskStatusBadge(status: task.status)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(task.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            if !task.taskDescription.isEmpty {
                Text(task.taskDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Progress Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("当前综合完成进度")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((task.progressFraction * 100).rounded()))%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(task.tagColor.swiftUIColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                        Capsule()
                            .fill(task.tagColor.gradient)
                            .frame(width: max(10, geo.size.width * task.progressFraction), height: 8)
                    }
                }
                .frame(height: 8)
            }

            // Dates & Outcome Summary
            VStack(alignment: .leading, spacing: 8) {
                if let dueDate = task.dueDate {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(dueDate < Date() && task.status.isActive ? TaskTagColor.coral.swiftUIColor : task.tagColor.swiftUIColor)
                        Text("截止时间：\(dueDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption.weight(.medium))
                        if dueDate < Date() && task.status.isActive {
                            Text("已逾期")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(TaskTagColor.coral.swiftUIColor)
                        }
                    }
                }

                if let nextFollowUp = task.nextFollowUpAt {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                        Text("下次追踪：\(nextFollowUp.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption.weight(.medium))
                    }
                }

                if !task.outcomeSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("已记录的工作结果", systemImage: "flag.checkered")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                        Text(task.outcomeSummary)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TaskTagColor.emerald.swiftUIColor.opacity(0.10))
                    )
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: task.tagColor.swiftUIColor)
    }

    // MARK: - 2. Custom Follow-Up & Overdue Reminders Section

    private var customFollowUpRemindersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("自定义复追与逾期提醒时间列表", systemImage: "bell.and.waves.left.and.right.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                Spacer()
                Text("\(task.customFollowUpSchedules.filter { !$0.isCompleted }.count) 个待触发")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            // Manual Add Custom Follow-Up / Overdue Reminder Box
            VStack(alignment: .leading, spacing: 10) {
                DatePicker(
                    "提醒时间",
                    selection: $newReminderDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.caption)

                Toggle("标记为逾期未处理复追提醒", isOn: $newReminderIsOverdueRetry)
                    .font(.caption.weight(.semibold))
                    .tint(TaskTagColor.coral.swiftUIColor)

                HStack(spacing: 8) {
                    TextField("输入提醒备注（如：逾期未回，再次电话沟通确认）", text: $newReminderNote)
                        .font(.caption)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )

                    Button {
                        addCustomFollowUpSchedule()
                    } label: {
                        Label("手动添加", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(newReminderIsOverdueRetry ? TaskTagColor.coral.gradient : TaskTagColor.violet.gradient)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            // Scheduled List
            if task.customFollowUpSchedules.isEmpty {
                Text("暂未设置自定义复追或逾期重追提醒。您可以在上方自由添加任意多个提醒时间点。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(task.customFollowUpSchedules) { item in
                    HStack(spacing: 10) {
                        Button {
                            toggleFollowUpItemCompletion(item)
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "bell.circle.fill")
                                .font(.title3)
                                .foregroundStyle(
                                    item.isCompleted
                                        ? TaskTagColor.emerald.swiftUIColor
                                        : (item.isOverdueRetry ? TaskTagColor.coral.swiftUIColor : TaskTagColor.violet.swiftUIColor)
                                )
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption.weight(.bold))
                                    .strikethrough(item.isCompleted)
                                if item.isOverdueRetry {
                                    Text("逾期复追")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .foregroundStyle(TaskTagColor.coral.swiftUIColor)
                                        .background(
                                            Capsule().fill(TaskTagColor.coral.swiftUIColor.opacity(0.15))
                                        )
                                }
                            }
                            if !item.note.isEmpty {
                                Text(item.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button(role: .destructive) {
                            task.removeManualFollowUp(id: item.id)
                            saveAndSyncNotifications()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.violet.swiftUIColor)
    }

    // MARK: - 3. Subtasks Checklist Card

    private var subtasksChecklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let subs = task.subtasks
            let completedCount = subs.filter(\.isCompleted).count

            HStack {
                Label("子步骤执行清单", systemImage: "checklist")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(task.tagColor.swiftUIColor)
                Spacer()
                Text("\(completedCount) / \(subs.count) 已完成")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("新增子步骤（回车或点击添加）...", text: $newSubtaskTitle)
                    .font(.caption)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .onSubmit {
                        addSubtask()
                    }

                Button {
                    addSubtask()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(task.tagColor.swiftUIColor)
                }
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if subs.isEmpty {
                Text("暂无拆分子步骤，可在上方快速添加推进节点。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subs) { item in
                    HStack(spacing: 10) {
                        Button {
                            toggleSubtask(item)
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundStyle(item.isCompleted ? TaskTagColor.emerald.swiftUIColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        Text(item.title)
                            .font(.subheadline)
                            .strikethrough(item.isCompleted)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)

                        Spacer()

                        Button(role: .destructive) {
                            deleteSubtask(item)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: task.tagColor.swiftUIColor)
    }

    // MARK: - 4. Local Photos / Screenshots & Files Attachments Section

    private var attachmentsGalleryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("本地图片/截图与文件附件区", systemImage: "paperclip.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TaskTagColor.teal.swiftUIColor)
                Spacer()
                Text("\(task.attachments.count) 个任务附件")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedTaskPhotos,
                    maxSelectionCount: 8,
                    matching: .images
                ) {
                    Label("添加照片 / 截图", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(TaskTagColor.sky.swiftUIColor)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.sky.swiftUIColor.opacity(0.14))
                        )
                }

                Button {
                    showingTaskFileImporter = true
                } label: {
                    Label("导入本地文件 (PDF/文档/表格)", systemImage: "doc.badge.plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(TaskTagColor.teal.swiftUIColor)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.teal.swiftUIColor.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if task.attachments.isEmpty {
                Text("支持添加聊天截图、白板照片、PDF方案、Word/Excel等任意本地附件，完全离线加密保存在本机沙盒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    ForEach(task.attachments) { item in
                        AttachmentThumbnailCard(
                            item: item,
                            accentColor: task.tagColor.swiftUIColor,
                            onPreviewImage: {
                                previewingImageAttachment = item
                            },
                            onDelete: {
                                deleteTaskAttachment(item)
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.teal.swiftUIColor)
    }

    // MARK: - 5. Vertical Progress Timeline Card

    private var progressTimelineCard: some View {
        let sortedLogs = task.logs.sorted { $0.createdAt > $1.createdAt }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("纵向进展与复追时间线 (\(sortedLogs.count))", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(task.tagColor.swiftUIColor)

                Spacer()

                Button {
                    showingLogComposerSheet = true
                } label: {
                    Label("新增进展记录", systemImage: "plus.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(task.tagColor.swiftUIColor)
                }
                .buttonStyle(.plain)
            }

            if sortedLogs.isEmpty {
                Text("暂无进展时间线记录，点击下方「记录进展」随时留存推进痕迹。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedLogs) { log in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressEntryTypeBadge(entryType: log.entryType)
                                Spacer()
                                Text(log.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(log.content)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            if !log.attachments.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(log.attachments) { att in
                                            if att.kind == .image {
                                                Button {
                                                    previewingImageAttachment = att
                                                } label: {
                                                    logAttachmentPillContent(att)
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                ShareLink(item: AttachmentStore.shared.fileURL(for: att)) {
                                                    logAttachmentPillContent(att)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(log.entryType.themeColor.opacity(0.25), lineWidth: 0.9)
                                )
                        )
                    }
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: task.tagColor.swiftUIColor)
    }

    private func logAttachmentPillContent(_ att: AttachmentItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: att.kind.systemImage)
                .font(.caption2)
            Text(att.fileName)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
            Text("(\(att.formattedSize))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    // MARK: - 6. Bottom Floating Action Bar

    private var bottomFloatingActionBar: some View {
        HStack(spacing: 12) {
            Button {
                showingLogComposerSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.bubble.fill")
                    Text("记录进展")
                        .fontWeight(.bold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(TaskTagColor.sky.swiftUIColor)
                .background(
                    Capsule(style: .continuous)
                        .fill(TaskTagColor.sky.swiftUIColor.opacity(0.15))
                )
            }
            .buttonStyle(.plain)

            Button {
                showingOutcomeSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                    Text("记录结果 / 归档")
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(
                    Capsule(style: .continuous)
                        .fill(task.tagColor.gradient)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .liquidGlassFloatingBar(cornerRadius: 30)
    }

    // MARK: - Actions & Logic

    private func addCustomFollowUpSchedule() {
        let note = newReminderNote.trimmingCharacters(in: .whitespacesAndNewlines)
        task.addManualFollowUp(
            at: newReminderDate,
            note: note,
            isOverdueRetry: newReminderIsOverdueRetry
        )
        let labelText = newReminderIsOverdueRetry ? "添加逾期复追提醒" : "添加自定义复追提醒"
        task.addProgressLog(
            content: "\(labelText)：\(newReminderDate.formatted(date: .abbreviated, time: .shortened)) \(note)",
            type: .followUpNote
        )
        newReminderNote = ""
        saveAndSyncNotifications()
    }

    private func toggleFollowUpItemCompletion(_ item: FollowUpScheduleItem) {
        var list = task.customFollowUpSchedules
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx].isCompleted.toggle()
            task.customFollowUpSchedules = list
            saveAndSyncNotifications()
        }
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var subs = task.subtasks
        subs.append(SubtaskItem(title: trimmed))
        task.subtasks = subs
        newSubtaskTitle = ""
        try? modelContext.save()
    }

    private func toggleSubtask(_ item: SubtaskItem) {
        var subs = task.subtasks
        if let idx = subs.firstIndex(where: { $0.id == item.id }) {
            subs[idx].isCompleted.toggle()
            subs[idx].completedAt = subs[idx].isCompleted ? Date() : nil
            task.subtasks = subs
            try? modelContext.save()
        }
    }

    private func deleteSubtask(_ item: SubtaskItem) {
        var subs = task.subtasks
        subs.removeAll { $0.id == item.id }
        task.subtasks = subs
        try? modelContext.save()
    }

    @MainActor
    private func handleTaskPhotoSelection(_ items: [PhotosPickerItem]) async {
        var currentAttachments = task.attachments
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                do {
                    let saved = try AttachmentStore.shared.saveImageData(
                        data,
                        suggestedName: "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                    )
                    currentAttachments.append(saved)
                } catch {
                    attachmentError = error.localizedDescription
                }
            }
        }
        task.attachments = currentAttachments
        selectedTaskPhotos.removeAll()
        try? modelContext.save()
    }

    private func handleTaskFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var currentAttachments = task.attachments
            for url in urls {
                do {
                    let saved = try AttachmentStore.shared.importFile(from: url)
                    currentAttachments.append(saved)
                } catch {
                    attachmentError = error.localizedDescription
                }
            }
            task.attachments = currentAttachments
            try? modelContext.save()
        case .failure(let error):
            attachmentError = error.localizedDescription
        }
    }

    private func deleteTaskAttachment(_ item: AttachmentItem) {
        AttachmentStore.shared.deleteAttachment(item)
        var current = task.attachments
        current.removeAll { $0.id == item.id }
        task.attachments = current
        try? modelContext.save()
    }

    private func saveAndSyncNotifications() {
        try? modelContext.save()
        let updatedTasks = (try? modelContext.fetch(FetchDescriptor<WorkTask>())) ?? allTasks
        let routines = (try? modelContext.fetch(FetchDescriptor<RoutineReminderRule>())) ?? allRoutines
        Task { @MainActor in
            await notificationManager.syncAllNotifications(tasks: updatedTasks, routines: routines)
        }
    }
}

// MARK: - Attachment Thumbnail Card & Preview Sheet

struct AttachmentThumbnailCard: View {
    let item: AttachmentItem
    let accentColor: Color
    var onPreviewImage: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.kind == .image,
               let data = AttachmentStore.shared.readData(for: item),
               let uiImage = UIImage(data: data) {
                Button(action: onPreviewImage) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 92)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Image(systemName: item.kind.systemImage)
                        .font(.title2)
                        .foregroundStyle(accentColor)
                    Spacer()
                    Text(item.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 54)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.10))
                )
            }

            Text(item.fileName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            HStack {
                Text(item.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()

                ShareLink(item: AttachmentStore.shared.fileURL(for: item)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(accentColor)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
        )
    }
}

struct AttachmentImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: AttachmentItem

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let data = AttachmentStore.shared.readData(for: item),
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    Text("无法加载图片预览")
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle(item.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: AttachmentStore.shared.fileURL(for: item)) {
                        Label("分享/导出", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Detailed Progress Log Composer with Attachments

struct DetailedProgressLogComposerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var task: WorkTask

    @State private var content: String = ""
    @State private var entryType: ProgressEntryType = .update
    @State private var logAttachments: [AttachmentItem] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingFileImporter: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("类型", selection: $entryType) {
                            ForEach(ProgressEntryType.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("详细描述当前工作进展、同步内容、风险卡点或复追反馈...", text: $content, axis: .vertical)
                            .lineLimit(4...10)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )

                        AdaptiveFlowLayout(horizontalSpacing: 10, verticalSpacing: 8) {
                            PhotosPicker(
                                selection: $selectedPhotos,
                                maxSelectionCount: 6,
                                matching: .images
                            ) {
                                Label("附带进展截图/照片", systemImage: "photo.badge.plus")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(TaskTagColor.sky.swiftUIColor.opacity(0.15))
                                    )
                            }

                            Button {
                                showingFileImporter = true
                            } label: {
                                Label("附带文件", systemImage: "paperclip")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(TaskTagColor.teal.swiftUIColor.opacity(0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        if !logAttachments.isEmpty {
                            ForEach(logAttachments) { att in
                                HStack {
                                    Image(systemName: att.kind.systemImage)
                                    Text(att.fileName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(att.formattedSize)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Button(role: .destructive) {
                                        AttachmentStore.shared.deleteAttachment(att)
                                        logAttachments.removeAll { $0.id == att.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
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
                    .adaptiveScreenContainer()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("新增进展时间线记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存记录") {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty || !logAttachments.isEmpty else { return }
                        let finalText = trimmed.isEmpty ? "上传了 \(logAttachments.count) 个进展附件" : trimmed
                        task.addProgressLog(
                            content: finalText,
                            type: entryType,
                            attachments: logAttachments
                        )
                        if task.status == .todo {
                            task.status = .inProgress
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && logAttachments.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item, .data, .content, .pdf, .plainText, .image, .archive],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        if let imported = try? AttachmentStore.shared.importFile(from: url) {
                            logAttachments.append(imported)
                        }
                    }
                }
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task { @MainActor in
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let saved = try? AttachmentStore.shared.saveImageData(data, suggestedName: "log_\(Int(Date().timeIntervalSince1970)).jpg") {
                            logAttachments.append(saved)
                        }
                    }
                    selectedPhotos.removeAll()
                }
            }
        }
    }
}
