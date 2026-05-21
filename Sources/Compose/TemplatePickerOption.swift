// TemplatePickerOption — value-typed picker entry for ComposeView's
// pinned template Menu.
//
// "Why a separate type?" SwiftUI's Menu / Picker / ForEach all want an
// Identifiable + Hashable choice. The picker has exactly two shapes
// (the synthetic "None" option, and one entry per saved Template), so
// an enum keeps the call sites pattern-matchable while still satisfying
// the protocols ForEach needs.
//
// The `title` is captured at option-build time rather than re-read from
// the Template at render time — keeps the option pure-value and avoids
// re-entering @MainActor from a non-isolated context.

import Foundation
import SwiftData
import Templates

public enum TemplatePickerOption: Identifiable, Hashable, Sendable {
    case none
    case template(PersistentIdentifier, title: String)

    public var id: AnyHashable {
        switch self {
        case .none:                            return AnyHashable("none")
        case .template(let pid, _):            return AnyHashable(pid)
        }
    }

    public var menuTitle: String {
        switch self {
        case .none:                            return "None (blank)"
        case .template(_, let title):          return title
        }
    }

    /// Maps a query result into a list of picker options with the
    /// synthetic "None" entry prepended. Pure — caller passes the
    /// already-sorted templates (the `@Query` in ComposeView handles
    /// the sort order; this helper is order-preserving).
    @MainActor
    public static func options(from templates: [Template]) -> [TemplatePickerOption] {
        var options: [TemplatePickerOption] = [.none]
        for t in templates {
            options.append(.template(t.persistentModelID, title: t.title))
        }
        return options
    }
}
