import SwiftUI

enum Theme {
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.075, green: 0.08, blue: 0.07, alpha: 1) : UIColor(red: 0.98, green: 0.985, blue: 0.97, alpha: 1) })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let subtle = Color.primary.opacity(0.045)
    static let line = Color.primary.opacity(0.1)
    static let holiday = Color(red: 0.76, green: 0.25, blue: 0.22)
    static func heading(_ size: CGFloat = 64) -> Font { .custom("Anton-Regular", size: size, relativeTo: .largeTitle) }
}

struct HabitSymbol: Identifiable {
    var symbol: String
    var name: String
    var id: String { symbol }
}

enum HabitSymbols {
    static let all: [HabitSymbol] = [
        .init(symbol: "book", name: "読書"), .init(symbol: "text.book.closed", name: "勉強"),
        .init(symbol: "graduationcap", name: "学習"), .init(symbol: "character.book.closed", name: "語学"),
        .init(symbol: "pencil", name: "執筆"), .init(symbol: "pencil.and.outline", name: "スケッチ"),
        .init(symbol: "paintpalette", name: "絵画"), .init(symbol: "camera", name: "写真"),
        .init(symbol: "figure.walk", name: "散歩"), .init(symbol: "figure.run", name: "ランニング"),
        .init(symbol: "figure.hiking", name: "ハイキング"), .init(symbol: "figure.yoga", name: "ヨガ"),
        .init(symbol: "figure.mind.and.body", name: "瞑想"), .init(symbol: "figure.pool.swim", name: "水泳"),
        .init(symbol: "bicycle", name: "自転車"), .init(symbol: "dumbbell", name: "筋トレ"),
        .init(symbol: "tennis.racket", name: "テニス"), .init(symbol: "soccerball", name: "サッカー"),
        .init(symbol: "basketball", name: "バスケットボール"), .init(symbol: "figure.dance", name: "ダンス"),
        .init(symbol: "pianokeys", name: "ピアノ"), .init(symbol: "guitars", name: "ギター"),
        .init(symbol: "music.note", name: "音楽"), .init(symbol: "mic", name: "歌"),
        .init(symbol: "headphones", name: "リスニング"), .init(symbol: "leaf", name: "植物"),
        .init(symbol: "drop", name: "水分"), .init(symbol: "cup.and.saucer", name: "休憩"),
        .init(symbol: "fork.knife", name: "食事"), .init(symbol: "carrot", name: "栄養"),
        .init(symbol: "frying.pan", name: "料理"), .init(symbol: "bed.double", name: "睡眠"),
        .init(symbol: "moon", name: "就寝"), .init(symbol: "sun.max", name: "朝の活動"),
        .init(symbol: "house", name: "家事"), .init(symbol: "washer", name: "洗濯"),
        .init(symbol: "sparkles", name: "掃除"), .init(symbol: "trash", name: "片づけ"),
        .init(symbol: "desktopcomputer", name: "仕事"), .init(symbol: "keyboard", name: "開発"),
        .init(symbol: "hammer", name: "制作"), .init(symbol: "wrench.and.screwdriver", name: "修理"),
        .init(symbol: "brain.head.profile", name: "思考"), .init(symbol: "heart", name: "健康"),
        .init(symbol: "cross.case", name: "ケア"), .init(symbol: "person.2", name: "交流"),
        .init(symbol: "phone", name: "連絡"), .init(symbol: "envelope", name: "メール"),
        .init(symbol: "pawprint", name: "ペット"), .init(symbol: "tree", name: "自然"),
        .init(symbol: "wallet.pass", name: "家計"), .init(symbol: "chart.bar", name: "記録"),
        .init(symbol: "clock", name: "時間管理"), .init(symbol: "checklist", name: "確認"),
        .init(symbol: "map", name: "旅行"), .init(symbol: "globe.asia.australia", name: "地理"),
        .init(symbol: "flame", name: "練習"), .init(symbol: "star", name: "その他")
    ]
}

struct SectionCaption: View {
    var title: String
    var count: Int? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(.caption, design: .monospaced)).tracking(1.4)
            Spacer()
            if let count { Text(String(format: "%02d", count)).font(.system(.caption, design: .monospaced)) }
        }.foregroundStyle(.secondary).padding(.bottom, 7)
    }
}

struct ProgressRing<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var progress: Double
    var size: CGFloat = 64
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 3)
            Circle().trim(from: 0, to: min(1, max(0, progress))).stroke(Color.primary.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            content()
        }.frame(width: size, height: size).animation(InteractionMotion.animation(reduceMotion: reduceMotion), value: progress)
    }
}

struct SymbolPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: String
    var onSelection: () -> Void = {}
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private let columns = [GridItem(.adaptive(minimum: 58), spacing: 12)]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("アイコンを検索", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("symbol.search")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(HabitSymbols.all.filter { query.isEmpty || $0.name.contains(query) }) { entry in
                    Button {
                        searchFocused = false
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { selection = entry.symbol }
                        query = ""
                        onSelection()
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: entry.symbol).font(.system(size: 23, weight: .light)).frame(width: 48, height: 48)
                                .background(selection == entry.symbol ? Color.primary.opacity(0.12) : Theme.subtle, in: RoundedRectangle(cornerRadius: 12))
                            Text(entry.name).font(.caption2).lineLimit(1)
                        }
                    }.buttonStyle(.plain)
                        .accessibilityLabel(entry.name)
                        .accessibilityIdentifier("symbol.\(entry.symbol)")
                        .accessibilityAddTraits(selection == entry.symbol ? [.isSelected] : [])
                }
            }
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var task: PlannerTask
    var showDate = false
    var edit: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Button { withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) { _ = store.toggleTask(task) } } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19, weight: .light)).foregroundStyle(task.isCompleted ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.6))
                    .frame(width: 28, height: 44).contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }.buttonStyle(PressFeedbackStyle()).accessibilityLabel("\(task.title)を\(task.isCompleted ? "未完了に戻す" : "完了にする")")
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.body).strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? Color.secondary : Color.primary).multilineTextAlignment(.leading)
                    if showDate, let date = task.date { Text(date, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 11)
            }.buttonStyle(PressFeedbackStyle()).accessibilityIdentifier("task.item.\(task.title)")
            if task.isPriority { Image(systemName: "star").font(.caption).foregroundStyle(.secondary) }
            if task.repeatsDaily { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 1).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            .modifier(TaskContextActions(task: task, edit: edit))
            .sensoryFeedback(.selection, trigger: task.isCompleted)
    }
}

struct EventRow: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var task: PlannerTask
    var edit: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in row }
            .modifier(TaskContextActions(task: task, edit: edit))
            .sensoryFeedback(.selection, trigger: task.isCompleted)
    }
    private var row: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { withAnimation(InteractionMotion.animation(reduceMotion: reduceMotion)) { _ = store.toggleTask(task) } } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .light)).frame(width: 28, height: 44)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }.buttonStyle(PressFeedbackStyle()).foregroundStyle(task.isCompleted ? Color.primary : .secondary)
                .accessibilityLabel("\(task.title)を\(task.isCompleted ? "未完了に戻す" : "完了にする")")
            Button(action: edit) {
                HStack(alignment: .top, spacing: 14) {
                    if let start = task.date {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(start, style: .time).font(.system(.caption, design: .monospaced))
                            if let end = task.endDate { Text(end, style: .time).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary) }
                        }.frame(width: 48, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.body).strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? Color.secondary : .primary)
                        if !task.location.isEmpty { Label(task.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
                        if task.isCompleted, let completed = task.completedAt {
                            HStack(spacing: 4) {
                                Text(task.completionStatus.title)
                                if task.completionDateOnly { Text(completed, format: .dateTime.month().day()) }
                                else { Text(completed, style: .time) }
                            }.font(.caption).foregroundStyle(.secondary)
                        } else if task.isOverdue() { Text("未完了・予定時刻を経過").font(.caption).foregroundStyle(Theme.holiday) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.multilineTextAlignment(.leading).padding(.vertical, 14)
            }.buttonStyle(PressFeedbackStyle()).accessibilityIdentifier("event.item.\(task.title)")
        }.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }
}
