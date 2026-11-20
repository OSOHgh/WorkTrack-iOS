import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct OutcomeDecisionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query private var allTasks: [WorkTask]
    @Query private var allRoutines: [RoutineReminderRule]

    @Bindable var task: WorkTask

    @State private var outcomeSummary: String = ""
    @State private var needsContinuedTracking: Bool = true
    @State private var followUpNote: String = ""
    @State private var customFollowUpDates: [Date] = []
    @State private var pickerFollowUpDate: Date = Date().addingTimeInterval(3600 * 24)

    @State private var newAttachments: [AttachmentItem] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showingFileImporter: Bool = false
    @State private var attachmentErrorMessage: String?

    init(task: WorkTask, defaultContinuedTracking: Bool? = nil) {
        self._task = Bindable(wrappedValue: task)
        let initialSummary = task.outcomeSummary
        let initialMode = defaultContinuedTracking ?? (task.status == .followUp ? true : false)
        _outcomeSummary = State(initialValue: initialSummary)
        _needsContinuedTracking = State(initialValue: initialMode)
        _customFollowUpDates = State(initialValue: [Self.tomorrowMorningDate()])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        taskBriefBanner
                        outcomeInputCard
                        decisionModeSelectorCard
                        if needsContinuedTracking {
                            continuedTrackingConfigCard
                        } else {
                            archiveConfirmationCard
                        }
                    }
                    .adaptiveScreenContainer()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("记录工作结果与流转")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(needsContinuedTracking ? "保存并继续追踪" : "确认完成并归档") {
                        commitOutcome()
                    }
                    .fontWeight(.semibold)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item, .data, .content, .pdf, .plainText, .image, .archive],
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result)
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { @MainActor in
                    await loadSelectedPhotos(newItems)
                }
            }
            .alert(
                "附件导入提示",
                isPresented: Binding(
                    get: { attachmentErrorMessage != nil },
                    set: { if !$0 { attachmentErrorMessage = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {
                    attachmentErrorMessage = nil
                }
            } message: {
                Text(attachmentErrorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var taskBriefBanner: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(task.tagColor.gradient)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                    TaskStatusBadge(status: task.status)
                }
            }
            Spacer()
        }
        .padding(14)
        .liquidGlassCard(tint: task.tagColor.swiftUIColor, cornerRadius: 18)
    }

    private var outcomeInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("阶段/最终工作结果总结", systemImage: "flag.checkered.2.crossed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(task.tagColor.swiftUIColor)

            TextField(
                "记录本次交付成果、关键结论、数据产出或待对方反馈的结果说明...",
                text: $outcomeSummary,
                axis: .vertical
            )
            .lineLimit(4...8)
            .font(.subheadline)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            AdaptiveFlowLayout(horizontalSpacing: 10, verticalSpacing: 8) {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 6,
                    matching: .images
                ) {
                    Label("添加结果截图/照片", systemImage: "photo.badge.plus")
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
                    Label("附加本地文件", systemImage: "paperclip.badge.ellipsis")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.indigo.swiftUIColor.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            if !newAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本次新增结果附件 (\(newAttachments.count))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(newAttachments) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.kind.systemImage)
                                .foregroundStyle(task.tagColor.swiftUIColor)
                            Text(item.fileName)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(item.formattedSize)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                AttachmentStore.shared.deleteAttachment(item)
                                newAttachments.removeAll { $0.id == item.id }
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
        .liquidGlassCard(tint: task.tagColor.swiftUIColor)
    }

    private var decisionModeSelectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("选择后续分流方式", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(alignment: .top, spacing: 10) {
                // Mode A: Needs Continued Tracking
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        needsContinuedTracking = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.title2)
                                .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                            Spacer()
                            if needsContinuedTracking {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                            }
                        }
                        Text("仍需继续追踪")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("阶段产出已记录，设定后续复追时间点，到点自动系统提醒")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                needsContinuedTracking
                                    ? TaskTagColor.violet.swiftUIColor.opacity(0.16)
                                    : Color.primary.opacity(0.04)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        needsContinuedTracking ? TaskTagColor.violet.swiftUIColor : Color.clear,
                                        lineWidth: 1.6
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)

                // Mode B: Complete & Archive
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        needsContinuedTracking = false
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "archivebox.circle.fill")
                                .font(.title2)
                                .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                            Spacer()
                            if !needsContinuedTracking {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                            }
                        }
                        Text("确认完成并归档")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("事项彻底闭环，清除后续提醒并存入工作成果库与周报统计")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                !needsContinuedTracking
                                    ? TaskTagColor.emerald.swiftUIColor.opacity(0.16)
                                    : Color.primary.opacity(0.04)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        !needsContinuedTracking ? TaskTagColor.emerald.swiftUIColor : Color.clear,
                                        lineWidth: 1.6
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .liquidGlassCard(
            tint: needsContinuedTracking ? TaskTagColor.violet.swiftUIColor : TaskTagColor.emerald.swiftUIColor
        )
    }

    private var continuedTrackingConfigCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("配置继续追踪提醒时间点", systemImage: "bell.and.waves.left.and.right.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TaskTagColor.violet.swiftUIColor)

            Text("快捷添加复追节点")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickPresetButton(title: "+2小时后", date: Date().addingTimeInterval(3600 * 2))
                    quickPresetButton(title: "明天 09:30", date: Self.tomorrowMorningDate())
                    quickPresetButton(title: "3天后 09:30", date: Self.daysFromNowMorning(days: 3))
                    quickPresetButton(title: "下周一 09:30", date: Self.nextMondayMorningDate())
                }
            }

            Divider()

            Text("或手动选择任意日期与时间添加（选定时间并点击「确认」即可加入列表）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ConfirmableDatePickerRow(
                title: "选择自定义复追时间",
                selection: $pickerFollowUpDate,
                displayedComponents: [.date, .hourAndMinute],
                accentColor: TaskTagColor.violet.swiftUIColor
            ) { confirmedDate in
                addFollowUpDate(confirmedDate)
            }

            TextField("继续追踪提醒备注（如：核对上线后第2天数据表现）", text: $followUpNote)
                .font(.caption)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            if !customFollowUpDates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已设定的复追提醒时间 (\(customFollowUpDates.count))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(customFollowUpDates, id: \.self) { date in
                        HStack {
                            Image(systemName: "bell.fill")
                                .font(.caption)
                                .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button(role: .destructive) {
                                customFollowUpDates.removeAll { $0 == date }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(TaskTagColor.violet.swiftUIColor.opacity(0.08))
                        )
                    }
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.violet.swiftUIColor)
    }

    private var archiveConfirmationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(TaskTagColor.emerald.swiftUIColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("即将完成并归档此工作事项")
                    .font(.subheadline.weight(.semibold))
                Text("确认后将自动取消该任务的未触发提醒，并将工作结果与全部进展时间线转入「归档与周报」成果库，您随时可检索或重新激活。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.emerald.swiftUIColor)
    }

    private func quickPresetButton(title: String, date: Date) -> some View {
        Button {
            addFollowUpDate(date)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.plus")
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(TaskTagColor.violet.swiftUIColor)
            .background(
                Capsule(style: .continuous)
                    .fill(TaskTagColor.violet.swiftUIColor.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(TaskTagColor.violet.swiftUIColor.opacity(0.32), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers & Actions

    private func addFollowUpDate(_ date: Date) {
        if !customFollowUpDates.contains(where: { abs($0.timeIntervalSince(date)) < 30 }) {
            customFollowUpDates.append(date)
            customFollowUpDates.sort()
        }
    }

    private func commitOutcome() {
        let datesToSchedule = needsContinuedTracking
            ? (customFollowUpDates.isEmpty ? [Self.tomorrowMorningDate()] : customFollowUpDates)
            : []

        task.recordOutcome(
            summary: outcomeSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            needsContinuedTracking: needsContinuedTracking,
            followUpDates: datesToSchedule,
            followUpNote: followUpNote.trimmingCharacters(in: .whitespacesAndNewlines),
            newAttachments: newAttachments
        )

        try? modelContext.save()

        let updatedTasks = (try? modelContext.fetch(FetchDescriptor<WorkTask>())) ?? allTasks
        let routines = (try? modelContext.fetch(FetchDescriptor<RoutineReminderRule>())) ?? allRoutines
        Task { @MainActor in
            await notificationManager.syncAllNotifications(tasks: updatedTasks, routines: routines)
        }

        dismiss()
    }

    @MainActor
    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                do {
                    let saved = try AttachmentStore.shared.saveImageData(
                        data,
                        suggestedName: "outcome_\(Int(Date().timeIntervalSince1970)).jpg"
                    )
                    newAttachments.append(saved)
                } catch {
                    attachmentErrorMessage = error.localizedDescription
                }
            }
        }
        selectedPhotoItems.removeAll()
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    let imported = try AttachmentStore.shared.importFile(from: url)
                    newAttachments.append(imported)
                } catch {
                    attachmentErrorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            attachmentErrorMessage = error.localizedDescription
        }
    }

    private static func tomorrowMorningDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
        return calendar.date(bySettingHour: 9, minute: 30, second: 0, of: tomorrow) ?? tomorrow
    }

    private static func daysFromNowMorning(days: Int) -> Date {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date().addingTimeInterval(Double(days) * 86400)
        return calendar.date(bySettingHour: 9, minute: 30, second: 0, of: target) ?? target
    }

    private static func nextMondayMorningDate() -> Date {
        let calendar = Calendar.current
        let nextMon = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 9, minute: 30, weekday: 2),
            matchingPolicy: .nextTime
        )
        return nextMon ?? daysFromNowMorning(days: 3)
    }
}
