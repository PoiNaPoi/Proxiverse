import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins

struct DeviceCertificateView: View {
    @ObservedObject var model: CaptureModel
    @State private var platform = 0
    @State private var devices: [CertificateDevice] = []
    @State private var selectedID = ""
    @State private var busy = false
    @State private var message: String?
    @State private var failure: String?
    @State private var addresses: [String] = []

    private var certificateExists: Bool { FileManager.default.fileExists(atPath: model.engine.paths.certificate.path) }
    private var qrCode: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("http://mitm.it".utf8)
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
                                                      from: output.extent.applying(CGAffineTransform(scaleX: 6, y: 6))) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 132, height: 132))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Install Certificate").font(.title2.bold())
                Text("Install this Mac’s public CA on a test device to inspect HTTPS traffic.")
                    .foregroundStyle(.secondary)
                if !certificateExists {
                    Text("Start capture once to generate the CA certificate.").foregroundStyle(.orange)
                    Button("Start Capture") { Task { await model.start() } }.disabled(model.running || model.busy)
                }
                Picker("Device", selection: $platform) {
                    Text("Phone / Tablet").tag(0)
                    Text("iOS Simulator").tag(1)
                    Text("Android / Emulator (ADB)").tag(2)
                }.pickerStyle(.segmented).disabled(busy)
                if platform == 0 { phoneGuide } else { connectedDevices }
                Divider()
                Button("Show Public CA Certificate", action: model.openCertificate).disabled(!certificateExists)
                Text("Only the public CA is transferred. Remove it from the device when testing is finished. Apps with certificate pinning require a debug build configured for inspection.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(width: 640, height: 660)
        .task { addresses = DeviceCertificate.lanAddresses() }
        .onChange(of: platform) { _, _ in Task { await refresh() } }
    }

    private var phoneGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.running && model.allowLAN ? "LAN capture is running" : "Start capture with “Allow test devices on local network” enabled in Capture Settings.")
                .foregroundStyle(model.running && model.allowLAN ? Color.secondary : Color.orange)
            Text("1. Connect the phone and Mac to the same network. In the phone’s Wi-Fi settings, set HTTP proxy to Manual.")
            Text("Server: \(addresses.isEmpty ? "Mac’s LAN IP (check Network Settings)" : addresses.joined(separator: " / "))\nPort: \(model.proxyPort)")
                .font(.body.monospaced()).textSelection(.enabled)
            Text("Choose the Mac address reachable from the phone. VPN or firewall settings may affect the connection.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if let qrCode { Image(nsImage: qrCode).interpolation(.none).accessibilityLabel("QR code for http://mitm.it") }
                VStack(alignment: .leading, spacing: 8) {
                    Text("2. After setting the proxy, scan this code or open http://mitm.it in Safari / Chrome on the phone. Choose your platform to download the CA.")
                    Button("Copy Setup URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("http://mitm.it", forType: .string)
                    }
                }
            }
            Text("iPhone / iPad: Settings → General → VPN & Device Management → install the downloaded profile. Then General → About → Certificate Trust Settings → enable full trust for the mitmproxy CA.")
            Text("Android: Settings → Security → Install a certificate → CA certificate, then select the downloaded CA. Menu names vary by device. Apps targeting Android 7+ generally need a debug Network Security Configuration that trusts user CAs.")
                .font(.callout)
        }
    }

    private var connectedDevices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(platform == 1 ? "Boot an iOS Simulator in Xcode, then refresh. The CA is installed directly into the selected simulator’s trust store."
                 : "Connect an Android phone with USB debugging authorized, or start an Android emulator. Android SDK Platform-Tools (ADB) is required.")
            HStack {
                Picker("Target", selection: $selectedID) {
                    Text("Select a device").tag("")
                    ForEach(devices) { device in Text("\(device.name) (\(device.id))").tag(device.id) }
                }
                Button("Refresh") { Task { await refresh() } }
            }.disabled(busy)
            Button(platform == 1 ? "Install & Trust CA" : "Install CA Automatically") { Task { await install() } }
                .disabled(busy || !certificateExists || selectedID.isEmpty)
            if platform == 2 {
                Button("Copy CA & Open Settings") { Task { await install(automatically: false) } }
                    .disabled(busy || !certificateExists || selectedID.isEmpty)
            }
            if busy { ProgressView().controlSize(.small) }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let message { Text(message).textSelection(.enabled) }
            if platform == 1 {
                Text("Proxy setup is separate: tick “Capture Mac Traffic” in the sidebar, or set the Mac HTTP/HTTPS proxy manually to 127.0.0.1:\(model.proxyPort). The checkbox applies immediately while capturing.")
            } else {
                Text("Automatic installation writes and verifies the CA in Android’s user CA store. Requires root ADB access; debug emulators can enable it automatically. Phones without root and Google Play emulator images must use “Copy CA & Open Settings”. For the standard Android emulator, set its proxy to 10.0.2.2:\(model.proxyPort) and enable LAN capture. Apps targeting Android 7+ generally need a debug configuration that trusts user CAs.")
            }
        }
    }

    @MainActor private func refresh() async {
        guard !busy else { return }
        busy = true
        failure = nil
        message = nil
        devices = []
        selectedID = ""
        defer { busy = false }
        let selectedPlatform = platform
        guard selectedPlatform != 0 else { return }
        do {
            devices = try await Task.detached {
                if selectedPlatform == 1 {
                    return try DeviceCertificate.simulators(from: SystemProxy.command("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "-j"]))
                }
                guard let adb = DeviceCertificate.adbPath() else { throw AppFailure("ADB not found. Install Android SDK Platform-Tools, then refresh.") }
                return try DeviceCertificate.androidDevices(from: SystemProxy.command(adb, ["devices", "-l"]))
            }.value
            if devices.count == 1 { selectedID = devices[0].id }
            if devices.isEmpty { message = "No ready devices found. Start a simulator/emulator or connect and authorize your phone, then refresh." }
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func install(automatically: Bool = true) async {
        guard !busy, let device = devices.first(where: { $0.id == selectedID }) else { return }
        busy = true
        failure = nil
        message = nil
        defer { busy = false }
        let certificate = model.engine.paths.certificate
        do {
            message = try await Task.detached {
                if automatically {
                    return try DeviceCertificate.installAutomatically(on: device, certificate: certificate, adb: DeviceCertificate.adbPath())
                }
                return try DeviceCertificate.install(on: device, certificate: certificate, adb: DeviceCertificate.adbPath())
            }.value
        } catch { failure = error.localizedDescription }
    }
}
