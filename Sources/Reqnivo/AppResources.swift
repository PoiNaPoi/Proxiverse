import Foundation

enum AppResources {
    static let bundle: Bundle = {
        // SwiftPM's generated lookup varies by toolchain; packaged apps use this location.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Reqnivo_Reqnivo.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
