import Foundation

struct CertificateDevice: Identifiable, Equatable {
    enum Platform { case simulator, android }
    let id: String
    let name: String
    let platform: Platform
}

enum DeviceCertificate {
    typealias Command = (String, [String]) throws -> String

    static func simulators(from output: String) throws -> [CertificateDevice] {
        struct Device: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool }
        struct Listing: Decodable { let devices: [String: [Device]] }
        return try JSONDecoder().decode(Listing.self, from: Data(output.utf8)).devices.values.flatMap { $0 }
            .filter { $0.state == "Booted" && $0.isAvailable }
            .map { CertificateDevice(id: $0.udid, name: $0.name, platform: .simulator) }
            .sorted { $0.id < $1.id }
    }

    static func androidDevices(from output: String) -> [CertificateDevice] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2, parts[1] == "device" else { return nil }
            let model = parts.first(where: { $0.hasPrefix("model:") })?.dropFirst(6)
            return CertificateDevice(id: parts[0], name: model.map(String.init) ?? parts[0], platform: .android)
        }
    }

    static func adbPath(environment: [String: String] = ProcessInfo.processInfo.environment,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let roots = [environment["ANDROID_SDK_ROOT"], environment["ANDROID_HOME"],
                     home.appendingPathComponent("Library/Android/sdk").path].compactMap { $0 }
        let candidates = roots.map { $0 + "/platform-tools/adb" }
            + (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/adb" }
            + ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func install(on device: CertificateDevice, certificate: URL, adb: String?,
                        command: Command = SystemProxy.command) throws -> String {
        guard FileManager.default.fileExists(atPath: certificate.path) else {
            throw AppFailure("Start capture once to generate this Mac’s CA certificate, then try again.")
        }
        switch device.platform {
        case .simulator:
            _ = try command("/usr/bin/xcrun", ["simctl", "keychain", device.id, "add-root-cert", certificate.path])
            return "CA installed and trusted in \(device.name). Configure the Mac HTTP/HTTPS proxy to 127.0.0.1 and the capture port for Simulator traffic."
        case .android:
            guard let adb else { throw AppFailure("ADB not found. Install Android SDK Platform-Tools, then refresh.") }
            let destination = "/sdcard/Download/Proxiverse-CA.cer"
            _ = try command(adb, ["-s", device.id, "push", certificate.path, destination])
            let next = "On \(device.name), open Settings → Security → Encryption & credentials → Install a certificate → CA certificate (names vary by Android version). Choose Download/Proxiverse-CA.cer. The certificate has only been copied; installation requires confirmation on the device."
            do {
                _ = try command(adb, ["-s", device.id, "shell", "am", "start", "-a", "android.settings.SECURITY_SETTINGS"])
                return next
            } catch {
                return "Certificate copied, but Settings could not be opened automatically. " + next
            }
        }
    }

    static func installAutomatically(on device: CertificateDevice, certificate: URL, adb: String?,
                                     helper: URL? = Bundle.module.url(forResource: "install-certificate", withExtension: "dex"),
                                     command: Command = SystemProxy.command) throws -> String {
        guard device.platform == .android else {
            return try install(on: device, certificate: certificate, adb: adb, command: command)
        }
        guard FileManager.default.fileExists(atPath: certificate.path) else {
            throw AppFailure("Start capture once to generate this Mac’s CA certificate, then try again.")
        }
        guard let adb else { throw AppFailure("ADB not found. Install Android SDK Platform-Tools, then refresh.") }
        guard let helper else { throw AppFailure("The Android certificate installer is missing. Rebuild Proxiverse.") }
        let publicCA = try String(contentsOf: certificate, encoding: .utf8)
        guard publicCA.contains("-----BEGIN CERTIFICATE-----"), !publicCA.contains("PRIVATE KEY") else {
            throw AppFailure("Only a public CA certificate can be transferred.")
        }
        let target = ["-s", device.id]
        func run(_ arguments: [String]) throws -> String { try command(adb, target + arguments) }
        func isRoot() -> Bool {
            (try? run(["shell", "id", "-u"]).trimmingCharacters(in: .whitespacesAndNewlines)) == "0"
        }
        if !isRoot(), device.id.range(of: "^emulator-[0-9]+$", options: .regularExpression) != nil {
            _ = try run(["root"])
            for _ in 0..<20 {
                if isRoot() { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        guard isRoot() else {
            throw AppFailure("Automatic installation requires root ADB access. Use an AOSP / Google APIs debug emulator image (Google Play images do not support adb root), or use “Copy CA & Open Settings” and confirm on the phone. No CA was installed.")
        }
        let user = try run(["shell", "am", "get-current-user"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard user.range(of: "^[0-9]+$", options: .regularExpression) != nil else {
            throw AppFailure("Cannot determine the active Android user. No CA was installed.")
        }
        let directory = "/data/local/tmp/proxiverse-ca-" + UUID().uuidString
        _ = try run(["shell", "mkdir", directory])
        defer { _ = try? run(["shell", "rm", "-rf", directory]) }
        _ = try run(["push", certificate.path, directory + "/ca.pem"])
        _ = try run(["push", helper.path, directory + "/installer.dex"])
        let output = try run(["shell", "env", "CLASSPATH=" + directory + "/installer.dex", "app_process", "/",
                              "InstallCertificate", directory + "/ca.pem", user])
        guard output.split(separator: "\n").contains(where: { $0.hasPrefix("PROXIVERSE_CA_INSTALLED:") }) else {
            throw AppFailure("Android did not confirm the CA installation. \(output)")
        }
        // Refresh running apps' cached trust configuration; the CA is already installed if this fails.
        let notified = (try? run(["shell", "am", "broadcast", "--user", user, "-a", "android.security.action.TRUST_STORE_CHANGED"])) != nil
        return "CA installed and verified in \(device.name)’s user CA store (Android user \(user)). "
            + (notified ? "Restart the app being tested if it was already running. " : "Trust refresh could not be sent; restart the app being tested. ")
            + "Apps must trust user CAs in their debug configuration. Proxy settings are separate."
    }

    static func lanAddresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var addresses: Set<String> = []
        var current = interfaces
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.insert(String(cString: host))
            }
        }
        return addresses.sorted()
    }
}
