// TemplateListView — @Query-driven list of saved templates.
//
// Architecture §6.1 + §6.5: @Query directly in the view (no ViewModel, no
// TemplateStore wrapper), SwiftData for persistence, NavigationStack with
// value-based destinations.

import SwiftUI
import SwiftData

public struct TemplateListView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Template.updatedAt, order: .reverse) private var templates: [Template]

    @State private var newSheetPresented: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No templates yet",
                        systemImage: "doc.text",
                        description: Text("Tap + to create one.")
                    )
                } else {
                    List {
                        ForEach(templates) { template in
                            NavigationLink(value: template) {
                                TemplateRow(template: template)
                            }
                        }
                        .onDelete { offsets in delete(at: offsets) }
                    }
                }
            }
            .navigationTitle("Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: Template.self) { template in
                TemplateEditorView(mode: .editing(template))
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newSheetPresented = true
                    } label: {
                        Label("New template", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $newSheetPresented) {
                TemplateEditorView(mode: .new)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(templates[index])
        }
        // SwiftData usually auto-saves, but save explicitly so the row
        // vanishes immediately and the behavior is pinnable in a test.
        try? modelContext.save()
    }
}

// MARK: - Row

private struct TemplateRow: View {
    let template: Template

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.title).font(.headline)
            Text(template.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !template.hashtags.isEmpty {
                Text(template.hashtags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#Preview("Templates — populated") {
    TemplateListView()
        .modelContainer(makePreviewContainer(populated: true))
}

#Preview("Templates — empty") {
    TemplateListView()
        .modelContainer(makePreviewContainer(populated: false))
}

@MainActor
private func makePreviewContainer(populated: Bool) -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Template.self, configurations: config)
    if populated {
        let context = ModelContext(container)
        context.insert(Template(title: "Daily standup", body: "What did you ship? What's blocked?", hashtags: ["work"]))
        context.insert(Template(title: "Hello bluesky", body: "Hi from the templates app.", hashtags: ["bsky"]))
    }
    return container
}
