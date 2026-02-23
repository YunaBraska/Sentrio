import AppIntents
import SentrioCore

@available(macOS 14.0, *)
struct SentrioAppIntentsPackageBridge: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [SentrioCoreAppIntentsPackage.self]
    }
}
