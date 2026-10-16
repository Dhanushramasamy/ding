import SwiftUI

/// The menu bar icon; shows a countdown to the next reminder when one is pending.
struct MenuBarLabel: View {
    @ObservedObject var store: ReminderStore

    var body: some View {
        if let next = store.next {
            HStack(spacing: 3) {
                Image(systemName: "stopwatch")
                Text(store.remaining(next)).monospacedDigit()
            }
        } else {
            Image(systemName: "stopwatch")
        }
    }
}

/// The panel that drops down from the menu bar icon.
struct MenuView: View {
    @ObservedObject var store: ReminderStore
    @ObservedObject var prefs: Preferences
    let onHideEverything: () -> Void
    let onTest: () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var message = ""
    @State private var minutes = 10
    @State private var alarmTime = Date().addingTimeInterval(3600)
    @FocusState private var messageFocused: Bool

    private static let presets = [1, 5, 10, 25, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            PanelGroup(title: "New reminder") {
                TextField("What should I remind you about?", text: $message)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($messageFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.1)))
                    .onSubmit { startTimer(minutes: minutes) }

                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { preset in
                        Button("\(preset)m") { startTimer(minutes: preset) }
                            .buttonStyle(PillButtonStyle())
                    }
                }

                Divider().opacity(0.5)

                HStack {
                    Text("In")
                        .foregroundStyle(.secondary)
                    Stepper(value: $minutes, in: 1...600) {
                        Text("\(minutes) min").monospacedDigit()
                    }
                    Spacer()
                    Button("Start") { startTimer(minutes: minutes) }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
                HStack {
                    Text("At")
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                    Button("Set alarm") {
                        store.add(alarmAt: alarmTime, message: reminderText)
                        message = ""
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            if !store.reminders.isEmpty {
                PanelGroup(title: "Upcoming") {
                    ForEach(store.reminders) { reminder in
                        HStack(spacing: 12) {
                            Text(store.remaining(reminder))
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(reminder.message).lineLimit(1)
                                Text(reminder.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                store.cancel(reminder)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            PanelGroup(title: "Delivered by") {
                let characters = Character.all
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { prefs.character?.name ?? "" },
                        set: { prefs.characterName = $0 }
                    )) {
                        ForEach(characters) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                    if let chosen = prefs.character, chosen.isCustom {
                        Button {
                            CustomCharacters.remove(chosen)
                            prefs.characterName = ""
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(PillButtonStyle())
                        .help("Remove this image")
                    }
                    Spacer()
                    Button {
                        closeAndRun(onTest)
                    } label: {
                        Label("Preview", systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                }
                Button {
                    closeAndRun {
                        openWindow(id: AddImageView.windowID)
                        NSApp.activate()
                    }
                } label: {
                    Label("Add your image…", systemImage: "photo.badge.plus")
                }
                .buttonStyle(PillButtonStyle())
            }

            HStack(spacing: 8) {
                Button {
                    closeAndRun(onHideEverything)
                } label: {
                    Label("Hide Everything", systemImage: "eye.slash")
                }
                .buttonStyle(PillButtonStyle())
                Text("⌃⌥H")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconArtwork()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(Brand.name)
                    .font(.system(size: 17, weight: .bold))
                Text(Brand.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var reminderText: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Time’s up." : trimmed
    }

    private func startTimer(minutes: Int) {
        store.add(after: TimeInterval(minutes * 60), message: reminderText)
        message = ""
    }

    /// Closes the menu bar window first so it doesn't sit on top of what comes next.
    private func closeAndRun(_ action: @escaping () -> Void) {
        NSApp.keyWindow?.close()
        DispatchQueue.main.async(execute: action)
    }
}
