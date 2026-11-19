import Foundation
import SwiftData

struct WorkTrackBackupPayload: Codable, Sendable {
    struct ProgressLogSnapshot: Codable, Sendable {
        var id: UUID
        var createdAt: Date
        var content: String
        var entryTypeRaw: String
        var attachments: [AttachmentItem]
    }

    struct TaskSnapshot: Codable, Sendable {
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
        var subtasks: [SubtaskItem]
        var attachments: [AttachmentItem]
        var customFollowUpSchedules: [FollowUpScheduleItem]
        var logs: [ProgressLogSnapshot]
    }

    struct RoutineSnapshot: Codable, Sendable {
        var id: UUID
        var title: String
        var note: String
        var kindRaw: String
        var hour: Int
        var minute: Int
        var weekdays: [Int]
        var isEnabled: Bool
        var createdAt: Date
    }

    var schemaVersion: Int = 1
    var exportedAt: Date = Date()
    var tasks: [TaskSnapshot]
    var routines: [RoutineSnapshot]
    var attachmentFiles: [String: Data]
}

enum BackupService {
    @MainActor
    static func exportBackupData(modelContext: ModelContext) throws -> Data {
        try exportBackupData(modelContext: modelContext, attachmentStore: .shared)
    }

    @MainActor
    static func importBackupData(
        _ data: Data,
        into modelContext: ModelContext,
        clearExisting: Bool = false
    ) throws -> (restoredTasks: Int, restoredRoutines: Int) {
        try importBackupData(
            data,
            into: modelContext,
            clearExisting: clearExisting,
            attachmentStore: .shared
        )
    }

    @MainActor
    static func exportBackupData(
        modelContext: ModelContext,
        attachmentStore: AttachmentStore
    ) throws -> Data {
        let tasks = try modelContext.fetch(FetchDescriptor<WorkTask>())
        let routines = try modelContext.fetch(FetchDescriptor<RoutineReminderRule>())

        var attachmentFiles: [String: Data] = [:]

        let taskSnapshots: [WorkTrackBackupPayload.TaskSnapshot] = tasks.map { task in
            for item in task.attachments where attachmentFiles[item.relativePath] == nil {
                if let fileData = attachmentStore.readData(for: item) {
                    attachmentFiles[item.relativePath] = fileData
                }
            }

            let logSnapshots: [WorkTrackBackupPayload.ProgressLogSnapshot] = task.logs
                .sorted { $0.createdAt < $1.createdAt }
                .map { log in
                    for item in log.attachments where attachmentFiles[item.relativePath] == nil {
                        if let fileData = attachmentStore.readData(for: item) {
                            attachmentFiles[item.relativePath] = fileData
                        }
                    }
                    return WorkTrackBackupPayload.ProgressLogSnapshot(
                        id: log.id,
                        createdAt: log.createdAt,
                        content: log.content,
                        entryTypeRaw: log.entryTypeRaw,
                        attachments: log.attachments
                    )
                }

            return WorkTrackBackupPayload.TaskSnapshot(
                id: task.id,
                title: task.title,
                taskDescription: task.taskDescription,
                categoryTag: task.categoryTag,
                tagColorRaw: task.tagColorRaw,
                priorityRaw: task.priorityRaw,
                statusRaw: task.statusRaw,
                createdAt: task.createdAt,
                updatedAt: task.updatedAt,
                dueDate: task.dueDate,
                nextFollowUpAt: task.nextFollowUpAt,
                completedAt: task.completedAt,
                outcomeSummary: task.outcomeSummary,
                needsContinuedTracking: task.needsContinuedTracking,
                subtasks: task.subtasks,
                attachments: task.attachments,
                customFollowUpSchedules: task.customFollowUpSchedules,
                logs: logSnapshots
            )
        }

        let routineSnapshots: [WorkTrackBackupPayload.RoutineSnapshot] = routines.map { rule in
            WorkTrackBackupPayload.RoutineSnapshot(
                id: rule.id,
                title: rule.title,
                note: rule.note,
                kindRaw: rule.kindRaw,
                hour: rule.hour,
                minute: rule.minute,
                weekdays: rule.weekdays,
                isEnabled: rule.isEnabled,
                createdAt: rule.createdAt
            )
        }

        let payload = WorkTrackBackupPayload(
            schemaVersion: 1,
            exportedAt: Date(),
            tasks: taskSnapshots,
            routines: routineSnapshots,
            attachmentFiles: attachmentFiles
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    @MainActor
    static func importBackupData(
        _ data: Data,
        into modelContext: ModelContext,
        clearExisting: Bool = false,
        attachmentStore: AttachmentStore
    ) throws -> (restoredTasks: Int, restoredRoutines: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(WorkTrackBackupPayload.self, from: data)

        if clearExisting {
            let existingTasks = try modelContext.fetch(FetchDescriptor<WorkTask>())
            for task in existingTasks {
                modelContext.delete(task)
            }
            let existingRoutines = try modelContext.fetch(FetchDescriptor<RoutineReminderRule>())
            for routine in existingRoutines {
                modelContext.delete(routine)
            }
            try modelContext.save()
        }

        for (relativePath, bytes) in payload.attachmentFiles {
            try attachmentStore.restoreAttachmentFile(relativePath: relativePath, data: bytes)
        }

        let currentTasks = try modelContext.fetch(FetchDescriptor<WorkTask>())
        var existingTasksByID: [UUID: WorkTask] = Dictionary(uniqueKeysWithValues: currentTasks.map { ($0.id, $0) })

        let currentRoutines = try modelContext.fetch(FetchDescriptor<RoutineReminderRule>())
        var existingRoutinesByID: [UUID: RoutineReminderRule] = Dictionary(uniqueKeysWithValues: currentRoutines.map { ($0.id, $0) })

        var deletedConflicts = false
        for snapshot in payload.tasks {
            if let existing = existingTasksByID.removeValue(forKey: snapshot.id) {
                modelContext.delete(existing)
                deletedConflicts = true
            }
        }
        for snapshot in payload.routines {
            if let existing = existingRoutinesByID.removeValue(forKey: snapshot.id) {
                modelContext.delete(existing)
                deletedConflicts = true
            }
        }
        if deletedConflicts {
            try modelContext.save()
        }

        var restoredTasksCount = 0
        for snapshot in payload.tasks {
            let task = WorkTask(
                id: snapshot.id,
                title: snapshot.title,
                taskDescription: snapshot.taskDescription,
                categoryTag: snapshot.categoryTag,
                tagColor: TaskTagColor(rawValue: snapshot.tagColorRaw) ?? .sky,
                priority: TaskPriority(rawValue: snapshot.priorityRaw) ?? .medium,
                status: TaskStatus(rawValue: snapshot.statusRaw) ?? .todo,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                dueDate: snapshot.dueDate,
                nextFollowUpAt: snapshot.nextFollowUpAt,
                completedAt: snapshot.completedAt,
                outcomeSummary: snapshot.outcomeSummary,
                needsContinuedTracking: snapshot.needsContinuedTracking,
                subtasks: snapshot.subtasks,
                attachments: snapshot.attachments,
                customFollowUpSchedules: snapshot.customFollowUpSchedules,
                logs: []
            )
            modelContext.insert(task)

            for logSnapshot in snapshot.logs {
                let log = ProgressLog(
                    id: logSnapshot.id,
                    createdAt: logSnapshot.createdAt,
                    content: logSnapshot.content,
                    entryType: ProgressEntryType(rawValue: logSnapshot.entryTypeRaw) ?? .update,
                    attachments: logSnapshot.attachments,
                    task: nil
                )
                modelContext.insert(log)
                task.logs.append(log)
            }

            restoredTasksCount += 1
        }

        var restoredRoutinesCount = 0
        for snapshot in payload.routines {
            let rule = RoutineReminderRule(
                id: snapshot.id,
                title: snapshot.title,
                note: snapshot.note,
                kind: DailyRoutineKind(rawValue: snapshot.kindRaw) ?? .customRoutine,
                hour: snapshot.hour,
                minute: snapshot.minute,
                weekdays: snapshot.weekdays,
                isEnabled: snapshot.isEnabled,
                createdAt: snapshot.createdAt
            )
            modelContext.insert(rule)
            restoredRoutinesCount += 1
        }

        try modelContext.save()
        return (restoredTasksCount, restoredRoutinesCount)
    }
}
