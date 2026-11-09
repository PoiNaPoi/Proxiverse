import XCTest
@testable import Proxiverse

final class DeviceCertificateTests: XCTestCase {
    func testDiscoveryOnlyIncludesReadyDevices() throws {
        let simulators = try DeviceCertificate.simulators(from: """
        {"devices":{"iOS":[
        {"udid":"booted","name":"iPhone","state":"Booted","isAvailable":true},
        {"udid":"off","name":"iPhone","state":"Shutdown","isAvailable":true},
        {"udid":"missing","name":"iPhone","state":"Booted","isAvailable":false}]}}
        """)
        XCTAssertEqual(simulators.map(\.id), ["booted"])
        XCTAssertThrowsError(try DeviceCertificate.simulators(from: "invalid"))
        let android = DeviceCertificate.androidDevices(from: """
        List of devices attached
        emulator-5554 device product:sdk model:Pixel_9 transport_id:1
        phone unauthorized usb:1
        old offline
        """)
        XCTAssertEqual(android.map(\.id), ["emulator-5554"])
        XCTAssertEqual(android.first?.name, "Pixel_9")
    }

    func testSimulatorTargetsSelectedDeviceAndOnlyPublicCertificate() throws {
        let cert = try temporaryCertificate()
        defer { try? FileManager.default.removeItem(at: cert.deletingLastPathComponent()) }
        var calls: [[String]] = []
        _ = try DeviceCertificate.install(on: CertificateDevice(id: "chosen-udid", name: "iPhone", platform: .simulator),
                                          certificate: cert, adb: nil) { executable, arguments in
            calls.append([executable] + arguments)
            return ""
        }
        XCTAssertEqual(calls, [["/usr/bin/xcrun", "simctl", "keychain", "chosen-udid", "add-root-cert", cert.path]])
    }

    func testAndroidCopiesPublicCAThenOpensSettingsWithoutReportingTrust() throws {
        let cert = try temporaryCertificate()
        defer { try? FileManager.default.removeItem(at: cert.deletingLastPathComponent()) }
        let device = CertificateDevice(id: "emulator-5554", name: "Pixel", platform: .android)
        var calls: [[String]] = []
        let result = try DeviceCertificate.install(on: device, certificate: cert, adb: "/sdk/adb") { executable, arguments in
            calls.append([executable] + arguments)
            return ""
        }
        XCTAssertEqual(calls, [
            ["/sdk/adb", "-s", device.id, "push", cert.path, "/sdcard/Download/Proxiverse-CA.cer"],
            ["/sdk/adb", "-s", device.id, "shell", "am", "start", "-a", "android.settings.SECURITY_SETTINGS"]
        ])
        XCTAssertTrue(result.contains("only been copied"))
        XCTAssertTrue(result.contains("requires confirmation"))
        XCTAssertThrowsError(try DeviceCertificate.install(on: device, certificate: cert, adb: nil))
        var count = 0
        let partial = try DeviceCertificate.install(on: device, certificate: cert, adb: "/sdk/adb") { _, _ in
            count += 1
            if count == 2 { throw AppFailure("Settings unavailable") }
            return ""
        }
        XCTAssertTrue(partial.contains("could not be opened"))
        count = 0
        XCTAssertThrowsError(try DeviceCertificate.install(on: device, certificate: cert, adb: "/sdk/adb") { _, _ in
            count += 1
            throw AppFailure("Push failed")
        })
        XCTAssertEqual(count, 1)
    }

    func testMissingCertificateDoesNotRunCommands() {
        XCTAssertThrowsError(try DeviceCertificate.install(
            on: CertificateDevice(id: "device", name: "iPhone", platform: .simulator),
            certificate: URL(fileURLWithPath: "/missing/mitmproxy-ca-cert.pem"), adb: nil) { _, _ in
                XCTFail("No command should run without a CA")
                return ""
            })
    }

    func testAutomaticInstallRefusesNonRootPhoneWithoutCopyingAnything() throws {
        let cert = try temporaryCertificate()
        defer { try? FileManager.default.removeItem(at: cert.deletingLastPathComponent()) }
        try Data("-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----".utf8).write(to: cert)
        var calls: [[String]] = []
        XCTAssertThrowsError(try DeviceCertificate.installAutomatically(
            on: CertificateDevice(id: "phone", name: "Phone", platform: .android),
            certificate: cert, adb: "/sdk/adb", helper: cert) { _, arguments in
                calls.append(arguments)
                return "2000\n"
            }) { error in
                XCTAssertTrue(error.localizedDescription.contains("requires root ADB access"))
            }
        XCTAssertTrue(calls.allSatisfy { $0 == ["-s", "phone", "shell", "id", "-u"] })
    }

    func testAutomaticInstallVerifiesNativeResultAndCleansUpAfterFailure() throws {
        let cert = try temporaryCertificate()
        defer { try? FileManager.default.removeItem(at: cert.deletingLastPathComponent()) }
        try Data("-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----".utf8).write(to: cert)
        let device = CertificateDevice(id: "emulator-5554", name: "Pixel", platform: .android)
        for confirmed in [false, true] {
            var calls: [[String]] = []
            var rooted = false
            let operation = {
                try DeviceCertificate.installAutomatically(on: device, certificate: cert, adb: "/sdk/adb", helper: cert) { _, arguments in
                    calls.append(arguments)
                    XCTAssertEqual(Array(arguments.prefix(2)), ["-s", device.id])
                    if arguments.contains("id") { return rooted ? "0\n" : "2000\n" }
                    if arguments.contains("root") { rooted = true; return "restarting adbd as root" }
                    if arguments.contains("get-current-user") { return "10\n" }
                    if arguments.contains("app_process") {
                        XCTAssertEqual(arguments.last, "10")
                        return confirmed ? "PROXIVERSE_CA_INSTALLED:user:12345678.0\n" : "unknown output"
                    }
                    return ""
                }
            }
            if confirmed { XCTAssertTrue(try operation().contains("installed and verified")) }
            else { XCTAssertThrowsError(try operation()) }
            XCTAssertEqual(Array(calls.last!.prefix(5)), ["-s", device.id, "shell", "rm", "-rf"])
            XCTAssertEqual(calls.filter { $0.contains("push") }.count, 2)
            XCTAssertTrue(calls.contains(["-s", device.id, "root"]))
        }
    }

    func testAutomaticInstallRejectsPrivateKeyBeforeRunningADB() throws {
        let cert = try temporaryCertificate()
        defer { try? FileManager.default.removeItem(at: cert.deletingLastPathComponent()) }
        try Data("-----BEGIN CERTIFICATE-----\n-----BEGIN PRIVATE KEY-----".utf8).write(to: cert)
        XCTAssertThrowsError(try DeviceCertificate.installAutomatically(
            on: CertificateDevice(id: "emulator-5554", name: "Pixel", platform: .android),
            certificate: cert, adb: "/sdk/adb", helper: cert) { _, _ in
                XCTFail("Private keys must never reach ADB")
                return ""
            })
    }

    func testAutomaticInstallationOnOptInConnectedEmulator() throws {
        guard let serial = ProcessInfo.processInfo.environment["PROXIVERSE_CERT_TEST_EMULATOR"], serial.hasPrefix("emulator-") else {
            throw XCTSkip("Set PROXIVERSE_CERT_TEST_EMULATOR to explicitly install this Mac's CA on a test emulator")
        }
        let device = CertificateDevice(id: serial, name: serial, platform: .android)
        for _ in 0..<2 {
            let result = try DeviceCertificate.installAutomatically(on: device, certificate: RuntimePaths().certificate,
                                                                   adb: DeviceCertificate.adbPath())
            XCTAssertTrue(result.contains("installed and verified"))
        }
    }

    private func temporaryCertificate() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cert = directory.appendingPathComponent("mitmproxy-ca-cert.pem")
        try Data("public-cert-fixture".utf8).write(to: cert)
        return cert
    }
}
