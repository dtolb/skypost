// TODO(A3): replace stub.
//
// Forward declaration so TemplateListView compiles ahead of the real editor
// landing in Phase A3. A3 owns this file and will replace the body + add
// Form fields, save/cancel toolbar items, and parseHashtags wiring.

import SwiftUI

public struct TemplateEditorView: View {
    public enum Mode {
        case new
        case editing(Template)
    }

    private let mode: Mode

    public init(mode: Mode) {
        self.mode = mode
    }

    public var body: some View {
        Text("TemplateEditorView (A3 not yet implemented; mode = \(String(describing: mode)))")
            .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        switch mode {
        case .new:     return "New Template"
        case .editing: return "Edit Template"
        }
    }
}
