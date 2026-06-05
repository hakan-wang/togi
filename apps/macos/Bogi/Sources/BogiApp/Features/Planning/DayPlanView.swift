import SwiftUI

struct DayPlanView: View {
    let blocks: [PlannedBlock]

    var body: some View {
        List(blocks) { block in
            VStack(alignment: .leading) {
                Text(block.title)
                Text(block.category ?? "Uncategorized")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
