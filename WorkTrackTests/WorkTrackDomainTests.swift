import XCTest
import SwiftData
@testable import WorkTrack

@MainActor
final class WorkTrackDomainTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var tempAttachmentsURL: URL!
    private var testAttachmentStore: AttachmentStore!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([WorkTask.self, ProgressLog.self, RoutineReminderRule.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        tempAttachmentsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkTrackTests-\(UUID().uuidString)", isDirectory: true)
        testAttachmentStore = AttachmentStore(baseDirectoryURL: tempAttachmentsURL)
    }

    override func tearDown() async throws {
        if let tempAttachmentsURL {
            try? FileManager.default.removeItem(at: tempAttachmentsURL)
        }
        context = nil
        container = nil
        testAttachmentStore = nil
        try await super.tearDown()
    }

    func testWorkTaskCreationAndComputedProperties() {
        let now = Date()
        let pastDue = now.addingTimeInterval(-3600)
        let futureFollowUp = now.addingTimeInterval(7200)

        let task = WorkTask(
            title: "季度产品需求评审",
            taskDescription: "对齐研发与测试排期",
            categoryTag: "产品规划",
            tagColor: .coral,
            priority: .high,
            status: .inProgress,
            dueDate: pastDue,
            subtasks: [
                SubtaskItem(title: "整理 PRD", isCompleted: true, completedAt: now),
                SubtaskItem(title: "组织评审会", isCompleted: false)
            ]
        )
        task.addManualFollowUp(at: futureFollowUp, note: "确认测试排期", isOverdueRetry: false)
        context.insert(task)

        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.tagColor, .coral)
        XCTAssertEqual(task.progressFraction, 0.5, accuracy: 0.001)
        XCTAssertTrue(task.isOverdue)
        XCTAssertEqual(task.upcomingReminderDates, [futureFollowUp])
    }

    func testProgressLogging() throws {
        let task = WorkTask(title: "接口联调与压测", categoryTag: "后端", tagColor: .indigo)
        context.insert(task)

        let imageBytes = Data("mock-png-bytes".utf8)
        let attachment = try testAttachmentStore.saveImageData(imageBytes, suggestedName: "latency.png")

        let log = task.addProgressLog(
            content: "已完成核心接口压测，P99 耗时下降 30%",
            type: .update,
            attachments: [attachment]
        )
        try context.save()

        XCTAssertEqual(task.logs.count, 1)
        XCTAssertEqual(log.entryType, .update)
        XCTAssertEqual(log.attachments.count, 1)
        XCTAssertEqual(log.attachments.first?.fileName, "latency.png")
        XCTAssertEqual(testAttachmentStore.readData(for: attachment), imageBytes)
    }

    func testRecordOutcomeContinuedTrackingAndArchive() throws {
        let task = WorkTask(
            title: "客户验收交付",
            categoryTag: "项目交付",
            tagColor: .emerald,
            status: .inProgress
        )
        context.insert(task)

        let followUp1 = Date().addingTimeInterval(3600 * 4)
        let followUp2 = Date().addingTimeInterval(3600 * 24)
        let docData = Data("验收意见清单".utf8)
        let resultAttachment = try testAttachmentStore.saveImageData(docData, suggestedName: "feedback.png")

        task.recordOutcome(
            summary: "客户初步通过演示，需跟进两项细节修改",
            needsContinuedTracking: true,
            followUpDates: [followUp2, followUp1],
            followUpNote: "确认细节修改闭环",
            newAttachments: [resultAttachment]
        )

        XCTAssertEqual(task.status, .followUp)
        XCTAssertTrue(task.needsContinuedTracking)
        XCTAssertNil(task.completedAt)
        XCTAssertEqual(task.nextFollowUpAt, followUp1)
        XCTAssertEqual(task.customFollowUpSchedules.count, 2)
        XCTAssertEqual(task.attachments.count, 1)
        XCTAssertEqual(task.logs.last?.entryType, .outcome)

        task.recordOutcome(
            summary: "全部修改已确认，正式签收归档",
            needsContinuedTracking: false
        )

        XCTAssertEqual(task.status, .archived)
        XCTAssertFalse(task.status.isActive)
        XCTAssertFalse(task.needsContinuedTracking)
        XCTAssertNotNil(task.completedAt)
        XCTAssertNil(task.nextFollowUpAt)
        XCTAssertTrue(task.customFollowUpSchedules.allSatisfy(\.isCompleted))
        XCTAssertEqual(task.progressFraction, 1.0, accuracy: 0.001)

        let reactivatedDate = Date().addingTimeInterval(7200)
        task.reopenForTracking(nextFollowUpAt: reactivatedDate, note: "客户新增补充需求")
        XCTAssertEqual(task.status, .followUp)
        XCTAssertNil(task.completedAt)
        XCTAssertEqual(task.nextFollowUpAt, reactivatedDate)
        XCTAssertEqual(task.logs.last?.entryType, .followUpNote)
    }

    func testManualOverdueFollowUpScheduling() {
        let pastDue = Date().addingTimeInterval(-7200)
        let retryAt = Date().addingTimeInterval(3600)
        let task = WorkTask(
            title: "法务合同复核",
            status: .waiting,
            dueDate: pastDue
        )
        context.insert(task)

        XCTAssertTrue(task.isOverdue)

        task.addManualFollowUp(at: retryAt, note: "逾期二次提醒法务同事", isOverdueRetry: true)
        XCTAssertEqual(task.customFollowUpSchedules.count, 1)
        XCTAssertEqual(task.customFollowUpSchedules.first?.isOverdueRetry, true)
        XCTAssertEqual(task.nextFollowUpAt, retryAt)

        if let scheduleID = task.customFollowUpSchedules.first?.id {
            task.removeManualFollowUp(id: scheduleID)
        }
        XCTAssertTrue(task.customFollowUpSchedules.isEmpty)
        XCTAssertNil(task.nextFollowUpAt)
    }

    func testReportGeneratorOutput() {
        let now = Date()
        let interval = ReportGenerator.dateInterval(for: .thisWeek, now: now)

        let archivedTask = WorkTask(
            title: "上线灰度监控告警",
            categoryTag: "运维",
            tagColor: .teal,
            priority: .high,
            status: .archived,
            completedAt: now,
            outcomeSummary: "已完成全链路监控覆盖并归档"
        )
        archivedTask.addProgressLog(content: "灰度集群观测 24 小时无异常", type: .decision)

        let activeTask = WorkTask(
            title: "新版首页视觉走查",
            categoryTag: "设计",
            tagColor: .violet,
            priority: .medium,
            status: .followUp,
            nextFollowUpAt: now.addingTimeInterval(3600 * 5),
            outcomeSummary: "待调整深色模式卡片对比度",
            needsContinuedTracking: true
        )
        activeTask.addProgressLog(content: "已同步最新标注图", type: .update)

        let config = ReportConfiguration(
            preset: .thisWeek,
            startDate: interval.start,
            endDate: interval.end,
            includeDetailedTimeline: true,
            includePendingFollowUps: true
        )

        let report = ReportGenerator.generateTextReport(tasks: [archivedTask, activeTask], config: config)

        XCTAssertTrue(report.contains("一、核心统计概览"))
        XCTAssertTrue(report.contains("二、已完成归档成果"))
        XCTAssertTrue(report.contains("三、推进中与需继续追踪事项"))
        XCTAssertTrue(report.contains("四、下阶段重点跟进计划"))
        XCTAssertTrue(report.contains("上线灰度监控告警"))
        XCTAssertTrue(report.contains("新版首页视觉走查"))
        XCTAssertTrue(report.contains("灰度集群观测 24 小时无异常"))
    }

    func testBackupServiceRoundTrip() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let attachment = try testAttachmentStore.saveImageData(imageData, suggestedName: "evidence.png")

        let task = WorkTask(
            title: "备份还原验证任务",
            taskDescription: "验证任务、进展、附件与提醒规则完整恢复",
            categoryTag: "质量保障",
            tagColor: .amber,
            priority: .high,
            status: .followUp,
            nextFollowUpAt: Date().addingTimeInterval(3600),
            outcomeSummary: "首轮验证完成",
            needsContinuedTracking: true,
            subtasks: [SubtaskItem(title: "校验 JSON 导出", isCompleted: true)],
            attachments: [attachment]
        )
        task.addManualFollowUp(at: Date().addingTimeInterval(7200), note: "二次复查", isOverdueRetry: true)
        task.addProgressLog(content: "已附带截图日志", type: .update, attachments: [attachment])
        context.insert(task)

        let morningRule = RoutineReminderRule(
            title: "早间待办汇总",
            kind: .morningSummary,
            hour: 9,
            minute: 0,
            weekdays: [2, 3, 4, 5, 6],
            isEnabled: true
        )
        context.insert(morningRule)
        try context.save()

        let exportedData = try BackupService.exportBackupData(
            modelContext: context,
            attachmentStore: testAttachmentStore
        )

        // Remove original attachment file before restoring into a fresh in-memory container
        testAttachmentStore.deleteAttachment(attachment)
        XCTAssertNil(testAttachmentStore.readData(for: attachment))

        let restoreSchema = Schema([WorkTask.self, ProgressLog.self, RoutineReminderRule.self])
        let restoreConfig = ModelConfiguration(schema: restoreSchema, isStoredInMemoryOnly: true)
        let restoreContainer = try ModelContainer(for: restoreSchema, configurations: [restoreConfig])
        let restoreContext = ModelContext(restoreContainer)

        let summary = try BackupService.importBackupData(
            exportedData,
            into: restoreContext,
            clearExisting: true,
            attachmentStore: testAttachmentStore
        )

        XCTAssertEqual(summary.restoredTasks, 1)
        XCTAssertEqual(summary.restoredRoutines, 1)

        let restoredTasks = try restoreContext.fetch(FetchDescriptor<WorkTask>())
        let restoredRoutines = try restoreContext.fetch(FetchDescriptor<RoutineReminderRule>())

        XCTAssertEqual(restoredTasks.count, 1)
        XCTAssertEqual(restoredTasks.first?.title, "备份还原验证任务")
        XCTAssertEqual(restoredTasks.first?.logs.count, 1)
        XCTAssertEqual(restoredTasks.first?.subtasks.count, 1)
        XCTAssertEqual(restoredTasks.first?.customFollowUpSchedules.count, 1)
        XCTAssertEqual(testAttachmentStore.readData(for: attachment), imageData)

        XCTAssertEqual(restoredRoutines.count, 1)
        XCTAssertEqual(restoredRoutines.first?.formattedTime, "09:00")
        XCTAssertEqual(restoredRoutines.first?.formattedWeekdays, "工作日")
    }
}
