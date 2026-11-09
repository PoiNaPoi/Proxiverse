import SwiftUI

struct EncryptedTrafficView: View {
    let host: String
    let decryptionEnabled: Bool
    let busy: Bool
    let onEnable: () -> Void
    let onSettings: () -> Void

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { actionButtons }
            VStack(alignment: .leading, spacing: 12) { actionButtons }
        }
        .controlSize(.large)
        .disabled(busy)
    }

    @ViewBuilder private var actionButtons: some View {
        if !decryptionEnabled {
            Button(action: onEnable) {
                Label("Enable Decryption", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Enable HTTPS decryption for \(host)")
        }
        Button("Manage Domains…", action: onSettings)
            .buttonStyle(.bordered)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Encrypted connection").font(.title2.weight(.semibold))
                        Text("This connection passed through without HTTPS decryption. Headers, URL paths, and bodies are not available.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("DOMAIN").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(host).font(.system(.body, design: .monospaced).weight(.medium))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Label(decryptionEnabled ? "Decryption enabled for new connections" : "Decryption is off for this domain",
                          systemImage: decryptionEnabled ? "checkmark.circle.fill" : "lock.fill")
                        .font(.callout)
                        .foregroundStyle(decryptionEnabled ? Color.green : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))

                VStack(alignment: .leading, spacing: 12) {
                    if decryptionEnabled {
                        Text("Reconnect to inspect the next request").font(.headline)
                        Text("Reconnect the client or reopen the app being tested, then send the request again. This captured connection will stay encrypted.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Inspect HTTPS from this domain").font(.headline)
                        Text("Enable decryption, then reconnect the client and send the request again. The client must trust the Proxiverse CA.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    actions
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
