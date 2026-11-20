import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

private struct PendingFollowUpDraft: Identifiable, Equatable {
    let id = UUID()
    var scheduledAt: Date
    var note: String
    var isOverdueRetry: Bool
}

struct ProgressFollowUpSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query private var allTasks: [WorkTask]
    @Query private var allRoutines: [RoutineReminderRule]

    @Bindable var task: WorkTask

    @State private var content: String = ""
    @State private var entryType: ProgressEntryType = .update
    @State private var logAttachments: [AttachmentItem] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingFileImporter: Bool = false
    @State private var attachmentError: String?

    @State private var enableFollowUpSchedule: Bool = false
    @State private var scheduledDate: Date = Date().addingTimeInterval(3600 * 2)
    @State private var followUpNote: String = ""
    @State private var isOverdueRetry: Bool = false
    @State private var queuedFollowUps: [PendingFollowUpDraft] = []

    private let selectableEntryTypes: [ProgressEntryType] = [
        .update, .blocker, .decision, .followUpNote
    ]

    init(
        task: WorkTask,
        defaultEnableFollowUp: Bool = false,
        defaultIsOverdueRetry: Bool = false
    ) {
        self._task = Bindable(wrappedValue: task)
        _enableFollowUpSchedule = State(initialValue: defaultEnableFollowUp)
        _isOverdueRetry = State(initialValue: defaultIsOverdueRetry)
    }

    private var canSave: Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || !logAttachments.isEmpty || enableFollowUpSchedule || !queuedFollowUps.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        taskHeaderBanner
                        progressRecordCard
                        followUpReminderCard

                        Button {
                            saveAndSync()
                        } label: {
                            Label("保存进展并同步提醒", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(.white)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(canSave ? AnyShapeStyle(task.tagColor.gradient) : AnyShapeStyle(Color.gray.opacity(0.4)))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                    }
                    .adaptiveScreenContainer()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("进展与复追")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveAndSync()
                    }
                    .fontWeight(.bold)
                    .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item, .data, .content, .pdf, .plainText, .image, .archive],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        do {
                            let imported = try AttachmentStore.shared.importFile(from: url)
                            logAttachments.append(imported)
                        } catch {
                            attachmentError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    attachmentError = error.localizedDescription
                }
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task { @MainActor in
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let saved = try? AttachmentStore.shared.saveImageData(
                            data,
                            suggestedName: "log_\(Int(Date().timeIntervalSince1970)).jpg"
                           ) {
                            logAttachments.append(saved)
                        }
                    }
                    selectedPhotos.removeAll()
                }
            }
            .alert(
                "附件导入提示",
                isPresented: Binding(
                    get: { attachmentError != nil },
                    set: { if !$0 { attachmentError = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {
                    attachmentError = nil
                }
            } message: {
                Text(attachmentError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var taskHeaderBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(task.tagColor.gradient)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)

                AdaptiveFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                    TaskStatusBadge(status: task.status)
                }
            }

            Spacer()
        }
        .padding(14)
        .liquidGlassCard(tint: task.tagColor.swiftUIColor, cornerRadius: 18)
    }

    private var progressRecordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("记录工作进展（选填）", systemImage: "text.bubble.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TaskTagColor.sky.swiftUIColor)

            Picker("记录类型", selection: $entryType) {
                ForEach(selectableEntryTypes) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)

            TextField(
                "输入当前推进情况、沟通反馈、卡点或关键结论（若仅需添加复追提醒可留空）...",
                text: $content,
                axis: .vertical
            )
            .lineLimit(3...7)
            .font(.subheadline)
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
                    Label("附带截图/照片", systemImage: "photo.badge.plus")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.sky.swiftUIColor.opacity(0.15))
                        )
                }

                Button {
                    showingFileImporter = true
                } label: {
                    Label("附带本地文件", systemImage: "paperclip")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.teal.swiftUIColor.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            if !logAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(logAttachments) { att in
                        HStack(spacing: 8) {
                            Image(systemName: att.kind.systemImage)
                                .foregroundStyle(TaskTagColor.sky.swiftUIColor)
                            Text(att.fileName)
                                .font(.caption.weight(.medium))
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
                                    .foregroundStyle(.secondary)
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
        .liquidGlassCard(tint: TaskTagColor.sky.swiftUIColor)
    }

    private var followUpReminderCard: some View {
        let accent = isOverdueRetry ? TaskTagColor.coral : TaskTagColor.violet

        return VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $enableFollowUpSchedule.animation()) {
                Label("同时设定复追提醒时间", systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent.swiftUIColor)
            }
            .tint(accent.swiftUIColor)

            if enableFollowUpSchedule {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        quickTimePill("+1小时后", date: Date().addingTimeInterval(3600), color: accent.swiftUIColor)
                        quickTimePill("+3小时后", date: Date().addingTimeInterval(3600 * 3), color: accent.swiftUIColor)
                        quickTimePill("明早 09:30", date: Self.tomorrowMorningDate(), color: accent.swiftUIColor)
                        quickTimePill("3天后 09:30", date: Self.daysAfterMorningDate(3), color: accent.swiftUIColor)
                    }
                }

                ConfirmableDatePickerRow(
                    title: "复追提醒时间",
                    selection: $scheduledDate,
                    displayedComponents: [.date, .hourAndMinute],
                    accentColor: accent.swiftUIColor
                )

                Toggle("标记为逾期未处理重点复追", isOn: $isOverdueRetry)
                    .font(.caption.weight(.semibold))
                    .tint(TaskTagColor.coral.swiftUIColor)

                TextField("复追备注（选填，如：确认对方是否反馈）", text: $followUpNote)
                    .font(.caption)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                Button {
                    queueCurrentScheduleDraft()
                } label: {
                    Label("再追加一个提醒节点", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(accent.swiftUIColor)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accent.swiftUIColor.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)

                if !queuedFollowUps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("已追加待保存节点 (\(queuedFollowUps.count))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(queuedFollowUps) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isOverdueRetry ? "exclamationmark.arrow.circlepath" : "bell.fill")
                                    .font(.caption)
                                    .foregroundStyle(item.isOverdueRetry ? TaskTagColor.coral.swiftUIColor : TaskTagColor.violet.swiftUIColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption.weight(.semibold))
                                    if !item.note.isEmpty {
                                        Text(item.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    queuedFollowUps.removeAll { $0.id == item.id }
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
        }
        .padding(16)
        .liquidGlassCard(tint: accent.swiftUIColor)
    }

    private func quickTimePill(_ title: String, date: Date, color: Color) -> some View {
        Button {
            scheduledDate = date
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .foregroundStyle(color)
                .background(
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func queueCurrentScheduleDraft() {
        let trimmedNote = followUpNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let alreadyExists = queuedFollowUps.contains {
            abs($0.scheduledAt.timeIntervalSince(scheduledDate)) < 60
        }
        if !alreadyExists {
            queuedFollowUps.append(
                PendingFollowUpDraft(
                    scheduledAt: scheduledDate,
                    note: trimmedNote,
                    isOverdueRetry: isOverdueRetry
                )
            )
            queuedFollowUps.sort { $0.scheduledAt < $1.scheduledAt }
        }
        followUpNote = ""
    }

    private func saveAndSync() {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasProgressInput = !trimmedContent.isEmpty || !logAttachments.isEmpty

        var schedulesToAdd = queuedFollowUps
        if enableFollowUpSchedule {
            let trimmedFollowNote = followUpNote.trimmingCharacters(in: .whitespacesAndNewlines)
            let alreadyQueued = schedulesToAdd.contains {
                abs($0.scheduledAt.timeIntervalSince(scheduledDate)) < 60
            }
            if !alreadyQueued {
                schedulesToAdd.append(
                    PendingFollowUpDraft(
                        scheduledAt: scheduledDate,
                        note: trimmedFollowNote,
                        isOverdueRetry: isOverdueRetry
                    )
                )
            }
        }

        if hasProgressInput {
            let finalText = trimmedContent.isEmpty ? "上传了 \(logAttachments.count) 个进展附件" : trimmedContent
            task.addProgressLog(
                content: finalText,
                type: entryType,
                attachments: logAttachments
            )
            if task.status == .todo {
                task.status = .inProgress
            }
        }

        if !schedulesToAdd.isEmpty {
            let sortedSchedules = schedulesToAdd.sorted { $0.scheduledAt < $1.scheduledAt }
            for item in sortedSchedules {
                task.addManualFollowUp(
                    at: item.scheduledAt,
                    note: item.note,
                    isOverdueRetry: item.isOverdueRetry
                )
            }

            if !hasProgressInput {
                let summaryLines = sortedSchedules.map { item -> String in
                    let timeStr = item.scheduledAt.formatted(date: .abbreviated, time: .shortened)
                    let prefix = item.isOverdueRetry ? "[逾期复追]" : "[复追提醒]"
                    return item.note.isEmpty ? "\(prefix) \(timeStr)" : "\(prefix) \(timeStr) · \(item.note)"
                }
                task.addProgressLog(
                    content: "已设定复追提醒：\(summaryLines.joined(separator: "；"))",
                    type: .followUpNote
                )
            }
        }

        try? modelContext.save()

        let updatedTasks = (try? modelContext.fetch(FetchDescriptor<WorkTask>())) ?? allTasks
        let routines = (try? modelContext.fetch(FetchDescriptor<RoutineReminderRule>())) ?? allRoutines
        Task { @MainActor in
            await notificationManager.syncAllNotifications(tasks: updatedTasks, routines: routines)
        }
        dismiss()
    }

    private static func tomorrowMorningDate() -> Date {
        daysAfterMorningDate(1)
    }

    private static func daysAfterMorningDate(_ days: Int) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: day) ?? day
    }
}
