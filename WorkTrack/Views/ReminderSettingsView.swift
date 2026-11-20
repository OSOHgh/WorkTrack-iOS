import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct BackupJSONDocument: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ReminderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query(sort: \WorkTask.updatedAt, order: .reverse) private var allTasks: [WorkTask]
    @Query(sort: \RoutineReminderRule.createdAt, order: .forward) private var allRoutines: [RoutineReminderRule]

    @State private var showingNewRoutineSheet: Bool = false
    @State private var editingRoutine: RoutineReminderRule?

    // Backup & Restore States
    @State private var backupDocument: BackupJSONDocument?
    @State private var showingBackupExporter: Bool = false
    @State private var showingBackupImporter: Bool = false
    @State private var clearExistingOnRestore: Bool = false
    @State private var statusAlertTitle: String = ""
    @State private var statusAlertMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        routineRemindersCard
                        sideloadCertificateHelperCard
                        notificationQueueStatusCard
                        localBackupAndRestoreCard
                    }
                    .adaptiveScreenContainer()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("提醒与备份")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewRoutineSheet = true
                    } label: {
                        Label("新增定时盘点", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewRoutineSheet) {
                RoutineRuleEditorSheet(existingRule: nil) {
                    syncAllNotificationsNow()
                }
            }
            .sheet(item: $editingRoutine) { rule in
                RoutineRuleEditorSheet(existingRule: rule) {
                    syncAllNotificationsNow()
                }
            }
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "WorkTrack_FullBackup_\(Self.backupDateStamp()).json"
            ) { result in
                switch result {
                case .success:
                    statusAlertTitle = "全量备份导出成功"
                    statusAlertMessage = "已成功导出包含全部工作待办、进展时间线、自定义提醒规则及本地图片/文件附件的 JSON 备份文件。"
                case .failure(let error):
                    statusAlertTitle = "导出失败"
                    statusAlertMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImport(result)
            }
            .alert(
                statusAlertTitle,
                isPresented: Binding(
                    get: { statusAlertMessage != nil },
                    set: { if !$0 { statusAlertMessage = nil } }
                )
            ) {
                Button("好的", role: .cancel) {
                    statusAlertMessage = nil
                }
            } message: {
                Text(statusAlertMessage ?? "")
            }
        }
    }

    // MARK: - 1. Custom Morning Summary & Evening Review Routine Reminders Card

    private var routineRemindersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("早晚盘点定时提醒", systemImage: "alarm.waves.left.and.right.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TaskTagColor.amber.swiftUIColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                Button {
                    showingNewRoutineSheet = true
                } label: {
                    Label("新增提醒", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.amber.gradient)
                        )
                }
                .buttonStyle(.plain)
            }

            Text("支持自由定制早间待办汇总、晚间复盘核对或任意自定义时间点的周期盘点提醒。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if allRoutines.isEmpty {
                Button {
                    seedDefaultRoutines()
                } label: {
                    Label("一键恢复默认早晚盘点提醒 (09:00 / 18:30)", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(TaskTagColor.amber.swiftUIColor.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(allRoutines) { rule in
                    HStack(spacing: 12) {
                        Button {
                            editingRoutine = rule
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(rule.formattedTime)
                                        .font(.title3.weight(.bold).monospacedDigit())
                                        .foregroundStyle(rule.isEnabled ? TaskTagColor.amber.swiftUIColor : .secondary)

                                    Text(rule.kind.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .foregroundStyle(TaskTagColor.amber.swiftUIColor)
                                        .background(
                                            Capsule().fill(TaskTagColor.amber.swiftUIColor.opacity(0.14))
                                        )

                                    Text(rule.formattedWeekdays)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text(rule.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                if !rule.note.isEmpty {
                                    Text(rule.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Toggle(
                            "启用",
                            isOn: Binding(
                                get: { rule.isEnabled },
                                set: { newValue in
                                    rule.isEnabled = newValue
                                    try? modelContext.save()
                                    syncAllNotificationsNow()
                                }
                            )
                        )
                        .labelsHidden()
                        .tint(TaskTagColor.amber.swiftUIColor)

                        Button(role: .destructive) {
                            modelContext.delete(rule)
                            try? modelContext.save()
                            syncAllNotificationsNow()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.amber.swiftUIColor)
    }

    // MARK: - 2. Sideload Certificate 7-Day Renewal Assistant

    private var sideloadCertificateHelperCard: some View {
        let daysLeft = notificationManager.daysRemainingUntilCertExpiry
        let themeColor = daysLeft <= 2 ? TaskTagColor.coral : TaskTagColor.teal

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("自签证书 7 天续签助手", systemImage: "signature")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(themeColor.swiftUIColor)
                Spacer()
                Text("剩余 \(daysLeft) 天")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(themeColor.gradient))
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("上次续签：\(notificationManager.lastCertificateRefreshDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("预计到期：\(notificationManager.nextCertExpiryDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(daysLeft <= 2 ? TaskTagColor.coral.swiftUIColor : .primary)
                }
                Spacer()
            }

            Toggle("第 5 天 / 第 6 天自动发送系统通知续签提醒", isOn: $notificationManager.certExpiryWarningEnabled)
                .font(.caption.weight(.medium))
                .tint(themeColor.swiftUIColor)

            Button {
                notificationManager.markCertificateRefreshedToday()
                statusAlertTitle = "已重置 7 天签名倒计时"
                statusAlertMessage = "已记录今日完成自签刷新，系统将在第 5 天与第 6 天早上 10:00 自动提醒您下一次续签。"
            } label: {
                Label("我已续签（重置7天倒计时）", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(
                        Capsule(style: .continuous)
                            .fill(themeColor.gradient)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .liquidGlassCard(tint: themeColor.swiftUIColor)
    }

    // MARK: - 3. System Notification Queue Status Card

    private var notificationQueueStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("系统通知队列状态 (64槽位滑动窗口)", systemImage: "bell.badge.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TaskTagColor.sky.swiftUIColor)
                Spacer()
                Text("\(notificationManager.pendingRequestCount) / 64")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(TaskTagColor.sky.swiftUIColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    Capsule()
                        .fill(TaskTagColor.sky.gradient)
                        .frame(
                            width: max(8, geo.size.width * min(1.0, Double(notificationManager.pendingRequestCount) / 64.0)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            HStack {
                Text("权限状态：\(authorizationStatusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { @MainActor in
                        _ = await notificationManager.requestPermissionIfNeeded()
                        syncAllNotificationsNow()
                    }
                } label: {
                    Label("立即重排并同步通知队列", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TaskTagColor.sky.swiftUIColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.sky.swiftUIColor)
    }

    private var authorizationStatusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized:
            return "已授权 (横幅 + 声音 + 角标)"
        case .provisional:
            return "临时授权"
        case .ephemeral:
            return "短期授权"
        case .denied:
            return "未开启 (请前往系统设置开启通知)"
        case .notDetermined:
            return "待请求授权"
        @unknown default:
            return "未知"
        }
    }

    // MARK: - 4. Full Local Backup & Restore Card

    private var localBackupAndRestoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("本地全量备份与恢复 (含图片与文件附件)", systemImage: "externaldrive.fill.badge.checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TaskTagColor.emerald.swiftUIColor)

            Text("单文件打包全部工作待办、进展时间线、早晚提醒配置以及所有本地截图/文档二进制数据，可随时存入 iCloud Drive 或“文件”App，完全无惧证书过期重装。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("恢复备份时清空当前现有数据（关闭则为智能合并覆盖）", isOn: $clearExistingOnRestore)
                .font(.caption.weight(.medium))

            HStack(spacing: 12) {
                Button {
                    prepareAndExportBackup()
                } label: {
                    Label("导出备份 (.json)", systemImage: "square.and.arrow.up.on.square.fill")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.emerald.gradient)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    showingBackupImporter = true
                } label: {
                    Label("导入恢复备份", systemImage: "square.and.arrow.down.on.square.fill")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TaskTagColor.emerald.swiftUIColor.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .liquidGlassCard(tint: TaskTagColor.emerald.swiftUIColor)
    }

    // MARK: - Helpers

    private func seedDefaultRoutines() {
        let morning = RoutineReminderRule(
            title: "早间工作待办汇总",
            note: DailyRoutineKind.morningSummary.defaultPrompt,
            kind: .morningSummary,
            hour: 9,
            minute: 0,
            weekdays: [2, 3, 4, 5, 6],
            isEnabled: true
        )
        let evening = RoutineReminderRule(
            title: "晚间工作复盘与结果核对",
            note: DailyRoutineKind.eveningReview.defaultPrompt,
            kind: .eveningReview,
            hour: 18,
            minute: 30,
            weekdays: [2, 3, 4, 5, 6],
            isEnabled: true
        )
        modelContext.insert(morning)
        modelContext.insert(evening)
        try? modelContext.save()
        syncAllNotificationsNow()
    }

    private func syncAllNotificationsNow() {
        let updatedTasks = (try? modelContext.fetch(FetchDescriptor<WorkTask>())) ?? allTasks
        let routines = (try? modelContext.fetch(FetchDescriptor<RoutineReminderRule>())) ?? allRoutines
        Task { @MainActor in
            await notificationManager.syncAllNotifications(tasks: updatedTasks, routines: routines)
        }
    }

    private func prepareAndExportBackup() {
        do {
            let data = try BackupService.exportBackupData(modelContext: modelContext)
            backupDocument = BackupJSONDocument(data: data)
            showingBackupExporter = true
        } catch {
            statusAlertTitle = "生成备份失败"
            statusAlertMessage = error.localizedDescription
        }
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                let stats = try BackupService.importBackupData(
                    data,
                    into: modelContext,
                    clearExisting: clearExistingOnRestore
                )
                syncAllNotificationsNow()
                statusAlertTitle = "全量备份恢复成功"
                statusAlertMessage = "已成功恢复 \(stats.restoredTasks) 项工作待办（含进展与附件）以及 \(stats.restoredRoutines) 条定时盘点提醒规则。"
            } catch {
                statusAlertTitle = "恢复备份失败"
                statusAlertMessage = error.localizedDescription
            }
        case .failure(let error):
            statusAlertTitle = "读取备份文件失败"
            statusAlertMessage = error.localizedDescription
        }
    }

    private static func backupDateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter.string(from: Date())
    }
}

// MARK: - Routine Reminder Rule Editor Sheet

struct RoutineRuleEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingRule: RoutineReminderRule?
    var onSaved: () -> Void

    @State private var kind: DailyRoutineKind = .morningSummary
    @State private var title: String = "早间工作待办汇总"
    @State private var note: String = DailyRoutineKind.morningSummary.defaultPrompt
    @State private var selectedTime: Date = Date()
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var isEnabled: Bool = true

    private let weekdayOptions: [(day: Int, label: String)] = [
        (2, "周一"),
        (3, "周二"),
        (4, "周三"),
        (5, "周四"),
        (6, "周五"),
        (7, "周六"),
        (1, "周日")
    ]

    init(existingRule: RoutineReminderRule?, onSaved: @escaping () -> Void) {
        self.existingRule = existingRule
        self.onSaved = onSaved

        let calendar = Calendar.current
        if let rule = existingRule {
            _kind = State(initialValue: rule.kind)
            _title = State(initialValue: rule.title)
            _note = State(initialValue: rule.note)
            let timeDate = calendar.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date()) ?? Date()
            _selectedTime = State(initialValue: timeDate)
            _selectedWeekdays = State(initialValue: Set(rule.weekdays))
            _isEnabled = State(initialValue: rule.isEnabled)
        } else {
            let defaultTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            _selectedTime = State(initialValue: defaultTime)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("提醒类型")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Picker("提醒类型", selection: $kind) {
                                ForEach(DailyRoutineKind.allCases) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: kind) { _, newKind in
                                if existingRule == nil {
                                    title = newKind.displayName
                                    note = newKind.defaultPrompt
                                    if let updatedTime = Calendar.current.date(
                                        bySettingHour: newKind.defaultHour,
                                        minute: newKind.defaultMinute,
                                        second: 0,
                                        of: Date()
                                    ) {
                                        selectedTime = updatedTime
                                    }
                                }
                            }

                            ConfirmableDatePickerRow(
                                title: "触发时间",
                                selection: $selectedTime,
                                displayedComponents: [.hourAndMinute],
                                accentColor: TaskTagColor.amber.swiftUIColor,
                                showQuickPresets: false
                            )

                            TextField("提醒标题（如：早间待办汇总 / 晚间复盘核对）", text: $title)
                                .font(.subheadline)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                )

                            TextField("提醒正文提示语", text: $note, axis: .vertical)
                                .lineLimit(2...4)
                                .font(.caption)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                )
                        }
                        .padding(16)
                        .liquidGlassCard(tint: TaskTagColor.amber.swiftUIColor)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("重复周期（点击星期切换）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("工作日") {
                                    selectedWeekdays = [2, 3, 4, 5, 6]
                                }
                                .font(.caption2.weight(.semibold))
                                Button("每天") {
                                    selectedWeekdays = [1, 2, 3, 4, 5, 6, 7]
                                }
                                .font(.caption2.weight(.semibold))
                            }

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(weekdayOptions, id: \.day) { option in
                                    let isSelected = selectedWeekdays.contains(option.day)
                                    Button {
                                        if isSelected && selectedWeekdays.count > 1 {
                                            selectedWeekdays.remove(option.day)
                                        } else {
                                            selectedWeekdays.insert(option.day)
                                        }
                                    } label: {
                                        Text(option.label)
                                            .font(.caption.weight(.bold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .foregroundStyle(isSelected ? .white : .primary)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(
                                                        isSelected
                                                            ? AnyShapeStyle(TaskTagColor.amber.gradient)
                                                            : AnyShapeStyle(Color.primary.opacity(0.06))
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Toggle("启用该定时提醒", isOn: $isEnabled)
                                .font(.subheadline.weight(.medium))
                                .tint(TaskTagColor.amber.swiftUIColor)
                        }
                        .padding(16)
                        .liquidGlassCard(tint: TaskTagColor.amber.swiftUIColor)
                    }
                    .adaptiveScreenContainer()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle(existingRule == nil ? "新增定时盘点提醒" : "编辑定时盘点提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveRule()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func saveRule() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let hour = components.hour ?? kind.defaultHour
        let minute = components.minute ?? kind.defaultMinute
        let sortedDays = selectedWeekdays.sorted()
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? kind.displayName
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? kind.defaultPrompt
            : note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let rule = existingRule {
            rule.kind = kind
            rule.title = finalTitle
            rule.note = finalNote
            rule.hour = hour
            rule.minute = minute
            rule.weekdays = sortedDays
            rule.isEnabled = isEnabled
        } else {
            let newRule = RoutineReminderRule(
                title: finalTitle,
                note: finalNote,
                kind: kind,
                hour: hour,
                minute: minute,
                weekdays: sortedDays,
                isEnabled: isEnabled
            )
            modelContext.insert(newRule)
        }

        try? modelContext.save()
        onSaved()
        dismiss()
    }
}
