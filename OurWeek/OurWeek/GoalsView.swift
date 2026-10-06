import SwiftUI

struct GoalsView: View {
    @State private var center = GoalsCenter.shared
    @State private var creating = false
    @State private var editing: Goal?
    @State private var detail: Goal?
    @State private var showSettings = false
    @State private var showArchived = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if center.activeGoals.isEmpty {
                    empty
                } else {
                    VStack(spacing: 10) {
                        ForEach(center.activeGoals) { goal in
                            goalRow(goal)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 140)
        }
        .background(Color.bgBase)
        .sheet(isPresented: $creating) {
            GoalEditor(goal: nil) { center.save($0) }
        }
        .sheet(item: $editing) { goal in
            GoalEditor(goal: goal) { center.save($0) }
        }
        .sheet(item: $detail) { goal in
            GoalDetailSheet(goalID: goal.id)
        }
        .sheet(isPresented: $showSettings) {
            GoalSettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.bgBase)
        }
        .sheet(isPresented: $showArchived) {
            ArchivedGoalsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.bgBase)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Goals")
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            Spacer()
            if center.undoAction != nil {
                Button("Undo") { center.undoLast() }
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Color.terra500)
                    .buttonStyle(.plain)
            }
            Menu {
                Button("New goal", action: { creating = true })
                Button("Archived", action: { showArchived = true })
                Button("Settings", action: { showSettings = true })
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Goal options")
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No goals yet")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            Button { creating = true } label: {
                Text("New goal")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.terra500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
    }

    private func goalRow(_ goal: Goal) -> some View {
        let current = center.progress(goal)
        let streak = center.streak(for: goal)
        let scheduled = center.isScheduled(goal, on: Date())
        return Button {
            if scheduled {
                center.bump(goal.id)
            } else {
                detail = fresh(goal.id)
            }
        } label: {
            HStack(spacing: 12) {
                GoalMark(goal: goal, current: current, diameter: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                        .lineLimit(1)
                    if !scheduled {
                        Text("Not today")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                    } else if streak > 0 {
                        Text(streakLabel(streak, period: goal.period))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                    }
                }
                Spacer(minLength: 8)
                if goal.kind != .check {
                    Text(progressText(current, goal: goal))
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.quiet)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeQuietCard()
            .contentShape(HomeQuiet.card)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Adjust") { detail = fresh(goal.id) }
            Button("Edit") { editing = fresh(goal.id) }
            Button("Archive") { center.archive(goal.id) }
        }
        .accessibilityLabel(scheduled ? accessibility(goal, current: current) : "Open \(goal.name)")
    }

    private func fresh(_ id: UUID) -> Goal? {
        center.goals.first { $0.id == id }
    }

    private func streakLabel(_ count: Int, period: GoalPeriod) -> String {
        let unit = period == .week ? "week" : "day"
        return count == 1 ? "1 \(unit)" : "\(count) \(unit)s"
    }

    private func progressText(_ current: Double, goal: Goal) -> String {
        let value = "\(GoalNumber.text(current))/\(GoalNumber.text(goal.target))"
        if goal.unitLabel.isEmpty { return value }
        return value
    }

    private func accessibility(_ goal: Goal, current: Double) -> String {
        if goal.kind == .check {
            return center.isMet(goal) ? "Clear \(goal.name)" : "Check \(goal.name)"
        }
        return "Add \(GoalNumber.text(goal.step)) to \(goal.name)"
    }
}

struct HomeGoalStrip: View {
    @State private var center = GoalsCenter.shared
    @State private var detail: Goal?

    var body: some View {
        let items = center.homeGoals
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { goal in
                        chip(goal)
                    }
                    if center.undoAction != nil {
                        Button("Undo") { center.undoLast() }
                            .font(.system(size: 13, weight: .regular, design: .serif))
                            .foregroundStyle(Color.terra500)
                            .buttonStyle(.plain)
                    }
                }
            }
            .sheet(item: $detail) { goal in
                GoalDetailSheet(goalID: goal.id)
            }
        }
    }

    private func chip(_ goal: Goal) -> some View {
        let current = center.progress(goal)
        return Button {
            center.bump(goal.id)
        } label: {
            HStack(spacing: 6) {
                GoalMark(goal: goal, current: current, diameter: 16)
                Text(goal.name)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .lineLimit(1)
                if goal.kind != .check {
                    Text(GoalNumber.text(current))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(HomeQuiet.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Adjust") { detail = center.goals.first { $0.id == goal.id } }
        }
        .accessibilityLabel(goal.kind == .check ? goal.name : "Add to \(goal.name)")
    }
}

struct GoalMark: View {
    let goal: Goal
    let current: Double
    var diameter: CGFloat = 22

    private var tint: Color { GoalPalette.color(goal.color) }
    private var fraction: Double {
        guard goal.target > 0 else { return 0 }
        return min(current / goal.target, 1)
    }

    var body: some View {
        ZStack {
            if goal.kind == .check {
                Circle()
                    .strokeBorder(fraction >= 1 ? tint : HomeQuiet.ink.opacity(0.28), lineWidth: 1.5)
                    .background { Circle().fill(fraction >= 1 ? tint : Color.clear) }
                if fraction >= 1 {
                    Image(systemName: "checkmark")
                        .font(.system(size: diameter * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else if goal.kind == .ring {
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if !goal.icon.isEmpty {
                    Image(systemName: goal.icon)
                        .font(.system(size: diameter * 0.38, weight: .regular))
                        .foregroundStyle(tint)
                }
            } else {
                Circle()
                    .fill(fraction >= 1 ? tint : tint.opacity(0.16))
                Image(systemName: goal.icon.isEmpty ? "plus" : goal.icon)
                    .font(.system(size: diameter * 0.38, weight: .regular))
                    .foregroundStyle(fraction >= 1 ? .white : tint)
            }
        }
        .frame(width: diameter, height: diameter)
        .padding(1)
    }
}

struct GoalDetailSheet: View {
    let goalID: UUID
    @State private var center = GoalsCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    private var goal: Goal? { center.goals.first { $0.id == goalID } }

    var body: some View {
        Group {
            if let goal {
                content(goal)
            }
        }
        .background(Color.bgBase)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgBase)
        .sheet(isPresented: $editing) {
            if let goal {
                GoalEditor(goal: goal) { center.save($0) }
            }
        }
    }

    private func content(_ goal: Goal) -> some View {
        let current = center.progress(goal)
        let streak = center.streak(for: goal)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(goal.name)
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                    Spacer()
                    Menu {
                        Button("Edit") { editing = true }
                        Button("Archive") {
                            center.archive(goal.id)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(HomeQuiet.ink)
                            .frame(width: 44, height: 44)
                    }
                }

                HStack(spacing: 18) {
                    if (goal.logs[center.dayKey(for: Date())] ?? 0) > 0 {
                        Button { center.add(goal.id, delta: -goal.step) } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(HomeQuiet.ink)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(HomeQuiet.cardStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decrease")
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }

                    VStack(spacing: 4) {
                        Text(GoalNumber.text(current))
                            .font(.system(size: 40, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                        Text("of \(GoalNumber.text(goal.target))\(goal.unitLabel.isEmpty ? "" : " \(goal.unitLabel)")")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                    }
                    .frame(maxWidth: .infinity)

                    Button { center.add(goal.id, delta: goal.step) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.terra500)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Increase")
                }

                if streak > 0 {
                    Text(goal.period == .week ? "\(streak) week\(streak == 1 ? "" : "s")" : "\(streak) day\(streak == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(Color.terra500)
                }

                HStack(spacing: 5) {
                    ForEach(center.history(goal, days: 30)) { mark in
                        Circle()
                            .fill(mark.met ? GoalPalette.color(goal.color) : Color.clear)
                            .overlay(
                                Circle().stroke(
                                    mark.scheduled ? GoalPalette.color(goal.color).opacity(mark.isToday ? 1 : 0.35) : HomeQuiet.rule,
                                    lineWidth: mark.isToday ? 1.5 : 1
                                )
                            )
                            .frame(width: mark.isToday ? 12 : 9, height: mark.isToday ? 12 : 9)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct GoalEditor: View {
    let goal: Goal?
    var onSave: (Goal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Goal

    init(goal: Goal?, onSave: @escaping (Goal) -> Void) {
        self.goal = goal
        self.onSave = onSave
        _draft = State(initialValue: goal ?? Goal.draft())
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    TextField("Name", text: $draft.name)
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)

                    row("Type") {
                        Menu {
                            ForEach(GoalKind.allCases, id: \.self) { kind in
                                Button(kind.title) { selectKind(kind) }
                            }
                        } label: {
                            menuLabel(draft.kind.title)
                        }
                    }
                    row("Unit") {
                        Menu {
                            ForEach(GoalUnit.allCases, id: \.self) { unit in
                                Button(unit.title) { selectUnit(unit) }
                            }
                        } label: {
                            menuLabel(draft.unit.title)
                        }
                    }
                    if draft.unit == .custom {
                        TextField("Unit name", text: $draft.customUnit)
                            .font(.system(size: 16, weight: .regular))
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    row(draft.period == .week ? "Each week" : "Each day") {
                        HStack(spacing: 12) {
                            if draft.target > max(draft.step, 1) {
                                stepButton("minus") { nudgeTarget(-1) }
                            }
                            Text(GoalNumber.text(draft.target))
                                .font(.system(size: 20, weight: .regular, design: .serif))
                                .frame(minWidth: 36)
                            stepButton("plus") { nudgeTarget(1) }
                        }
                    }
                    row("Repeats") {
                        Menu {
                            ForEach(GoalPeriod.allCases, id: \.self) { period in
                                Button(period.title) { draft.period = period }
                            }
                        } label: {
                            menuLabel(draft.period.title)
                        }
                    }

                    HStack(spacing: 10) {
                        ForEach(GoalPalette.names, id: \.self) { name in
                            Button {
                                draft.color = name
                            } label: {
                                Circle()
                                    .fill(GoalPalette.color(name))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: draft.color == name ? 3 : 0)
                                    )
                                    .padding(2)
                                    .overlay(
                                        Circle().stroke(draft.color == name ? HomeQuiet.ink : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(GoalIcons.symbols, id: \.self) { symbol in
                                Button {
                                    draft.icon = symbol
                                } label: {
                                    Image(systemName: symbol.isEmpty ? "circle" : symbol)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(draft.icon == symbol ? .white : HomeQuiet.ink)
                                        .frame(width: 36, height: 36)
                                        .background(draft.icon == symbol ? Color.terra500 : Color.white)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(HomeQuiet.cardStroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    weekdayRow

                    Toggle(isOn: $draft.showOnHome) {
                        Text("Today on Home")
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                    }
                    .tint(Color.terra500)
                    Toggle(isOn: $draft.showOnWidget) {
                        Text("On the widget")
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                    }
                    .tint(Color.terra500)

                    if !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.target > 0 {
                        Button {
                            onSave(draft)
                            dismiss()
                        } label: {
                            Text("Save")
                                .font(.system(size: 16, weight: .regular, design: .serif))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.terra500)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .background(Color.bgBase)
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(HomeQuiet.ink)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgBase)
    }

    private var weekdayRow: some View {
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        let start = GoalsCenter.shared.settings.weekStartsOn
        let order = (0..<7).map { ((start - 1 + $0) % 7) + 1 }
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let on = draft.weekdays.contains(weekday)
                Button {
                    if on {
                        draft.weekdays.removeAll { $0 == weekday }
                    } else {
                        draft.weekdays.append(weekday)
                    }
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(on ? .white : HomeQuiet.quiet)
                        .frame(width: 32, height: 32)
                        .background(on ? Color.terra500 : Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(HomeQuiet.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectKind(_ kind: GoalKind) {
        draft.kind = kind
        if kind == .time {
            draft.unit = .minutes
            draft.step = 5
            if draft.target < 5 { draft.target = 30 }
        } else if kind == .check {
            draft.step = 1
            if draft.period == .day { draft.target = 1 }
        }
    }

    private func selectUnit(_ unit: GoalUnit) {
        draft.unit = unit
        switch unit {
        case .glasses:
            draft.step = 1
            draft.target = 8
        case .steps:
            draft.step = 500
            draft.target = 10_000
        case .minutes:
            draft.step = 5
            draft.target = 30
            draft.kind = draft.kind == .check ? .time : draft.kind
        case .custom:
            draft.step = 1
            if draft.target <= 0 { draft.target = 1 }
        }
    }

    private func nudgeTarget(_ delta: Double) {
        let next = draft.target + delta * max(draft.step, 1)
        draft.target = max(draft.step, next)
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            Spacer()
            control()
        }
    }

    private func menuLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Color.terra600)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(HomeQuiet.ink)
                .frame(width: 32, height: 32)
                .background(Color.white)
                .clipShape(Circle())
                .overlay(Circle().stroke(HomeQuiet.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct GoalSettingsSheet: View {
    @State private var center = GoalsCenter.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Goals")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)

                Toggle(isOn: showOnWidget) {
                    Text("Show goals on widget")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                }
                .tint(Color.terra500)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Week starts")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)
                    HStack(spacing: 8) {
                        choice("Sunday", on: center.settings.weekStartsOn == 1) {
                            var next = center.settings
                            next.weekStartsOn = 1
                            center.updateSettings(next)
                        }
                        choice("Monday", on: center.settings.weekStartsOn == 2) {
                            var next = center.settings
                            next.weekStartsOn = 2
                            center.updateSettings(next)
                        }
                    }
                }

                DatePicker(
                    "Day resets",
                    selection: resetDate,
                    displayedComponents: .hourAndMinute
                )
                .font(.system(size: 16, weight: .regular, design: .serif))
                .tint(Color.terra500)

                if !center.goals.filter({ !$0.archived }).isEmpty {
                    VStack(spacing: 0) {
                        ForEach(center.goals.filter { !$0.archived }) { goal in
                            VStack(spacing: 8) {
                                Text(goal.name)
                                    .font(.system(size: 16, weight: .regular, design: .serif))
                                    .foregroundStyle(HomeQuiet.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    place("Home", on: goal.showOnHome) {
                                        center.setShowOnHome(goal.id, on: !goal.showOnHome)
                                    }
                                    place("Widget", on: goal.showOnWidget) {
                                        center.setShowOnWidget(goal.id, on: !goal.showOnWidget)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 12)
                            if goal.id != center.goals.filter({ !$0.archived }).last?.id {
                                Rectangle().fill(HomeQuiet.rule).frame(height: 1)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color.bgBase)
    }

    private var showOnWidget: Binding<Bool> {
        Binding(
            get: { center.settings.showOnWidget },
            set: { on in
                var next = center.settings
                next.showOnWidget = on
                center.updateSettings(next)
            }
        )
    }

    private var resetDate: Binding<Date> {
        Binding(
            get: {
                let minutes = center.settings.resetMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var next = center.settings
                next.resetMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                center.updateSettings(next)
            }
        )
    }

    private func choice(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(on ? .white : HomeQuiet.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? Color.terra500 : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(on ? Color.clear : HomeQuiet.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func place(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(on ? .white : HomeQuiet.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(on ? Color.terra500 : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(on ? Color.clear : HomeQuiet.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ArchivedGoalsSheet: View {
    @State private var center = GoalsCenter.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Archived")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                if center.archivedGoals.isEmpty {
                    Text("None")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.quiet)
                } else {
                    ForEach(center.archivedGoals) { goal in
                        HStack {
                            Text(goal.name)
                                .font(.system(size: 17, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.ink)
                            Spacer()
                            Button("Restore") { center.restore(goal.id) }
                                .font(.system(size: 14, weight: .regular, design: .serif))
                                .foregroundStyle(Color.terra500)
                                .buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) { center.delete(goal.id) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color.bgBase)
    }
}
