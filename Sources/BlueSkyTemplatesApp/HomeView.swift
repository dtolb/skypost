// HomeView — Mantis welcome surface at tab position 1.
//
// Reads `SessionInfo` from the parent, `[Template]` via `@Query`, and
// `SentSessionLog` from the environment. Owns the New-Template sheet
// presentation locally; flips parent-owned `selectedTab` for the other
// three quick actions via a `Binding<AppTab>`.
//
// `handleHomeAction` is a pure helper extracted above the view so that
// action routing is unit-testable without a SwiftUI host. The view's
// buttons call it with `inout` references to local `@State` and the
// `Binding<AppTab>`'s wrapped value — exactly the same code path that
// the tests exercise.

import SwiftUI
import SwiftData
import Compose
import Templates
import Models
import DesignSystem

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pure action helper

public enum HomeAction: Equatable {
    case compose
    case newTemplate
    case templates
    case settings
}

/// Mutates the parent state in response to a HomeView action. Pure helper
/// extracted so action routing is unit-testable without a SwiftUI host.
@MainActor
public func handleHomeAction(
    _ action: HomeAction,
    selectedTab: inout AppTab,
    newTemplateSheetPresented: inout Bool
) {
    switch action {
    case .compose:      selectedTab = .compose
    case .templates:    selectedTab = .templates
    case .settings:     selectedTab = .settings
    case .newTemplate:  newTemplateSheetPresented = true
    }
}

// MARK: - View

public struct HomeView: View {

    public let session: SessionInfo
    @Binding public var selectedTab: AppTab

    @Environment(SentSessionLog.self) private var sessionLog: SentSessionLog?
    @Query(sort: \Template.updatedAt, order: .reverse) private var templates: [Template]
    @State private var newTemplateSheetPresented: Bool = false
    // Per-row "Copied" confirmation; cleared after a short delay.
    @State private var copiedURI: String? = nil

    public init(session: SessionInfo, selectedTab: Binding<AppTab>) {
        self.session = session
        self._selectedTab = selectedTab
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    quickActions
                    sessionList
                }
                .padding(.vertical, 8)
            }
            .background(BrandColor.pageBackground)
            .navigationTitle("Home")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $newTemplateSheetPresented) {
                TemplateEditorView(mode: .new)
            }
        }
    }

    // MARK: - Sections

    private var hero: some View {
        WelcomeHero(
            "Welcome back",
            subtitle: "@\(session.handle)"
        )
        .overlay(alignment: .topTrailing) {
            Text("\(templates.count) \(templates.count == 1 ? "template" : "templates")")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.22), in: .capsule)
                .foregroundStyle(.white)
                .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private var quickActions: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 8
        ) {
            actionCell(systemName: "square.and.pencil", title: "Compose",   action: .compose)
            actionCell(systemName: "plus",              title: "New",       action: .newTemplate)
            actionCell(systemName: "doc.text",          title: "Templates", action: .templates)
            actionCell(systemName: "gearshape",         title: "Settings",  action: .settings)
        }
        .padding(.horizontal, 16)
    }

    private func actionCell(systemName: String, title: String, action: HomeAction) -> some View {
        Button {
            handleHomeAction(
                action,
                selectedTab: &selectedTab,
                newTemplateSheetPresented: &newTemplateSheetPresented
            )
        } label: {
            VStack(spacing: 8) {
                LeadIcon(systemName: systemName, tint: BrandColor.tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white, in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            // +4 inside-card gutter so the header aligns with the row content,
            // not the card edge.
            BrandSectionHeader("Sent this session")
                .padding(.horizontal, 16 + 4)
            if let log = sessionLog, !log.entries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(log.entries) { entry in
                        sessionRow(entry)
                        if entry.id != log.entries.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color.white, in: .rect(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
            } else {
                Text("Nothing sent yet — go post something.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16 + 4)
            }
        }
    }

    private func sessionRow(_ entry: SentSessionLog.Entry) -> some View {
        Button {
            copy(entry.uri)
            copiedURI = entry.uri
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedURI == entry.uri { copiedURI = nil }
            }
        } label: {
            HStack(spacing: 12) {
                LeadIcon(systemName: "checkmark.seal.fill", tint: BrandColor.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.preview.isEmpty ? entry.uri : entry.preview)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if copiedURI == entry.uri {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Sent: \(entry.preview). \(entry.createdAt.formatted(.relative(presentation: .named))). Tap to copy URI."
        )
    }

    // MARK: - Copy

    private func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
