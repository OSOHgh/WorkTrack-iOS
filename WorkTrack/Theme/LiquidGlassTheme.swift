import SwiftUI

// MARK: - TaskTagColor, TaskStatus, TaskPriority & ProgressEntryType Theme Extensions

extension TaskTagColor {
    var swiftUIColor: Color {
        switch self {
        case .coral:
            return Color(red: 1.00, green: 0.42, blue: 0.35)
        case .amber:
            return Color(red: 0.98, green: 0.68, blue: 0.16)
        case .emerald:
            return Color(red: 0.16, green: 0.80, blue: 0.54)
        case .sky:
            return Color(red: 0.18, green: 0.68, blue: 0.98)
        case .indigo:
            return Color(red: 0.38, green: 0.44, blue: 0.96)
        case .violet:
            return Color(red: 0.66, green: 0.36, blue: 0.96)
        case .rose:
            return Color(red: 0.96, green: 0.33, blue: 0.58)
        case .teal:
            return Color(red: 0.12, green: 0.76, blue: 0.76)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .coral:
            return Color(red: 1.00, green: 0.58, blue: 0.42)
        case .amber:
            return Color(red: 1.00, green: 0.82, blue: 0.32)
        case .emerald:
            return Color(red: 0.32, green: 0.90, blue: 0.68)
        case .sky:
            return Color(red: 0.38, green: 0.82, blue: 1.00)
        case .indigo:
            return Color(red: 0.52, green: 0.58, blue: 1.00)
        case .violet:
            return Color(red: 0.80, green: 0.50, blue: 1.00)
        case .rose:
            return Color(red: 1.00, green: 0.52, blue: 0.72)
        case .teal:
            return Color(red: 0.28, green: 0.88, blue: 0.86)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [swiftUIColor, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension TaskStatus {
    var themeColor: Color {
        switch self {
        case .todo:
            return Color(red: 0.48, green: 0.56, blue: 0.68)
        case .inProgress:
            return Color(red: 0.18, green: 0.68, blue: 0.98)
        case .waiting:
            return Color(red: 0.98, green: 0.68, blue: 0.16)
        case .followUp:
            return Color(red: 0.66, green: 0.36, blue: 0.96)
        case .archived:
            return Color(red: 0.16, green: 0.80, blue: 0.54)
        case .cancelled:
            return Color.secondary
        }
    }
}

extension TaskPriority {
    var themeColor: Color {
        switch self {
        case .low:
            return Color(red: 0.32, green: 0.72, blue: 0.88)
        case .medium:
            return Color(red: 0.98, green: 0.66, blue: 0.16)
        case .high:
            return Color(red: 0.98, green: 0.30, blue: 0.36)
        }
    }
}

extension ProgressEntryType {
    var themeColor: Color {
        switch self {
        case .update:
            return Color(red: 0.18, green: 0.68, blue: 0.98)
        case .blocker:
            return Color(red: 0.98, green: 0.34, blue: 0.38)
        case .decision:
            return Color(red: 0.66, green: 0.36, blue: 0.96)
        case .outcome:
            return Color(red: 0.16, green: 0.80, blue: 0.54)
        case .followUpNote:
            return Color(red: 0.98, green: 0.68, blue: 0.16)
        }
    }
}

// MARK: - Liquid Glass View Modifiers (iOS 27.2.1 / iOS 26.0+ Compatible)

struct LiquidGlassCardModifier: ViewModifier {
    var tint: Color?
    var cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let baseShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let activeTint = tint ?? Color.accentColor

        content
            .background {
                ZStack {
                    baseShape
                        .fill(.ultraThinMaterial)

                    if let tint {
                        baseShape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(colorScheme == .dark ? 0.18 : 0.12),
                                        tint.opacity(colorScheme == .dark ? 0.06 : 0.03),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    // Specular top-edge inner reflection highlight
                    baseShape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.38 : 0.72),
                                    activeTint.opacity(tint != nil ? 0.35 : 0.15),
                                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.15
                        )
                }
                .shadow(
                    color: (tint ?? Color.black).opacity(colorScheme == .dark ? 0.26 : 0.09),
                    radius: 14,
                    x: 0,
                    y: 7
                )
            }
    }
}

struct LiquidGlassFloatingBarModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape
                        .fill(.regularMaterial)
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.38),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.45 : 0.85),
                                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.14),
                    radius: 18,
                    x: 0,
                    y: 8
                )
            }
    }
}

extension View {
    func liquidGlassCard(tint: Color? = nil, cornerRadius: CGFloat = 22) -> some View {
        modifier(LiquidGlassCardModifier(tint: tint, cornerRadius: cornerRadius))
    }

    func liquidGlassFloatingBar(cornerRadius: CGFloat = 28) -> some View {
        modifier(LiquidGlassFloatingBarModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Ambient Liquid Glass Canvas Background

struct LiquidGlassAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.06, green: 0.08, blue: 0.14),
                        Color(red: 0.09, green: 0.11, blue: 0.19),
                        Color(red: 0.07, green: 0.10, blue: 0.16)
                    ]
                    : [
                        Color(red: 0.94, green: 0.96, blue: 1.00),
                        Color(red: 0.96, green: 0.95, blue: 0.99),
                        Color(red: 0.92, green: 0.97, blue: 0.98)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                Circle()
                    .fill(TaskTagColor.sky.swiftUIColor.opacity(colorScheme == .dark ? 0.22 : 0.18))
                    .frame(width: width * 0.75, height: width * 0.75)
                    .blur(radius: 65)
                    .offset(x: -width * 0.22, y: -height * 0.08)

                Circle()
                    .fill(TaskTagColor.violet.swiftUIColor.opacity(colorScheme == .dark ? 0.18 : 0.14))
                    .frame(width: width * 0.70, height: width * 0.70)
                    .blur(radius: 70)
                    .offset(x: width * 0.38, y: height * 0.18)

                Circle()
                    .fill(TaskTagColor.emerald.swiftUIColor.opacity(colorScheme == .dark ? 0.15 : 0.13))
                    .frame(width: width * 0.65, height: width * 0.65)
                    .blur(radius: 65)
                    .offset(x: -width * 0.10, y: height * 0.56)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Reusable Vibrant Badges

struct TagColorBadge: View {
    let categoryTag: String
    let tagColor: TaskTagColor

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tagColor.gradient)
                .frame(width: 7, height: 7)
            Text(categoryTag.isEmpty ? "通用工作" : categoryTag)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(tagColor.swiftUIColor)
        .background(
            Capsule(style: .continuous)
                .fill(tagColor.swiftUIColor.opacity(0.15))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tagColor.swiftUIColor.opacity(0.35), lineWidth: 0.8)
                )
        )
    }
}

struct TaskStatusBadge: View {
    let status: TaskStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.caption2.weight(.semibold))
            Text(status.displayName)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(status.themeColor)
        .background(
            Capsule(style: .continuous)
                .fill(status.themeColor.opacity(0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(status.themeColor.opacity(0.32), lineWidth: 0.8)
                )
        )
    }
}

struct TaskPriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: priority.iconName)
                .font(.caption2.weight(.bold))
            Text(priority.displayName)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(priority.themeColor)
        .background(
            Capsule(style: .continuous)
                .fill(priority.themeColor.opacity(0.14))
        )
    }
}

struct ProgressEntryTypeBadge: View {
    let entryType: ProgressEntryType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entryType.systemImage)
                .font(.caption2.weight(.semibold))
            Text(entryType.displayName)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(entryType.themeColor)
        .background(
            Capsule(style: .continuous)
                .fill(entryType.themeColor.opacity(0.15))
        )
    }
}
