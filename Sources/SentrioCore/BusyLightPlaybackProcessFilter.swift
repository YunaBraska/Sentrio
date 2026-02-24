import Foundation

enum BusyLightPlaybackProcessFilter {
    static func isActiveOutputProcess(
        outputRunning: UInt32?,
        ioRunning: UInt32?,
        processID: Int32?,
        ownProcessID: Int32,
        bundleID _: String?
    ) -> Bool {
        guard let outputRunning, outputRunning != 0 else { return false }
        guard let ioRunning, ioRunning != 0 else { return false }
        guard let processID, processID != ownProcessID else { return false }
        // Intentionally do not filter by bundle identifier:
        // Safari media output comes from com.apple.WebKit helper processes.
        return true
    }
}
