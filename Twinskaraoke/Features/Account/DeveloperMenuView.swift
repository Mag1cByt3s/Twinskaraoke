import SwiftUI

struct DeveloperMenuView: View {
    @AppStorage("nk.debugLogging") private var debugLogging: Bool = false
    @AppStorage("nk.easterEggAlwaysTrigger") private var easterEggAlwaysTrigger: Bool = false
    @State private var showDisableConfirm = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("Easter Eggs") {
                Toggle("Always Trigger", isOn: $easterEggAlwaysTrigger)
                    .tint(.appAccent)
            }
            Section("Logging") {
                Toggle("Debug Logging", isOn: $debugLogging)
                    .tint(.appAccent)
                if debugLogging {
                    Button("Export Debug Logs") {
                        exportDebugLogs()
                    }
                    .foregroundStyle(Color.appAccent)
                }
            }
            Section {
                Button("Disable Developer Mode", role: .destructive) {
                    showDisableConfirm = true
                }
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Disable developer mode?", isPresented: $showDisableConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Disable Developer Mode", role: .destructive) {
                DeveloperMode.isEnabled = false
                dismiss()
            }
        } message: {
            Text("The developer menu and related features will be hidden until you turn developer mode back on.")
        }
    }

    private func exportDebugLogs() {
        #if canImport(UIKit)
            let logs = DebugLogger.exportLogs()
            let av = UIActivityViewController(
                activityItems: [logs], applicationActivities: nil
            )
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                let root = windowScene.keyWindow?.rootViewController
            {
                root.present(av, animated: true)
            }
        #endif
    }
}
