// TemplateEditorView — create or edit a Template.
//
// Two presentation contexts share one view: a sheet from TemplateListView's
// "+" toolbar (.new) and a push via .navigationDestination (.editing). The
// sheet case needs its own NavigationStack; the push case must NOT wrap one
// or the toolbar items end up on the inner stack and the existing back
// button disappears.

import SwiftUI
import SwiftData
import DesignSystem

public struct TemplateEditorView: View {

    public enum Mode {
        case new
        case editing(Template)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    private let template: Template?

    // `bodyText` not `body`: SwiftUI reserves `body` for the view itself.
    @State private var title: String
    @State private var bodyText: String
    @State private var hashtagsRaw: String

    public init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new:
            self.template = nil
            self._title = State(initialValue: "")
            self._bodyText = State(initialValue: "")
            self._hashtagsRaw = State(initialValue: "")
        case .editing(let existing):
            self.template = existing
            self._title = State(initialValue: existing.title)
            self._bodyText = State(initialValue: existing.body)
            self._hashtagsRaw = State(initialValue: existing.hashtags.joined(separator: ", "))
        }
    }

    public var body: some View {
        switch mode {
        case .new:
            NavigationStack { content }
        case .editing:
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Form {
            Section {
                TextField("Daily standup", text: $title)
            } header: {
                BrandSectionHeader("Title")
            }

            Section {
                TextField("What did you ship?", text: $bodyText, axis: .vertical)
                    .lineLimit(4...10)
            } header: {
                BrandSectionHeader("Body")
            }

            Section {
                TextField("bsky, swiftui", text: $hashtagsRaw)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                BrandSectionHeader("Hashtags")
            } footer: {
                Text("Separate with commas. # is optional.")
            }
        }
        .navigationTitle(mode.navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedHashtags = parseHashtags(hashtagsRaw)

        if let template {
            template.title = trimmedTitle
            template.body = trimmedBody
            template.hashtags = parsedHashtags
            template.touch()
        } else {
            let new = Template(title: trimmedTitle, body: trimmedBody, hashtags: parsedHashtags)
            modelContext.insert(new)
        }
        try? modelContext.save()
        dismiss()
    }
}

private extension TemplateEditorView.Mode {
    var navigationTitle: String {
        switch self {
        case .new:     return "New Template"
        case .editing: return "Edit Template"
        }
    }
}

// MARK: - Previews

#Preview("New template") {
    TemplateEditorView(mode: .new)
        .modelContainer(makeEditorPreviewContainer())
}

#Preview("Edit template") {
    let container = makeEditorPreviewContainer()
    let t = Template(title: "Daily standup", body: "What did you ship?", hashtags: ["work"])
    return NavigationStack { TemplateEditorView(mode: .editing(t)) }
        .modelContainer(container)
}

@MainActor
private func makeEditorPreviewContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try! ModelContainer(for: Template.self, configurations: config)
}
