// ComposeView — text-only post composer.
//
// Local state only (per architecture §6.1): a small SendState enum drives
// the four UI moments (idle / sending / sent / failed). The send action
// kicks off a Task that awaits APIClient.createPost and folds the result
// back into the same enum on the main actor (Swift 6.2 Approachable
// Concurrency: Task closures inherit isolation from their enclosing
// context — no MainActor.run).
//
// Graceful when no APIClient is injected (e.g. previews): the Send button
// stays disabled via `canSend`, and an explicit tap surfaces an error
// message rather than crashing the way the Hello tab does.

import SwiftUI
import Bluesky

public struct ComposeView: View {

    @Environment(\.apiClient) private var api: APIClient?

    @State private var text: String = ""
    @State private var send: SendState = .idle
    @FocusState private var editorFocused: Bool

    // Equatable so `.task(id: send)` can detect transitions, and so the
    // computed helpers below can pattern-match cleanly.
    private enum SendState: Equatable {
        case idle
        case sending
        case sent(uri: String)
        case failed(message: String)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's on your mind?", text: $text, axis: .vertical)
                        .font(.body)
                        .lineLimit(8...20)
                        .focused($editorFocused)
                        .disabled(isSending)
                }

                Section {
                    HStack {
                        Spacer()
                        Text(counterLabel)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(remaining < 0
                                ? AnyShapeStyle(.red)
                                : AnyShapeStyle(.secondary))
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            if isSending { ProgressView() }
                            Text(sendButtonTitle).frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
                }

                resultSection
            }
            .navigationTitle("Compose")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear { editorFocused = true }
            // Auto-clear after success: 2-second URI dwell, then reset.
            // Re-check the case before mutating so a brand-new send started
            // during the dwell window isn't clobbered back to idle.
            .task(id: send) {
                guard case .sent = send else { return }
                try? await Task.sleep(for: .seconds(2))
                guard case .sent = send else { return }
                text = ""
                send = .idle
            }
        }
    }

    // MARK: - Result section

    @ViewBuilder
    private var resultSection: some View {
        switch send {
        case .idle, .sending:
            EmptyView()
        case .sent(let uri):
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Posted!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text(uri)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .contextMenu {
                            Button {
                                copy(uri)
                            } label: {
                                Label("Copy URI", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Derived state

    private var remaining: Int {
        ComposeText.remaining(text)
    }

    private var counterLabel: String {
        "\(remaining)"
    }

    private var isSending: Bool {
        if case .sending = send { return true }
        return false
    }

    private var canSend: Bool {
        api != nil && ComposeText.isSubmittable(text) && !isSending
    }

    private var sendButtonTitle: String {
        switch send {
        case .idle, .failed: return "Send"
        case .sending:       return "Sending…"
        case .sent:          return "Sent"
        }
    }

    // MARK: - Actions

    // Named `submit()` rather than `send()` because the @State property is
    // also `send` — Swift's same-namespace rule for stored property vs
    // zero-arg method would collide. Matches LoginView's verb choice.
    private func submit() {
        guard let api else {
            // Preview / un-injected: don't crash, surface why nothing happened.
            send = .failed(message: "Composer is not connected to the network yet.")
            return
        }
        guard canSend else { return }
        let body = text
        editorFocused = false
        self.send = .sending
        Task {
            do {
                let uri = try await api.createPost(text: body)
                self.send = .sent(uri: uri)
            } catch {
                self.send = .failed(message: error.localizedDescription)
            }
        }
    }

    private func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

#Preview("Compose — idle") {
    ComposeView()
    // No apiClient injected — Send stays disabled via the api-nil guard.
}
