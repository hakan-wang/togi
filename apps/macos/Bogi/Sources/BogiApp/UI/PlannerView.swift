import SwiftUI

/// In-app planner: set your day's intent without any calendar. "Hey Bogi" natural language
/// plus a quick manual add. Blocks land in planned_blocks, which the judge compares reality
/// against — so the accountability loop works whether or not Google Calendar is connected.
struct PlannerView: View {
    @EnvironmentObject private var appState: AppState

    @State private var blocks: [PlannedBlock] = []
    @State private var nl = ""
    @State private var title = ""
    @State private var start = PlannerView.nextHalfHour()
    @State private var durationMinutes = 60
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Plan today")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(BogiColor.ink)

            // "Hey Bogi" natural-language add.
            HStack(spacing: 8) {
                TextField("e.g. edit videos 2pm to 4pm", text: $nl)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNatural)
                Button(action: addNatural) {
                    Image(systemName: working ? "hourglass" : "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(BogiColor.primary)
                .disabled(nl.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }

            // Manual quick add.
            HStack(spacing: 8) {
                TextField("title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)
                DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Stepper("\(durationMinutes)m", value: $durationMinutes, in: 15...480, step: 15)
                    .fixedSize()
                Button("Add", action: addManual)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.callout)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if blocks.isEmpty {
                        Text("Nothing planned yet. Tell Bogi what you'll do, and it'll hold you to it.")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    ForEach(blocks, id: \.id) { block in
                        blockRow(block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .onAppear(perform: reload)
    }

    private func blockRow(_ block: PlannedBlock) -> some View {
        HStack(spacing: 10) {
            Text(Self.timeRange(block))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(BogiColor.primary)
                .frame(width: 96, alignment: .leading)
            Text(block.title).foregroundStyle(BogiColor.ink)
            Spacer()
            Button {
                appState.plannedBlocks.delete(id: block.id)
                reload()
            } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func reload() {
        blocks = appState.plannedBlocks.blocks(onDay: Date()).sorted { $0.startAt < $1.startAt }
    }

    private func addManual() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        _ = appState.planner.createLocalBlock(title: trimmed, start: start, end: end, category: nil)
        title = ""
        error = nil
        reload()
    }

    private func addNatural() {
        let utterance = nl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty, !working else { return }
        working = true
        error = nil
        let inference = appState.inference
        let parser = PlannerCommandParser(ai: { prompt in
            try await inference.infer(
                system: nil,
                messages: [InferenceMessage(role: "user", content: prompt)],
                maxTokens: 300
            )
        })
        Task {
            defer { working = false }
            do {
                let command = try await parser.parse(utterance, now: Date())
                switch command {
                case .createBlock(let t, let s, let e), .move(let t, let s, let e):
                    _ = appState.planner.createLocalBlock(
                        title: t.isEmpty ? utterance : t, start: s, end: e, category: nil
                    )
                    nl = ""
                    reload()
                case .unknown:
                    error = "Couldn't read that. Try 'edit videos 2pm to 4pm'."
                }
            } catch {
                self.error = "Couldn't reach Bogi: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    private static func nextHalfHour() -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        let minute = comps.minute ?? 0
        if minute >= 30 {
            comps.hour = (comps.hour ?? 0) + 1
            comps.minute = 0
        } else {
            comps.minute = 30
        }
        comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    private static func timeRange(_ block: PlannedBlock) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: block.startAt))–\(f.string(from: block.endAt))"
    }
}
