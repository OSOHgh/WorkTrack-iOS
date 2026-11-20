import SwiftUI
import SwiftData
import UIKit

enum ArchiveReportSubTab: String, CaseIterable, Identifiable {
    case archiveLibrary = "已归档成果库"
    case reportBuilder = "一键周报/月报"

    var id: String { rawValue }
}

struct ArchiveAndReportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager

    @Query(sort: \WorkTask.updatedAt, order: .reverse) private var allTasks: [WorkTask]
    @Query private var allRoutines: [RoutineReminderRule]

    @State private var selectedSegment: ArchiveReportSubTab = .archiveLibrary
    @State private var archiveSearchText: String = ""
    @State private var selectedArchivedTask: WorkTask?

    // Report Builder States
    @State private var selectedPreset: ReportRangePreset = .thisWeek
    @State private var customStartDate: Date = ReportGenerator.dateInterval(for: .thisWeek).start
    @State private var customEndDate: Date = ReportGenerator.dateInterval(for: .thisWeek).end
    @State private var selectedCategoryFilter: String = ""
    @State private var includeDetailedTimeline: Bool = true
    @State private var includePendingFollowUps: Bool = true
    @State private var copiedToastVisible: Bool = false
    @State private var reportPreviewMode: Int = 0 // 0 = 排版预览, 1 = 纯文本原文

    private var archivedTasks: [WorkTask] {
        allTasks
            .filter { task in
                guard task.status == .archived else { return false }
                let query = archiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let matchesTitle = task.title.localizedCaseInsensitiveContains(query)
                    let matchesOutcome = task.outcomeSummary.localizedCaseInsensitiveContains(query)
                    let matchesTag = task.categoryTag.localizedCaseInsensitiveContains(query)
                    return matchesTitle || matchesOutcome || matchesTag
                }
                return true
            }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    private var allCategories: [String] {
        let tags = allTasks
            .map { $0.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(tags)).sorted()
    }

    private var currentReportConfiguration: ReportConfiguration {
        let interval = selectedPreset == .custom
            ? (start: customStartDate, end: customEndDate)
            : ReportGenerator.dateInterval(for: selectedPreset)

        return ReportConfiguration(
            preset: selectedPreset,
            startDate: interval.start,
            endDate: interval.end,
            categoryFilter: selectedCategoryFilter.isEmpty ? nil : selectedCategoryFilter,
            includeDetailedTimeline: includeDetailedTimeline,
            includePendingFollowUps: includePendingFollowUps
        )
    }

    private var generatedReportText: String {
        ReportGenerator.generateTextReport(tasks: allTasks, config: currentReportConfiguration)
    }

    // Filtered collections for Structured Report Visual Preview
    private var reportFilteredTasks: [WorkTask] {
        let cat = selectedCategoryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if cat.isEmpty {
            return allTasks
        }
        return allTasks.filter { $0.categoryTag == cat }
    }

    private var reportNormalizedRange: (start: Date, end: Date) {
        let cfg = currentReportConfiguration
        return (min(cfg.startDate, cfg.endDate), max(cfg.startDate, cfg.endDate))
    }

    private var reportArchivedInRange: [WorkTask] {
        let range = reportNormalizedRange
        return reportFilteredTasks
            .filter { task in
                guard task.status == .archived else { return false }
                let finishDate = task.completedAt ?? task.updatedAt
                return finishDate >= range.start && finishDate <= range.end
            }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    private var reportActiveTrackingTasks: [WorkTask] {
        let range = reportNormalizedRange
        return reportFilteredTasks
            .filter { task in
                guard task.status.isActive else { return false }
                let touchedInRange = (task.updatedAt >= range.start && task.updatedAt <= range.end)
                    || (task.createdAt >= range.start && task.createdAt <= range.end)
                    || task.logs.contains { $0.createdAt >= range.start && $0.createdAt <= range.end }
                return touchedInRange || task.status == .inProgress || task.status == .followUp || task.status == .waiting
            }
            .sorted {
                if $0.priority.rawValue != $1.priority.rawValue {
                    return $0.priority.rawValue > $1.priority.rawValue
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var reportFollowUpPlanTasks: [WorkTask] {
        reportFilteredTasks
            .filter { task in
                guard task.status.isActive else { return false }
                return task.status == .followUp
                    || task.nextFollowUpAt != nil
                    || task.dueDate != nil
                    || task.customFollowUpSchedules.contains { !$0.isCompleted }
            }
            .sorted {
                let lhsDate = $0.upcomingReminderDates.first ?? .distantFuture
                let rhsDate = $1.upcomingReminderDates.first ?? .distantFuture
                return lhsDate < rhsDate
            }
    }

    private var reportLogsInRangeCount: Int {
        let range = reportNormalizedRange
        return reportFilteredTasks.reduce(0) { partial, task in
            partial + task.logs.filter { $0.createdAt >= range.start && $0.createdAt <= range.end }.count
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassAmbientBackground()

                VStack(spacing: 12) {
                    Picker("功能切换", selection: $selectedSegment) {
                        ForEach(ArchiveReportSubTab.allCases) { segment in
                            Text(segment.rawValue).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .adaptiveScreenContainer()
                    .padding(.top, 8)

                    if selectedSegment == .archiveLibrary {
                        archiveLibraryView
                    } else {
                        reportBuilderView
                    }
                }
            }
            .navigationTitle("归档成果与周报汇总")
            .navigationDestination(item: $selectedArchivedTask) { task in
                TaskDetailView(task: task)
            }
        }
    }

    // MARK: - Segment 1: Archived Outcomes Library (List with Left-Swipe Delete)

    private var archiveLibraryView: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索已归档标题、工作结果或分类标签...", text: $archiveSearchText)
                        .font(.subheadline)
                    if !archiveSearchText.isEmpty {
                        Button {
                            archiveSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(12)
                .liquidGlassCard(tint: TaskTagColor.emerald.swiftUIColor, cornerRadius: 16)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .adaptiveScreenContainer()
            }

            if archivedTasks.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(TaskTagColor.emerald.gradient)
                        Text("暂无已归档的工作成果")
                            .font(.headline)
                        Text("在任务中点击「结果与归档」并选择「确认完成并归档」，所有交付成果与进展时间线都会沉淀在此处。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .liquidGlassCard(tint: TaskTagColor.emerald.swiftUIColor)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 16, trailing: 0))
                    .adaptiveScreenContainer()
                }
            } else {
                Section {
                    ForEach(archivedTasks) { task in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                selectedArchivedTask = task
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                                        TaskStatusBadge(status: .archived)
                                        Spacer()
                                        Text((task.completedAt ?? task.updatedAt).formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(task.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)

                                    if !task.outcomeSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "flag.checkered")
                                                .font(.caption)
                                                .foregroundStyle(TaskTagColor.emerald.swiftUIColor)
                                                .padding(.top, 2)
                                            Text(task.outcomeSummary)
                                                .font(.caption)
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(TaskTagColor.emerald.swiftUIColor.opacity(0.10))
                                        )
                                    }

                                    HStack(spacing: 12) {
                                        Label("\(task.logs.count) 条进展记录", systemImage: "text.bubble")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        if !task.attachments.isEmpty {
                                            Label("\(task.attachments.count) 个附件", systemImage: "paperclip")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)

                            Divider()

                            HStack {
                                Text("需要补充后续跟进？")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    reopenArchivedTask(task)
                                } label: {
                                    Label("重新激活追踪", systemImage: "arrow.uturn.backward.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(TaskTagColor.violet.swiftUIColor)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(TaskTagColor.violet.swiftUIColor.opacity(0.14))
                                        )
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(16)
                        .liquidGlassCard(tint: task.tagColor.swiftUIColor)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                        .adaptiveScreenContainer()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteArchivedTask(task)
                            } label: {
                                Label("删除", systemImage: "trash.fill")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Segment 2: One-Click Weekly / Monthly Text Report Generator

    private var reportBuilderView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Report Configuration Card
                VStack(alignment: .leading, spacing: 14) {
                    Label("一键生成周报 / 月报文本汇总", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TaskTagColor.indigo.swiftUIColor)

                    Picker("统计周期", selection: $selectedPreset) {
                        ForEach(ReportRangePreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPreset) { _, newPreset in
                        copiedToastVisible = false
                        if newPreset != .custom {
                            let interval = ReportGenerator.dateInterval(for: newPreset)
                            customStartDate = interval.start
                            customEndDate = interval.end
                        }
                    }

                    if selectedPreset == .custom {
                        VStack(spacing: 10) {
                            ConfirmableDatePickerRow(
                                title: "起始日期",
                                selection: $customStartDate,
                                displayedComponents: [.date],
                                accentColor: TaskTagColor.indigo.swiftUIColor,
                                showQuickPresets: false
                            )
                            ConfirmableDatePickerRow(
                                title: "结束日期",
                                selection: $customEndDate,
                                displayedComponents: [.date],
                                accentColor: TaskTagColor.indigo.swiftUIColor,
                                showQuickPresets: false
                            )
                        }
                    }

                    if !allCategories.isEmpty {
                        HStack {
                            Text("分类筛选")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("分类标签", selection: $selectedCategoryFilter) {
                                Text("全部分类").tag("")
                                ForEach(allCategories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedCategoryFilter) { _, _ in
                                copiedToastVisible = false
                            }
                        }
                    }

                    Toggle("包含各事项详细进展时间线明细", isOn: $includeDetailedTimeline)
                        .font(.caption.weight(.medium))

                    Toggle("包含下阶段重点复追与待跟进计划", isOn: $includePendingFollowUps)
                        .font(.caption.weight(.medium))

                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = generatedReportText
                            withAnimation {
                                copiedToastVisible = true
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation {
                                    copiedToastVisible = false
                                }
                            }
                        } label: {
                            Label(
                                copiedToastVisible ? "已复制到剪贴板" : "一键复制全文",
                                systemImage: copiedToastVisible ? "checkmark.circle.fill" : "doc.on.doc.fill"
                            )
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(TaskTagColor.indigo.gradient)
                            )
                        }
                        .buttonStyle(.plain)

                        ShareLink(
                            item: generatedReportText,
                            subject: Text("WorkTrack \(selectedPreset.displayName)"),
                            message: Text(generatedReportText)
                        ) {
                            Label("分享 / 导出汇报", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .foregroundStyle(TaskTagColor.indigo.swiftUIColor)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(TaskTagColor.indigo.swiftUIColor.opacity(0.15))
                                )
                        }
                    }
                }
                .padding(16)
                .liquidGlassCard(tint: TaskTagColor.indigo.swiftUIColor)

                // Clean Structured Preview Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Label("汇报预览", systemImage: "text.alignleft")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TaskTagColor.sky.swiftUIColor)

                        Spacer()

                        Picker("预览模式", selection: $reportPreviewMode) {
                            Text("排版预览").tag(0)
                            Text("纯文本").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }

                    if reportPreviewMode == 0 {
                        structuredReportPreviewContent
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("复制粘贴后的实际文本效果")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(generatedReportText.count) 字")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Text(generatedReportText)
                                .font(.footnote)
                                .lineSpacing(6)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                        }
                    }
                }
                .padding(16)
                .liquidGlassCard(tint: TaskTagColor.sky.swiftUIColor)
            }
            .adaptiveScreenContainer()
            .padding(.bottom, 24)
        }
    }

    // MARK: - Clean Structured Visual Report Preview

    private var structuredReportPreviewContent: some View {
        let range = reportNormalizedRange
        let overdueCount = reportFilteredTasks.filter(\.isOverdue).count

        return VStack(alignment: .leading, spacing: 16) {
            // Header Banner
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("WorkTrack \(selectedPreset.displayName)")
                        .font(.headline.weight(.bold))
                    Spacer()
                    if !selectedCategoryFilter.isEmpty {
                        Text(selectedCategoryFilter)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(TaskTagColor.indigo.swiftUIColor)
                            .background(Capsule().fill(TaskTagColor.indigo.swiftUIColor.opacity(0.14)))
                    }
                }

                Text("统计周期：\(range.start.formatted(date: .numeric, time: .omitted)) 至 \(range.end.formatted(date: .numeric, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TaskTagColor.indigo.swiftUIColor.opacity(0.08))
            )

            // 1. Overview Section
            VStack(alignment: .leading, spacing: 8) {
                reportSectionHeading("一、核心统计概览", color: TaskTagColor.sky.swiftUIColor)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                    reportMiniStat("完成归档", value: "\(reportArchivedInRange.count) 项", color: TaskTagColor.emerald.swiftUIColor)
                    reportMiniStat("推进与追踪", value: "\(reportActiveTrackingTasks.count) 项", color: TaskTagColor.sky.swiftUIColor)
                    reportMiniStat("当前逾期", value: "\(overdueCount) 项", color: TaskTagColor.coral.swiftUIColor)
                    reportMiniStat("新增进展", value: "\(reportLogsInRangeCount) 条", color: TaskTagColor.violet.swiftUIColor)
                }
            }

            Divider()

            // 2. Archived Section
            VStack(alignment: .leading, spacing: 10) {
                reportSectionHeading("二、已完成归档成果", color: TaskTagColor.emerald.swiftUIColor)
                if reportArchivedInRange.isEmpty {
                    Text("本统计周期内暂无已归档成果")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(reportArchivedInRange.enumerated()), id: \.element.id) { idx, task in
                        reportTaskRowCard(index: idx + 1, task: task, isArchivedSection: true)
                    }
                }
            }

            Divider()

            // 3. Active & Follow-Up Section
            VStack(alignment: .leading, spacing: 10) {
                reportSectionHeading("三、推进中与需继续追踪事项", color: TaskTagColor.violet.swiftUIColor)
                if reportActiveTrackingTasks.isEmpty {
                    Text("当前暂无推进中或需继续追踪的工作事项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(reportActiveTrackingTasks.enumerated()), id: \.element.id) { idx, task in
                        reportTaskRowCard(index: idx + 1, task: task, isArchivedSection: false)
                    }
                }
            }

            if includePendingFollowUps {
                Divider()

                // 4. Next Follow-Up Plan Section
                VStack(alignment: .leading, spacing: 10) {
                    reportSectionHeading("四、下阶段重点跟进计划", color: TaskTagColor.amber.swiftUIColor)
                    if reportFollowUpPlanTasks.isEmpty {
                        Text("暂无待跟进提醒或计划节点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(reportFollowUpPlanTasks.enumerated()), id: \.element.id) { idx, task in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("\(idx + 1). \(task.title)")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                                }
                                if let nextDate = task.upcomingReminderDates.first {
                                    Text("最近提醒：\(nextDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("待补充具体复追时间")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                    }
                }
            }
        }
    }

    private func reportSectionHeading(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 14)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
        }
    }

    private func reportMiniStat(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    private func reportTaskRowCard(index: Int, task: WorkTask, isArchivedSection: Bool) -> some View {
        let range = reportNormalizedRange
        let sortedLogs = task.logs.sorted { $0.createdAt < $1.createdAt }
        let rangeLogs = sortedLogs.filter { $0.createdAt >= range.start && $0.createdAt <= range.end }
        let logsToShow = rangeLogs.isEmpty ? Array(sortedLogs.suffix(3)) : rangeLogs
        let summary = task.outcomeSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(index). \(task.title)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if isArchivedSection {
                    TagColorBadge(categoryTag: task.categoryTag, tagColor: task.tagColor)
                } else {
                    TaskStatusBadge(status: task.status)
                }
            }

            if isArchivedSection {
                Text("归档时间：\((task.completedAt ?? task.updatedAt).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("分类：\(task.categoryTag) ｜ 优先级：\(task.priority.displayName) ｜ 进度：\(Int((task.progressFraction * 100).rounded()))%\(task.isOverdue ? " ｜ 已逾期" : "")")
                    .font(.caption2)
                    .foregroundStyle(task.isOverdue ? TaskTagColor.coral.swiftUIColor : .secondary)
            }

            if !summary.isEmpty {
                Text("\(isArchivedSection ? "工作结果" : "阶段结果")：\(summary)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(task.tagColor.swiftUIColor.opacity(0.09))
                    )
            }

            if includeDetailedTimeline && !logsToShow.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logsToShow) { log in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(log.entryType.themeColor)
                            Text("[\(log.entryType.displayName) \(log.createdAt.formatted(date: .abbreviated, time: .shortened))] \(log.content)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Actions

    private func reopenArchivedTask(_ task: WorkTask) {
        let nextDate = Date().addingTimeInterval(3600 * 24)
        task.reopenForTracking(
            nextFollowUpAt: nextDate,
            note: "从已归档成果库重新激活，转入继续追踪"
        )
        try? modelContext.save()

        let updatedTasks = (try? modelContext.fetch(FetchDescriptor<WorkTask>())) ?? allTasks
        let routines = (try? modelContext.fetch(FetchDescriptor<RoutineReminderRule>())) ?? allRoutines
        Task { @MainActor in
            await notificationManager.syncAllNotifications(tasks: updatedTasks, routines: routines)
        }
    }

    private func deleteArchivedTask(_ task: WorkTask) {
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
