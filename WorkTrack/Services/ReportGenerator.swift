import Foundation

enum ReportRangePreset: String, CaseIterable, Identifiable, Sendable {
    case thisWeek
    case lastWeek
    case thisMonth
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisWeek:
            return "本周周报"
        case .lastWeek:
            return "上周周报"
        case .thisMonth:
            return "本月月报"
        case .custom:
            return "自定义区间"
        }
    }
}

struct ReportConfiguration: Sendable {
    var preset: ReportRangePreset
    var startDate: Date
    var endDate: Date
    var categoryFilter: String?
    var includeDetailedTimeline: Bool
    var includePendingFollowUps: Bool

    init(
        preset: ReportRangePreset = .thisWeek,
        startDate: Date? = nil,
        endDate: Date? = nil,
        categoryFilter: String? = nil,
        includeDetailedTimeline: Bool = true,
        includePendingFollowUps: Bool = true
    ) {
        let defaultInterval = ReportGenerator.dateInterval(for: preset)
        self.preset = preset
        self.startDate = startDate ?? defaultInterval.start
        self.endDate = endDate ?? defaultInterval.end
        self.categoryFilter = categoryFilter
        self.includeDetailedTimeline = includeDetailedTimeline
        self.includePendingFollowUps = includePendingFollowUps
    }
}

enum ReportGenerator {
    static func dateInterval(for preset: ReportRangePreset, now: Date = Date()) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = 2 // Monday

        switch preset {
        case .thisWeek:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
                let endOfWeek = interval.end.addingTimeInterval(-1)
                return (interval.start, endOfWeek)
            }
        case .lastWeek:
            if let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
               let previousAnchor = calendar.date(byAdding: .day, value: -7, to: thisWeek.start),
               let lastWeek = calendar.dateInterval(of: .weekOfYear, for: previousAnchor) {
                return (lastWeek.start, lastWeek.end.addingTimeInterval(-1))
            }
        case .thisMonth:
            if let interval = calendar.dateInterval(of: .month, for: now) {
                return (interval.start, interval.end.addingTimeInterval(-1))
            }
        case .custom:
            let startOfToday = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday)?.addingTimeInterval(-1) ?? now
            return (start, end)
        }

        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)?.addingTimeInterval(-1) ?? now
        return (startOfToday, endOfToday)
    }

    static func generateTextReport(tasks: [WorkTask], config: ReportConfiguration) -> String {
        let normalizedStart = min(config.startDate, config.endDate)
        let normalizedEnd = max(config.startDate, config.endDate)

        let filteredTasks: [WorkTask]
        if let categoryFilter = config.categoryFilter?.trimmingCharacters(in: .whitespacesAndNewlines),
           !categoryFilter.isEmpty {
            filteredTasks = tasks.filter { $0.categoryTag == categoryFilter }
        } else {
            filteredTasks = tasks
        }

        let archivedInRange = filteredTasks
            .filter { task in
                guard task.status == .archived else { return false }
                let finishDate = task.completedAt ?? task.updatedAt
                return finishDate >= normalizedStart && finishDate <= normalizedEnd
            }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }

        let activeTrackingTasks = filteredTasks
            .filter { task in
                guard task.status.isActive else { return false }
                let touchedInRange = (task.updatedAt >= normalizedStart && task.updatedAt <= normalizedEnd)
                    || (task.createdAt >= normalizedStart && task.createdAt <= normalizedEnd)
                    || task.logs.contains { $0.createdAt >= normalizedStart && $0.createdAt <= normalizedEnd }
                return touchedInRange || task.status == .inProgress || task.status == .followUp || task.status == .waiting
            }
            .sorted {
                if $0.priority.rawValue != $1.priority.rawValue {
                    return $0.priority.rawValue > $1.priority.rawValue
                }
                return $0.updatedAt > $1.updatedAt
            }

        let overdueCount = filteredTasks.filter(\.isOverdue).count
        let followUpTasksCount = filteredTasks.filter { $0.status == .followUp }.count
        let logsInRangeCount = filteredTasks.reduce(0) { partialResult, task in
            partialResult + task.logs.filter { $0.createdAt >= normalizedStart && $0.createdAt <= normalizedEnd }.count
        }

        let followUpPlanTasks = filteredTasks
            .filter { task in
                guard task.status.isActive else { return false }
                return task.status == .followUp
                    || task.nextFollowUpAt != nil
                    || task.dueDate != nil
                    || task.customFollowUpSchedules.contains { !$0.isCompleted }
            }
            .sorted { lhs, rhs in
                let lhsDate = earliestRelevantDate(for: lhs) ?? .distantFuture
                let rhsDate = earliestRelevantDate(for: rhs) ?? .distantFuture
                return lhsDate < rhsDate
            }

        var lines: [String] = []
        lines.append("# WorkTrack \(config.preset.displayName)")
        lines.append("统计周期：\(formatDay(normalizedStart)) 至 \(formatDay(normalizedEnd))")
        if let categoryFilter = config.categoryFilter?.trimmingCharacters(in: .whitespacesAndNewlines),
           !categoryFilter.isEmpty {
            lines.append("分类筛选：\(categoryFilter)")
        }
        lines.append("生成时间：\(formatDateTime(Date()))")
        lines.append("")

        // Section 1
        lines.append("## 一、核心统计概览")
        lines.append("- 本期完成归档：\(archivedInRange.count) 项")
        lines.append("- 推进中与追踪中事项：\(activeTrackingTasks.count) 项（其中需继续追踪 \(followUpTasksCount) 项）")
        lines.append("- 当前逾期未处理：\(overdueCount) 项")
        lines.append("- 本期新增进展记录：\(logsInRangeCount) 条")
        lines.append("")

        // Section 2
        lines.append("## 二、已完成归档成果")
        if archivedInRange.isEmpty {
            lines.append("- 本统计周期内暂无已归档成果。")
        } else {
            for (index, task) in archivedInRange.enumerated() {
                let doneDate = formatDateTime(task.completedAt ?? task.updatedAt)
                lines.append("\(index + 1). [\(task.categoryTag)] \(task.title)（归档时间：\(doneDate)）")
                let summary = task.outcomeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty {
                    lines.append("   - 工作结果：\(summary)")
                }
                if config.includeDetailedTimeline {
                    appendLogs(
                        for: task,
                        startDate: normalizedStart,
                        endDate: normalizedEnd,
                        into: &lines
                    )
                }
            }
        }
        lines.append("")

        // Section 3
        lines.append("## 三、推进中与需继续追踪事项")
        if activeTrackingTasks.isEmpty {
            lines.append("- 当前暂无推进中或需继续追踪的工作事项。")
        } else {
            for (index, task) in activeTrackingTasks.enumerated() {
                let progressPercent = Int((task.progressFraction * 100).rounded())
                let overdueTag = task.isOverdue ? " · ⚠️ 已逾期" : ""
                lines.append("\(index + 1). [\(task.status.displayName) · \(task.priority.displayName)] \(task.title)（标签：\(task.categoryTag)，进度：\(progressPercent)%\(overdueTag)）")
                let outcome = task.outcomeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !outcome.isEmpty {
                    lines.append("   - 阶段结果：\(outcome)")
                }
                if config.includeDetailedTimeline {
                    appendLogs(
                        for: task,
                        startDate: normalizedStart,
                        endDate: normalizedEnd,
                        into: &lines
                    )
                }
            }
        }
        lines.append("")

        // Section 4
        lines.append("## 四、下阶段重点跟进计划")
        if !config.includePendingFollowUps {
            lines.append("- 已按配置省略待跟进计划明细。")
        } else if followUpPlanTasks.isEmpty {
            lines.append("- 暂无待跟进提醒或计划节点。")
        } else {
            for (index, task) in followUpPlanTasks.enumerated() {
                var scheduleParts: [String] = []
                if let nextFollowUp = task.nextFollowUpAt {
                    scheduleParts.append("下次追踪：\(formatDateTime(nextFollowUp))")
                }
                if let dueDate = task.dueDate {
                    scheduleParts.append("截止时间：\(formatDateTime(dueDate))")
                }
                let pendingCustom = task.customFollowUpSchedules
                    .filter { !$0.isCompleted }
                    .sorted { $0.scheduledAt < $1.scheduledAt }
                if let customFirst = pendingCustom.first {
                    let noteSuffix = customFirst.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? ""
                        : "（\(customFirst.note)）"
                    scheduleParts.append("自定义复追：\(formatDateTime(customFirst.scheduledAt))\(noteSuffix)")
                }
                let detailText = scheduleParts.isEmpty ? "待补充具体复追时间" : scheduleParts.joined(separator: " ｜ ")
                lines.append("\(index + 1). [\(task.categoryTag)] \(task.title) — \(detailText)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func earliestRelevantDate(for task: WorkTask) -> Date? {
        var dates: [Date] = []
        if let nextFollowUpAt = task.nextFollowUpAt {
            dates.append(nextFollowUpAt)
        }
        if let dueDate = task.dueDate {
            dates.append(dueDate)
        }
        dates.append(contentsOf: task.customFollowUpSchedules.filter { !$0.isCompleted }.map(\.scheduledAt))
        return dates.min()
    }

    private static func appendLogs(
        for task: WorkTask,
        startDate: Date,
        endDate: Date,
        into lines: inout [String]
    ) {
        let sortedLogs = task.logs.sorted { $0.createdAt < $1.createdAt }
        let rangeLogs = sortedLogs.filter { $0.createdAt >= startDate && $0.createdAt <= endDate }
        let logsToDisplay = rangeLogs.isEmpty ? Array(sortedLogs.suffix(3)) : rangeLogs
        for log in logsToDisplay {
            lines.append("   - [\(log.entryType.displayName) \(formatDateTime(log.createdAt))] \(log.content)")
        }
    }

    private static func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
