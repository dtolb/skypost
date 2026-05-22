// TemplateListView — @Query-driven list of saved templates.
//
// Architecture §6.1 + §6.5: @Query directly in the view (no ViewModel, no
// TemplateStore wrapper), SwiftData for persistence, NavigationStack with
// value-based destinations.

import SwiftUI
import SwiftData
import DesignSystem

public struct TemplateListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(TemplateApplier.self) private var applier: TemplateApplier?
    @Query(sort: \Template.updatedAt, order: .reverse) private var templates: [Template]

    @State private var newSheetPresented: Bool = false
    @State private var navigationTarget: Template?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ScrollView {
                        VStack(spacing: 16) {
                            WelcomeHero(
                                "No templates yet",
                                subtitle: "Tap + to save your first."
                            )
                            BrandCard {
                                Button {
                                    newSheetPresented = true
                                } label: {
                                    Label("New template", systemImage: "plus")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .background(BrandColor.pageBackground)
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                applier?.apply(template)
                            } label: {
                                TemplateRow(template: template)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    navigationTarget = template
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    delete(template)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(template)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    navigationTarget = template
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $navigationTarget) { template in
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

    private func delete(_ template: Template) {
        // If the editor was pushed against this template, dismiss it before
        // the model disappears under the destination view.
        if navigationTarget == template {
            navigationTarget = nil
        }
        modelContext.delete(template)
        try? modelContext.save()
    }
}

// MARK: - Row

private struct TemplateRow: View {
    let template: Template

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LeadIcon(
                systemName: "doc.text",
                tint: BrandColor.deterministicColor(for: template.title)
            )
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
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#Preview("Templates — populated") {
    TemplateListView()
        .modelContainer(makePreviewContainer(populated: true))
        .environment(TemplateApplier())
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
