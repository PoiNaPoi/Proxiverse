import SwiftUI

struct HTTPSDecryptionView: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HTTPS Decryption").font(.title2.bold())
            Text("Decrypt only checked domains. Unchecked domains pass through encrypted. HTTP traffic is captured as usual.")
                .foregroundStyle(.secondary)
            Text("Inspect only systems and data you are authorized to test. Captures may contain passwords, tokens, and personal data.")
                .font(.caption).foregroundStyle(.secondary)
            List(model.availableHTTPSHosts, id: \.self) { domain in
                HStack {
                    Toggle(domain, isOn: Binding(
                        get: { model.isHTTPSDecryptionEnabled(domain) },
                        set: { enabled in Task { await model.setHTTPSDecryption(domain, enabled: enabled) } }
                    )).toggleStyle(.checkbox)
                    Spacer()
                    Text(model.isHTTPSDecryptionEnabled(domain) ? "Decryption enabled" : "Decryption off")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        Task { await model.removeHTTPSDecryption(domain) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(domain) and disable HTTPS decryption for new connections")
                    .accessibilityLabel("Remove \(domain)")
                }
            }
            .overlay {
                if model.availableHTTPSHosts.isEmpty {
                    Text("No saved domains. Enable HTTPS decryption for a domain from the main window.")
                        .foregroundStyle(.secondary).padding().allowsHitTesting(false)
                }
            }
            .disabled(model.busy)
            Text("Each entry matches that exact domain on all ports; subdomains are separate. Changes apply to new TLS connections. Reconnect the client after changing a checkbox. Enabled domains require trusting the Reqnivo CA.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 620, height: 480)
        .alert("HTTPS Decryption", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
