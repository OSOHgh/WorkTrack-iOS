import SwiftUI

struct ConfirmableDatePickerRow: View {
    let title: String
    @Binding var selection: Date
    var displayedComponents: DatePickerComponents = [.date, .hourAndMinute]
    var accentColor: Color = TaskTagColor.sky.swiftUIColor
    var showQuickPresets: Bool = true
    var onConfirm: ((Date) -> Void)? = nil

    @State private var isPresented: Bool = false
    @State private var draftDate: Date = Date()

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Button {
                draftDate = selection
                isPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.caption.weight(.semibold))
                    Text(formattedDisplayText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .opacity(0.75)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(accentColor)
                .background(
                    Capsule(style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(accentColor.opacity(0.32), lineWidth: 0.9)
                        )
                )
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ZStack {
                    LiquidGlassAmbientBackground()

                    ScrollView {
                        VStack(spacing: 16) {
                            if showQuickPresets && displayedComponents == [.date, .hourAndMinute] {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        presetChip("1小时后", date: Date().addingTimeInterval(3600))
                                        presetChip("3小时后", date: Date().addingTimeInterval(3600 * 3))
                                        presetChip("今天 18:00", date: Self.todayAt(hour: 18, minute: 0))
                                        presetChip("明早 09:30", date: Self.daysFromTodayAt(days: 1, hour: 9, minute: 30))
                                        presetChip("3天后 09:30", date: Self.daysFromTodayAt(days: 3, hour: 9, minute: 30))
                                    }
                                    .padding(.vertical, 2)
                                }
                            }

                            VStack(spacing: 10) {
                                Text("已选：\(formattedDraftPreview)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(accentColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if displayedComponents == [.hourAndMinute] {
                                    DatePicker(
                                        title,
                                        selection: $draftDate,
                                        displayedComponents: displayedComponents
                                    )
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                } else {
                                    DatePicker(
                                        title,
                                        selection: $draftDate,
                                        displayedComponents: displayedComponents
                                    )
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                    .tint(accentColor)
                                }
                            }
                            .padding(14)
                            .liquidGlassCard(tint: accentColor, cornerRadius: 18)

                            Button {
                                confirmAndClose()
                            } label: {
                                Label("确认选择时间", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .foregroundStyle(.white)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [accentColor, accentColor.opacity(0.82)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .adaptiveScreenContainer()
                        .padding(.vertical, 14)
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            isPresented = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确认") {
                            confirmAndClose()
                        }
                        .fontWeight(.bold)
                    }
                }
            }
            .presentationDetents(displayedComponents == [.hourAndMinute] ? [.medium] : [.fraction(0.78), .large])
        }
    }

    private var iconName: String {
        if displayedComponents == [.hourAndMinute] {
            return "clock"
        } else if displayedComponents == [.date] {
            return "calendar"
        }
        return "calendar.badge.clock"
    }

    private var formattedDisplayText: String {
        Self.format(selection, components: displayedComponents)
    }

    private var formattedDraftPreview: String {
        Self.format(draftDate, components: displayedComponents)
    }

    private func confirmAndClose() {
        selection = draftDate
        onConfirm?(draftDate)
        isPresented = false
    }

    private func presetChip(_ label: String, date: Date) -> some View {
        Button {
            draftDate = date
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(accentColor)
                .background(
                    Capsule(style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(accentColor.opacity(0.3), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private static func format(_ date: Date, components: DatePickerComponents) -> String {
        if components == [.hourAndMinute] {
            return date.formatted(date: .omitted, time: .shortened)
        } else if components == [.date] {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func todayAt(hour: Int, minute: Int) -> Date {
        let now = Date()
        let candidate = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return candidate > now ? candidate : daysFromTodayAt(days: 1, hour: hour, minute: minute)
    }

    private static func daysFromTodayAt(days: Int, hour: Int, minute: Int) -> Date {
        let targetDay = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay) ?? targetDay
    }
}
