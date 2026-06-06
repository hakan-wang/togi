import SwiftUI

// Day-timeline planner UI. Shows the selected day's `planned_blocks` laid out on
// an hour grid, supports create/edit, and exposes the "Hey Bogi" command field.
// Wiring into the menu bar / hotkey and `AppEnvironment` is an integration point
// (see PR description) — this view depends only on `PlannerService`.

/// View model bridging the SwiftUI timeline to the canonical `PlannerService`.
@MainActor
final class PlannerViewModel: ObservableObject {
    @Published var day: Date
    @Published private(set) var blocks: [PlannedBlock] = []
    @Published var commandText: String = ""
    @Published var errorMessage: String?

    private let service: PlannerService
    private let calendar: Calendar
    private let inference: InferenceClient?

    init(service: PlannerService, day: Date = Date(), calendar: Calendar = .current, inference: InferenceClient? = nil) {
        self.service = service
        self.day = calendar.startOfDay(for: day)
        self.calendar = calendar
        self.inference = inference
    }

    func reload() {
        do { blocks = try service.blocks(on: day, calendar: calendar) }
        catch { errorMessage = "Could not load blocks" }
    }

    func goToPreviousDay() { shiftDay(by: -1) }
    func goToNextDay() { shiftDay(by: 1) }

    private func shiftDay(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        day = next
        reload()
    }

    func createBlock(title: String, startAt: Date, endAt: Date, category: String?) {
        do {
            _ = try service.createBlock(title: title, startAt: startAt, endAt: endAt, category: category)
            reload()
        } catch { errorMessage = "Could not create block" }
    }

    func update(_ block: PlannedBlock) {
        do { try service.update(block); reload() }
        catch { errorMessage = "Could not update block" }
    }

    func delete(_ block: PlannedBlock) {
        Task {
            do { try await service.deleteBlock(id: block.id); reload() }
            catch { errorMessage = "Could not delete block" }
        }
    }

    /// Run a "Hey Bogi" command: try the local parser first, fall back to the LLM.
    func runCommand() async {
        let raw = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let now = Date()
        var parsed = CommandParser.parse(raw, now: now, calendar: calendar)

        if !parsed.confident, let inference {
            let request = CommandParser.inferenceRequest(for: raw, now: now, calendar: calendar)
            if let response = try? await inference.infer(request),
               let llm = CommandParser.parse(llmResponse: response.text) {
                parsed = llm
            }
        }
        apply(parsed, now: now)
        commandText = ""
    }

    private func apply(_ command: ParsedCommand, now: Date) {
        guard !command.title.isEmpty else {
            errorMessage = "Sorry, I couldn't understand that."
            return
        }
        let start = command.startAt ?? defaultStart(now: now)
        let end = command.endAt
            ?? start.addingTimeInterval(TimeInterval((command.durationMinutes ?? CommandParser.defaultDurationMinutes) * 60))
        createBlock(title: command.title, startAt: start, endAt: end, category: command.category)
    }

    /// When a command omits a time, place the block at the next round hour.
    private func defaultStart(now: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let topOfHour = calendar.date(from: comps) ?? now
        return calendar.date(byAdding: .hour, value: 1, to: topOfHour) ?? now
    }
}

struct PlannerView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @State private var showingCreate = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            timeline
            Divider()
            commandBar
        }
        .frame(minWidth: 360, minHeight: 480)
        .onAppear { viewModel.reload() }
        .sheet(isPresented: $showingCreate) {
            BlockEditorView(day: viewModel.day) { title, start, end, category in
                viewModel.createBlock(title: title, startAt: start, endAt: end, category: category)
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: viewModel.goToPreviousDay) { Image(systemName: "chevron.left") }
            Spacer()
            Text(Self.dayFormatter.string(from: viewModel.day)).font(.headline)
            Spacer()
            Button(action: viewModel.goToNextDay) { Image(systemName: "chevron.right") }
            Button { showingCreate = true } label: { Image(systemName: "plus") }
        }
        .padding()
    }

    private var timeline: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                hourGrid
                ForEach(viewModel.blocks) { block in
                    BlockTile(block: block)
                        .offset(y: yOffset(for: block.startAt))
                        .frame(height: max(24, height(for: block)))
                        .contextMenu {
                            Button("Delete", role: .destructive) { viewModel.delete(block) }
                        }
                }
            }
            .padding(.horizontal)
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top) {
                    Text(String(format: "%02d:00", hour))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
                }
                .frame(height: Self.hourHeight, alignment: .top)
            }
        }
    }

    private var commandBar: some View {
        HStack {
            Image(systemName: "mic.fill").foregroundStyle(.secondary)
            TextField("Hey Bogi… e.g. \"one hour to edit videos tomorrow\"", text: $viewModel.commandText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await viewModel.runCommand() } }
            Button("Add") { Task { await viewModel.runCommand() } }
        }
        .padding()
    }

    static let hourHeight: CGFloat = 44

    private func yOffset(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let minutes = CGFloat(cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date))
        return minutes / 60 * Self.hourHeight
    }

    private func height(for block: PlannedBlock) -> CGFloat {
        let minutes = CGFloat(block.endAt.timeIntervalSince(block.startAt) / 60)
        return minutes / 60 * Self.hourHeight
    }
}

private struct BlockTile: View {
    let block: PlannedBlock

    var body: some View {
        HStack {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title).font(.caption).bold().lineLimit(1)
                if let category = block.category {
                    Text(category).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.leading, 48)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var color: Color {
        switch block.source {
        case .apple: return .red
        case .google: return .blue
        case .local: return .green
        }
    }
}

/// Minimal create/edit sheet for a block.
private struct BlockEditorView: View {
    let day: Date
    let onSave: (String, Date, Date, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category = ""
    @State private var start: Date
    @State private var end: Date

    init(day: Date, onSave: @escaping (String, Date, Date, String?) -> Void) {
        self.day = day
        self.onSave = onSave
        let cal = Calendar.current
        let base = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        _start = State(initialValue: base)
        _end = State(initialValue: base.addingTimeInterval(3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Block").font(.headline)
            TextField("Title", text: $title)
            TextField("Category (optional)", text: $category)
            DatePicker("Start", selection: $start)
            DatePicker("End", selection: $end)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(title, start, end, category.isEmpty ? nil : category)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
