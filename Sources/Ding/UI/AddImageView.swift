import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Turns one of your pictures into a character. After you pick an image it asks how to
/// use it, showing both results side by side: the subject cut out of its background,
/// or the full image as it is.
struct AddImageView: View {
    static let windowID = "add-image"

    @ObservedObject var prefs: Preferences
    @Environment(\.dismissWindow) private var dismissWindow

    private enum Choice { case subject, full }

    @State private var original: CGImage?
    @State private var subject: CGImage?
    @State private var extracting = false
    @State private var choice = Choice.subject
    @State private var name = ""
    @State private var error: String?
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add your image")
                    .font(.system(size: 20, weight: .bold))
                Text("Pick a photo or drawing, and it will run onto your screen with your reminders.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if let original {
                Text("How should Ding use this image?")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 14) {
                    option(.subject,
                           title: "Extract the subject",
                           detail: subjectDetail,
                           image: subject,
                           enabled: subject != nil)
                    option(.full,
                           title: "Use the full image",
                           detail: "Keep the whole picture, background and all.",
                           image: original,
                           enabled: true)
                }

                HStack(spacing: 10) {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    TextField("My Character", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }

                HStack {
                    Button("Choose Another…", action: chooseFile)
                        .buttonStyle(PillButtonStyle())
                    Spacer()
                    Button("Cancel") { close() }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Add Character", action: add)
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(choice == .subject && subject == nil)
                }
            } else {
                dropZone
            }
        }
        .padding(24)
        .frame(width: 580)
        .background(BringToFront())
    }

    // MARK: Pieces

    private var subjectDetail: String {
        if extracting { return "Finding the subject…" }
        return subject == nil ? "No clear subject found in this image." : "Cut out the person, pet or object from its background."
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Button("Choose an Image…", action: chooseFile)
                .buttonStyle(PillButtonStyle(prominent: true))
            Text("or drop one here · PNG, JPEG, HEIC")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(dropTargeted ? Color.accentColor : .primary.opacity(0.18),
                              style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1.5, dash: [6, 5]))
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { load(url) }
            }
            return true
        }
    }

    private func option(_ value: Choice, title: String, detail: String, image: CGImage?, enabled: Bool) -> some View {
        let selected = choice == value
        return Button {
            if enabled { choice = value }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Checkerboard()
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    } else if extracting && value == .subject {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.crop.rectangle.badge.xmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.12), lineWidth: selected ? 2.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(enabled || extracting ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo or drawing to turn into a character."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        guard let image = CustomCharacters.load(url) else {
            error = "That file couldn’t be opened as an image."
            return
        }
        error = nil
        original = image
        subject = nil
        choice = .subject
        name = url.deletingPathExtension().lastPathComponent
        extracting = true
        // Subject lifting takes a moment; keep the window responsive meanwhile.
        Task.detached(priority: .userInitiated) {
            let lifted = CustomCharacters.extractSubject(from: image)
            await MainActor.run {
                subject = lifted
                extracting = false
                if lifted == nil { choice = .full }
            }
        }
    }

    private func add() {
        guard let picture = choice == .subject ? subject : original else { return }
        do {
            let character = try CustomCharacters.save(picture, named: name)
            prefs.characterName = character.name
            close()
        } catch {
            self.error = "Couldn’t save the image: \(error.localizedDescription)"
        }
    }

    private func close() {
        original = nil
        subject = nil
        error = nil
        name = ""
        dismissWindow(id: Self.windowID)
    }
}

/// The grey-and-white squares image editors use to show transparency.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.96)))
            var squares = Path()
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col).isMultiple(of: 2) {
                    squares.addRect(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            context.fill(squares, with: .color(Color(white: 0.88)))
        }
    }
}

/// Brings the window it sits in to the front as soon as it appears. Ding lives in the
/// menu bar, so without this a new window can open behind whatever app is in use.
private struct BringToFront: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.center()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
