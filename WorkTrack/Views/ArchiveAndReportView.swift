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

    // Report Builder States
    @State private var selectedPreset: ReportRangePreset = .thisWeek
    @State private var customStartDate: Date = ReportGenerator.dateInterval(for: .thisWeek).start
    @State private var customEndDate: Date = ReportGenerator.dateInterval(for: .thisWeek).end
    @State private var selectedCategoryFilter: String = ""
    @State private var includeDetailedTimeline: Bool = true
    @State private var includePendingFollowUps: Bool = true
    @State private var copiedToastVisible: Bool = false

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
        }
    }

    // MARK: - Segment 1: Archived Outcomes Library

    private var archiveLibraryView: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Search Bar
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
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .liquidGlassCard(tint: TaskTagColor.emerald.swiftUIColor, cornerRadius: 16)

                if archivedTasks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(TaskTagColor.emerald.gradient)
                        Text("暂无已归档的工作成果")
                            .font(.headline)
                        Text("在任务中点击「记录工作结果」并选择「确认完成并归档」，所有交付成果与进展时间线都会沉淀在此处。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .liquidGlassCard(tint: TaskTagColor.emerald.swiftUIColor)
                } else {
                    ForEach(archivedTasks) { task in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink {
                                TaskDetailView(task: task)
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
                            }
                            .buttonStyle(.plain)

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
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .liquidGlassCard(tint: task.tagColor.swiftUIColor)
                    }
                }
            }
            .adaptiveScreenContainer()
            .padding(.bottom, 24)
        }
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
                        VStack(spacing: 8) {
                            DatePicker("起始日期", selection: $customStartDate, displayedComponents: .date)
                                .font(.caption)
                            DatePicker("结束日期", selection: $customEndDate, displayedComponents: .date)
                                .font(.caption)
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

                // Live Preview Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("实时汇报文本预览", systemImage: "text.alignleft")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(generatedReportText.count) 字")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(generatedReportText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .padding(16)
                .liquidGlassCard(tint: TaskTagColor.sky.swiftUIColor)
            }
            .adaptiveScreenContainer()
            .padding(.bottom, 24)
        }
    }

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
}
