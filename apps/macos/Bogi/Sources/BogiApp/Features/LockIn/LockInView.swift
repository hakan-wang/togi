import SwiftUI

struct LockInView: View {
    @ObservedObject var controller: LockInController

    var body: some View {
        VStack(alignment: .leading) {
            Text(controller.isActive ? "Lock-in active" : "Lock-in idle")
            Button("End") {
                controller.end(summary: nil)
            }
            .disabled(!controller.isActive)
        }
        .padding()
    }
}
