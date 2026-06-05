import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Privacy") {
                Text("Raw screen and accessibility context stay local by default.")
            }
            Section("Calendar") {
                Text("Calendar permissions are required for planned blocks.")
            }
        }
        .padding()
        .frame(width: 480)
    }
}
