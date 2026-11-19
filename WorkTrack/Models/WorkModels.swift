import Foundation
import SwiftData

struct SubtaskItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
    var completedAt: Date? = nil

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}

struct AttachmentItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var fileName: String
    var relativePath: String
    var kind: AttachmentKind
    var fileSize: Int64
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        fileName: String,
        relativePath: String,
        kind: AttachmentKind,
        fileSize: Int64,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.relativePath = relativePath
        self.kind = kind
        self.fileSize = fileSize
        self.createdAt = createdAt
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct FollowUpScheduleItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var scheduledAt: Date
    var note: String = ""
    var isOverdueRetry: Bool = false
    var isCompleted: Bool = false

    init(
        id: UUID = UUID(),
        scheduledAt: Date,
        note: String = "",
        isOverdueRetry: Bool = false,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.scheduledAt = scheduledAt
        self.note = note
        self.isOverdueRetry = isOverdueRetry
        self.isCompleted = isCompleted
    }
}

private enum ModelJSONCodec {
    static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        return (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, fallback: T) -> T {
        guard !data.isEmpty else { return fallback }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(type, from: data) {
            return decoded
        }
        // Fallback to ISO8601 strategy if legacy data used ISO8601 string dates
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        return (try? isoDecoder.decode(type, from: data)) ?? fallback
    }
}

@Model
final class WorkTask {
    var id: UUID
    var title: String
    var taskDescription: String
    var categoryTag: String
    var tagColorRaw: String
    var priorityRaw: Int
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var dueDate: Date?
    var nextFollowUpAt: Date?
    var completedAt: Date?
    var outcomeSummary: String
    var needsContinuedTracking: Bool
    var subtasksData: Data
    var attachmentsData: Data
    var customFollowUpSchedulesData: Data

    @Relationship(deleteRule: .cascade, inverse: \ProgressLog.task)
    var logs: [ProgressLog]

    init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        categoryTag: String = "日常工作",
        tagColor: TaskTagColor = .sky,
        priority: TaskPriority = .medium,
        status: TaskStatus = .todo,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dueDate: Date? = nil,
        nextFollowUpAt: Date? = nil,
        completedAt: Date? = nil,
        outcomeSummary: String = "",
        needsContinuedTracking: Bool = false,
        subtasks: [SubtaskItem] = [],
        attachments: [AttachmentItem] = [],
        customFollowUpSchedules: [FollowUpScheduleItem] = [],
        logs: [ProgressLog] = []
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.categoryTag = categoryTag
        self.tagColorRaw = tagColor.rawValue
        self.priorityRaw = priority.rawValue
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.nextFollowUpAt = nextFollowUpAt
        self.completedAt = completedAt
        self.outcomeSummary = outcomeSummary
        self.needsContinuedTracking = needsContinuedTracking
        self.subtasksData = ModelJSONCodec.encode(subtasks)
        self.attachmentsData = ModelJSONCodec.encode(attachments)
        self.customFollowUpSchedulesData = ModelJSONCodec.encode(customFollowUpSchedules)
        self.logs = logs
    }

    var tagColor: TaskTagColor {
        get { TaskTagColor(rawValue: tagColorRaw) ?? .sky }
        set {
            tagColorRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set {
            priorityRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set {
            statusRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var subtasks: [SubtaskItem] {
        get { ModelJSONCodec.decode([SubtaskItem].self, from: subtasksData, fallback: []) }
        set {
            subtasksData = ModelJSONCodec.encode(newValue)
            updatedAt = Date()
        }
    }

    var attachments: [AttachmentItem] {
        get { ModelJSONCodec.decode([AttachmentItem].self, from: attachmentsData, fallback: []) }
        set {
            attachmentsData = ModelJSONCodec.encode(newValue)
            updatedAt = Date()
        }
    }

    var customFollowUpSchedules: [FollowUpScheduleItem] {
        get { ModelJSONCodec.decode([FollowUpScheduleItem].self, from: customFollowUpSchedulesData, fallback: []) }
        set {
            customFollowUpSchedulesData = ModelJSONCodec.encode(newValue)
            updatedAt = Date()
        }
    }

    var progressFraction: Double {
        let currentSubtasks = subtasks
        if !currentSubtasks.isEmpty {
            let doneCount = currentSubtasks.filter(\.isCompleted).count
            return Double(doneCount) / Double(currentSubtasks.count)
        }
        switch status {
        case .archived:
            return 1.0
        case .followUp:
            return 0.75
        case .waiting:
            return 0.5
        case .inProgress:
            return 0.4
        case .todo, .cancelled:
            return 0.0
        }
    }

    var isOverdue: Bool {
        guard status.isActive else { return false }
        let now = Date()
        if let dueDate, dueDate < now {
            return true
        }
        if let nextFollowUpAt, nextFollowUpAt < now {
            return true
        }
        return false
    }

    var upcomingReminderDates: [Date] {
        let now = Date()
        var candidates: [Date] = []
        if let dueDate, dueDate > now {
            candidates.append(dueDate)
        }
        if let nextFollowUpAt, nextFollowUpAt > now {
            candidates.append(nextFollowUpAt)
        }
        for item in customFollowUpSchedules where !item.isCompleted && item.scheduledAt > now {
            candidates.append(item.scheduledAt)
        }
        let sorted = candidates.sorted()
        var deduplicated: [Date] = []
        for date in sorted {
            if let last = deduplicated.last, abs(date.timeIntervalSince(last)) < 1.0 {
                continue
            }
            deduplicated.append(date)
        }
        return deduplicated
    }

    @discardableResult
    func addProgressLog(
        content: String,
        type: ProgressEntryType = .update,
        attachments: [AttachmentItem] = []
    ) -> ProgressLog {
        let log = ProgressLog(
            content: content,
            entryType: type,
            attachments: attachments,
            task: nil
        )
        modelContext?.insert(log)
        logs.append(log)
        updatedAt = Date()
        return log
    }

    func addManualFollowUp(at date: Date, note: String = "", isOverdueRetry: Bool = false) {
        var schedules = customFollowUpSchedules
        schedules.append(
            FollowUpScheduleItem(
                scheduledAt: date,
                note: note,
                isOverdueRetry: isOverdueRetry,
                isCompleted: false
            )
        )
        schedules.sort { $0.scheduledAt < $1.scheduledAt }
        customFollowUpSchedules = schedules

        let now = Date()
        let uncompletedDates = schedules.filter { !$0.isCompleted }.map(\.scheduledAt)
        if let nextUpcoming = uncompletedDates.first(where: { $0 >= now }) ?? uncompletedDates.first {
            if let existingNext = nextFollowUpAt {
                if existingNext < now || nextUpcoming < existingNext {
                    nextFollowUpAt = nextUpcoming
                }
            } else {
                nextFollowUpAt = nextUpcoming
            }
        }
        updatedAt = now
    }

    func removeManualFollowUp(id: UUID) {
        var schedules = customFollowUpSchedules
        let removed = schedules.first { $0.id == id }
        schedules.removeAll { $0.id == id }
        customFollowUpSchedules = schedules

        if let removed,
           let existingNext = nextFollowUpAt,
           abs(existingNext.timeIntervalSince(removed.scheduledAt)) < 1.0 {
            let now = Date()
            let remaining = schedules.filter { !$0.isCompleted }.map(\.scheduledAt).sorted()
            nextFollowUpAt = remaining.first(where: { $0 >= now }) ?? remaining.first
        }
        updatedAt = Date()
    }

    func recordOutcome(
        summary: String,
        needsContinuedTracking: Bool,
        followUpDates: [Date] = [],
        followUpNote: String = "",
        newAttachments: [AttachmentItem] = []
    ) {
        let now = Date()
        outcomeSummary = summary
        self.needsContinuedTracking = needsContinuedTracking

        if !newAttachments.isEmpty {
            var currentAttachments = attachments
            currentAttachments.append(contentsOf: newAttachments)
            attachments = currentAttachments
        }

        let logContent = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (needsContinuedTracking ? "已记录阶段结果，转入继续追踪" : "已确认完成并归档")
            : summary
        addProgressLog(content: logContent, type: .outcome, attachments: newAttachments)

        if needsContinuedTracking {
            status = .followUp
            completedAt = nil

            let sortedDates = followUpDates.sorted()
            if !sortedDates.isEmpty {
                var schedules = customFollowUpSchedules
                for date in sortedDates {
                    schedules.append(
                        FollowUpScheduleItem(
                            scheduledAt: date,
                            note: followUpNote,
                            isOverdueRetry: false,
                            isCompleted: false
                        )
                    )
                }
                schedules.sort { $0.scheduledAt < $1.scheduledAt }
                customFollowUpSchedules = schedules
            }

            nextFollowUpAt = sortedDates.first ?? now.addingTimeInterval(86400)
        } else {
            status = .archived
            completedAt = now
            nextFollowUpAt = nil

            var schedules = customFollowUpSchedules
            for index in schedules.indices {
                schedules[index].isCompleted = true
            }
            customFollowUpSchedules = schedules
        }

        updatedAt = now
    }

    func reopenForTracking(nextFollowUpAt: Date?, note: String = "重新激活追踪") {
        let now = Date()
        status = .followUp
        needsContinuedTracking = true
        completedAt = nil
        self.nextFollowUpAt = nextFollowUpAt
        updatedAt = now

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        addProgressLog(
            content: trimmedNote.isEmpty ? "重新激活追踪" : trimmedNote,
            type: .followUpNote
        )
    }
}

@Model
final class ProgressLog {
    var id: UUID
    var createdAt: Date
    var content: String
    var entryTypeRaw: String
    var attachmentsData: Data
    var task: WorkTask?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        content: String,
        entryType: ProgressEntryType = .update,
        attachments: [AttachmentItem] = [],
        task: WorkTask? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.content = content
        self.entryTypeRaw = entryType.rawValue
        self.attachmentsData = ModelJSONCodec.encode(attachments)
        self.task = task
    }

    var entryType: ProgressEntryType {
        get { ProgressEntryType(rawValue: entryTypeRaw) ?? .update }
        set { entryTypeRaw = newValue.rawValue }
    }

    var attachments: [AttachmentItem] {
        get { ModelJSONCodec.decode([AttachmentItem].self, from: attachmentsData, fallback: []) }
        set { attachmentsData = ModelJSONCodec.encode(newValue) }
    }
}

@Model
final class RoutineReminderRule {
    var id: UUID
    var title: String
    var note: String
    var kindRaw: String
    var hour: Int
    var minute: Int
    var weekdaysData: Data
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        kind: DailyRoutineKind = .customRoutine,
        hour: Int? = nil,
        minute: Int? = nil,
        weekdays: [Int] = [2, 3, 4, 5, 6],
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note.isEmpty ? kind.defaultPrompt : note
        self.kindRaw = kind.rawValue
        self.hour = hour ?? kind.defaultHour
        self.minute = minute ?? kind.defaultMinute
        self.weekdaysData = ModelJSONCodec.encode(weekdays)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    var kind: DailyRoutineKind {
        get { DailyRoutineKind(rawValue: kindRaw) ?? .customRoutine }
        set { kindRaw = newValue.rawValue }
    }

    var weekdays: [Int] {
        get { ModelJSONCodec.decode([Int].self, from: weekdaysData, fallback: [2, 3, 4, 5, 6]) }
        set { weekdaysData = ModelJSONCodec.encode(newValue) }
    }

    var formattedTime: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var formattedWeekdays: String {
        let validSet = Set(weekdays.filter { (1...7).contains($0) })
        if validSet.isEmpty {
            return "未设置"
        }
        if validSet == Set(1...7) {
            return "每天"
        }
        if validSet == Set([2, 3, 4, 5, 6]) {
            return "工作日"
        }
        if validSet == Set([1, 7]) {
            return "周末"
        }

        let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
        let labels: [Int: String] = [
            1: "周日",
            2: "周一",
            3: "周二",
            4: "周三",
            5: "周四",
            6: "周五",
            7: "周六"
        ]
        return orderedWeekdays
            .filter { validSet.contains($0) }
            .compactMap { labels[$0] }
            .joined(separator: "、")
    }
}
