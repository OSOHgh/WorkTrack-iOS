import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case todo
    case inProgress
    case waiting
    case followUp
    case archived
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .todo:
            return "待开始"
        case .inProgress:
            return "推进中"
        case .waiting:
            return "等待反馈"
        case .followUp:
            return "需继续追踪"
        case .archived:
            return "已归档"
        case .cancelled:
            return "已取消"
        }
    }

    var systemImage: String {
        switch self {
        case .todo:
            return "circle"
        case .inProgress:
            return "play.circle.fill"
        case .waiting:
            return "hourglass.circle.fill"
        case .followUp:
            return "arrow.clockwise.circle.fill"
        case .archived:
            return "archivebox.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    var isActive: Bool {
        self != .archived && self != .cancelled
    }
}

enum TaskPriority: Int, Codable, CaseIterable, Identifiable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "普通"
        case .medium:
            return "重要"
        case .high:
            return "紧急"
        }
    }

    var iconName: String {
        switch self {
        case .low:
            return "flag"
        case .medium:
            return "flag.fill"
        case .high:
            return "exclamationmark.triangle.fill"
        }
    }
}

enum TaskTagColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case coral
    case amber
    case emerald
    case sky
    case indigo
    case violet
    case rose
    case teal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coral:
            return "珊瑚橘"
        case .amber:
            return "琥珀黄"
        case .emerald:
            return "薄荷绿"
        case .sky:
            return "晴空蓝"
        case .indigo:
            return "靛青蓝"
        case .violet:
            return "薰衣草紫"
        case .rose:
            return "玫瑰粉"
        case .teal:
            return "青碧色"
        }
    }
}

enum ProgressEntryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case update
    case blocker
    case decision
    case outcome
    case followUpNote

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .update:
            return "进展更新"
        case .blocker:
            return "卡点/阻塞"
        case .decision:
            return "关键决策"
        case .outcome:
            return "工作结果"
        case .followUpNote:
            return "复追记录"
        }
    }

    var systemImage: String {
        switch self {
        case .update:
            return "text.bubble.fill"
        case .blocker:
            return "exclamationmark.octagon.fill"
        case .decision:
            return "checkmark.seal.fill"
        case .outcome:
            return "flag.checkered"
        case .followUpNote:
            return "bell.badge.fill"
        }
    }
}

enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case document

    var displayName: String {
        switch self {
        case .image:
            return "图片/截图"
        case .document:
            return "文档附件"
        }
    }

    var systemImage: String {
        switch self {
        case .image:
            return "photo.fill"
        case .document:
            return "doc.fill"
        }
    }
}

enum DailyRoutineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case morningSummary
    case eveningReview
    case customRoutine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morningSummary:
            return "早间待办汇总"
        case .eveningReview:
            return "晚间复盘核对"
        case .customRoutine:
            return "自定义盘点提醒"
        }
    }

    var defaultHour: Int {
        switch self {
        case .morningSummary:
            return 9
        case .eveningReview:
            return 18
        case .customRoutine:
            return 14
        }
    }

    var defaultMinute: Int {
        switch self {
        case .morningSummary:
            return 0
        case .eveningReview:
            return 30
        case .customRoutine:
            return 0
        }
    }

    var defaultPrompt: String {
        switch self {
        case .morningSummary:
            return "开启今日工作：查看今日到期、逾期未处理及需继续追踪的重点任务。"
        case .eveningReview:
            return "今日工作复盘：更新未完成事项进展，确认需要继续追踪或归档的工作结果。"
        case .customRoutine:
            return "定时工作盘点：检查关键任务节点推进情况与后续跟进安排。"
        }
    }
}
