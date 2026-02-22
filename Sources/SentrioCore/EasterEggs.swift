import Foundation

enum EasterEggs {
    static func audioDaemonStirs(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        guard c.hour == 3, let m = c.minute else { return false }
        return (0 ... 3).contains(m)
    }
}
