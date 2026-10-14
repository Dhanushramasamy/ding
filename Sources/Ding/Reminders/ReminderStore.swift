import Foundation

struct Reminder: Identifiable {
    let id = UUID()
    let fireDate: Date
    let message: String
    /// What kind of reminder this was, e.g. "10 min timer" or "Alarm · 3:45 PM".
    let title: String
}

/// Holds pending timers and alarms, and ticks once a second while any exist.
/// Reminders live in memory only; quitting the app drops them.
@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [Reminder] = []
    @Published private(set) var now = Date()

    var onFire: (Reminder) -> Void = { _ in }

    private var ticker: Timer?

    var next: Reminder? { reminders.first }

    func add(after seconds: TimeInterval, message: String, title: String? = nil) {
        let minutes = Int((seconds / 60).rounded())
        add(Reminder(
            fireDate: Date().addingTimeInterval(seconds),
            message: message,
            title: title ?? "\(minutes) min timer"
        ))
    }

    /// Fires at the next occurrence of the given clock time (today, or tomorrow if it has passed).
    func add(alarmAt time: Date, message: String) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        guard let fireDate = Calendar.current.nextDate(
            after: Date(),
            matching: parts,
            matchingPolicy: .nextTime
        ) else { return }
        add(Reminder(
            fireDate: fireDate,
            message: message,
            title: "Alarm · \(fireDate.formatted(date: .omitted, time: .shortened))"
        ))
    }

    func cancel(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
        stopTickerIfIdle()
    }

    /// "4:05" or "1:04:05" until the reminder fires.
    func remaining(_ reminder: Reminder) -> String {
        let total = max(0, Int(reminder.fireDate.timeIntervalSince(now).rounded(.up)))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private func add(_ reminder: Reminder) {
        reminders.append(reminder)
        reminders.sort { $0.fireDate < $1.fireDate }
        now = Date()
        startTicker()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // `.common` keeps it ticking while the menu bar window is open.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTickerIfIdle() {
        guard reminders.isEmpty else { return }
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        now = Date()
        let due = reminders.filter { $0.fireDate <= now }
        guard !due.isEmpty else { return }
        reminders.removeAll { $0.fireDate <= now }
        due.forEach(onFire)
        stopTickerIfIdle()
    }
}
