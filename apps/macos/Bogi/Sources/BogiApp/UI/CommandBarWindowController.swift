import AppKit
import SwiftUI

@MainActor
final class CommandBarModel: ObservableObject {
    @Published var isPresented = false
    @Published var query = ""

    nonisolated init() {}
}

struct CommandBarView: View {
    @ObservedObject var model: CommandBarModel

    var body: some View {
        TextField("Command", text: $model.query)
            .textFieldStyle(.plain)
            .padding(16)
            .frame(width: 520)
    }
}

@MainActor
final class CommandBarWindowController {
    private let model: CommandBarModel
    private var panel: NSPanel?

    init(model: CommandBarModel = CommandBarModel()) {
        self.model = model
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 72),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.contentView = NSHostingView(rootView: CommandBarView(model: model))
            self.panel = panel
        }
        model.isPresented = true
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        model.isPresented = false
        panel?.orderOut(nil)
    }
}
