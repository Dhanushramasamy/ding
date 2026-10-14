import SwiftUI

/// Menu bar only app: no Dock icon (LSUIElement), no main window.
@main
struct DingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(
                store: appDelegate.reminders,
                prefs: appDelegate.prefs,
                onHideEverything: { appDelegate.cover.show() },
                onTest: { appDelegate.test() }
            )
        } label: {
            MenuBarLabel(store: appDelegate.reminders)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let prefs = Preferences()
    let cover = CoverController()
    let reminders = ReminderStore()
    private let shows = ReminderShowController()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        reminders.onFire = { [weak self] reminder in
            guard let self else { return }
            self.shows.show(reminder, character: self.prefs.character)
        }
        shows.onSnooze = { [weak self] reminder in
            self?.reminders.add(after: 5 * 60, message: reminder.message, title: "Snoozed 5 min")
        }
        // ⌃⌥H toggles the cover from anywhere, without opening the menu.
        hotKey = HotKey(keyCode: HotKey.keyH, modifiers: HotKey.controlOption) { [weak self] in
            self?.cover.toggle()
        }
        // Development aid: `DING_TEST=1 open Ding.app` plays a reminder at launch.
        if ProcessInfo.processInfo.environment["DING_TEST"] == "1" {
            test()
        }
    }

    /// Plays the chosen character right away with a sample reminder.
    func test() {
        let sample = Reminder(fireDate: Date(), message: "Stand up and stretch.", title: "Test reminder")
        shows.show(sample, character: prefs.character)
    }
}
