// HomeView — signed-in landing screen.
//
// One button. Posts the literal string "hello from v2" to the user's PDS
// via APIClient (the only Bluesky-aware path), shows the resulting AT-URI,
// or shows the error. Plus sign-out.
//
// No ViewModel. Local screen state is a small @State enum (per §6.1).

import SwiftUI
import Auth
import Bluesky
import Models

public struct HomeView: View {

    public let session: SessionInfo

    @Environment(AuthService.self) private var auth
    @Environment(\.apiClient) private var api: APIClient?

    @State private var post: PostState = .idle

    private enum PostState {
        case idle
        case posting
        case posted(uri: String)
        case failed(String)
    }

    public init(session: SessionInfo) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Handle", value: session.handle)
                    LabeledContent("DID") {
                        Text(session.did)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Hello, world") {
                    Button(action: postHello) {
                        HStack {
                            if case .posting = post { ProgressView() }
                            Text(buttonTitle).frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPosting)

                    switch post {
                    case .idle:
                        EmptyView()
                    case .posting:
                        EmptyView()
                    case .posted(let uri):
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
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("BlueSky Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Derived

    private var isPosting: Bool {
        if case .posting = post { return true }
        return false
    }

    private var buttonTitle: String {
        switch post {
        case .idle, .failed: return "Post “hello from v2”"
        case .posting:       return "Posting…"
        case .posted:        return "Post another"
        }
    }

    // MARK: - Actions

    private func postHello() {
        guard let api else {
            fatalError("HomeView requires an APIClient in the environment — inject via .environment(\\.apiClient, ...) at the App root")
        }
        post = .posting
        Task {
            do {
                let uri = try await api.postHelloWorld()
                post = .posted(uri: uri)
            } catch {
                post = .failed(error.localizedDescription)
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
