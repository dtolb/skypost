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

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(UIKit)
import UIKit
#endif

public struct ComposeView: View {

    @Environment(\.apiClient) private var api: APIClient?

    @State private var text: String = ""
    @State private var attachments: [ComposeAttachment] = []
    @State private var send: SendState = .idle
    @FocusState private var editorFocused: Bool

    #if canImport(PhotosUI)
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var attachmentError: String?
    #endif

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

                Section("Images") {
                    #if canImport(PhotosUI)
                    // Snapshot the count so the picker's @Sendable label
                    // closure doesn't capture the main-actor-isolated
                    // `attachments` array directly (Swift 6 strict).
                    let currentCount = attachments.count
                    PhotosPicker(
                        selection: $pickerSelection,
                        maxSelectionCount: ComposeText.attachmentLimit - currentCount,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Add image (\(currentCount)/\(ComposeText.attachmentLimit))", systemImage: "photo.badge.plus")
                    }
                    .disabled(!ComposeText.canAttach(currentCount: currentCount) || isSending)
                    #else
                    Text("Image attachments are iOS-only.")
                        .foregroundStyle(.secondary)
                    #endif

                    #if canImport(PhotosUI)
                    if let attachmentError {
                        Label(attachmentError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                    #endif

                    ForEach($attachments) { $attachment in
                        AttachmentRow(attachment: $attachment, onRemove: { remove(attachment) })
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
                attachments = []
                send = .idle
            }
            #if canImport(PhotosUI)
            // PhotosPickerItems land here async; the picker itself can't host
            // an async loader. We move loaded items into the typed
            // `ComposeAttachment` list and immediately clear `pickerSelection`
            // so the picker is ready for the next add (also stops the loader
            // from re-firing on the same items if state diff'd weirdly).
            .onChange(of: pickerSelection) { _, newItems in
                guard !newItems.isEmpty else { return }
                attachmentError = nil
                Task {
                    await ingest(items: newItems)
                    pickerSelection.removeAll()
                }
            }
            #endif
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
        api != nil
            && ComposeText.isSubmittable(text: text, attachments: attachments)
            && !isSending
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
        // Flatten attachments into the cross-module value tuple — keeps
        // the Bluesky SDK types from leaking out of `Bluesky`.
        let pack = attachments.map {
            (jpegData: $0.jpegData,
             altText: $0.altText,
             pixelWidth: $0.pixelWidth,
             pixelHeight: $0.pixelHeight)
        }
        editorFocused = false
        self.send = .sending
        Task {
            do {
                let uri = try await api.createPost(text: body, images: pack)
                self.send = .sent(uri: uri)
            } catch {
                self.send = .failed(message: error.localizedDescription)
            }
        }
    }

    #if canImport(PhotosUI)
    /// Pulls picker items' raw bytes, runs each through `ImageProcessor`
    /// (resize + JPEG re-encode under the 1 MB cap), and appends a
    /// `ComposeAttachment` per success. The `attachmentLimit` re-check
    /// inside the loop defends against a race where the picker hands us
    /// more items than the cap allows (e.g. user pasted bursts).
    private func ingest(items: [PhotosPickerItem]) async {
        for item in items {
            if attachments.count >= ComposeText.attachmentLimit { break }
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    attachmentError = "Couldn't load one of the selected images."
                    continue
                }
                let encoded = try ImageProcessor.encodeJPEG(sourceData: raw)
                attachments.append(ComposeAttachment(
                    jpegData: encoded.data,
                    pixelWidth: encoded.pixelWidth,
                    pixelHeight: encoded.pixelHeight
                ))
            } catch let err as ImageProcessorError {
                attachmentError = imageErrorMessage(for: err)
            } catch {
                attachmentError = "Couldn't import that image."
            }
        }
    }

    private func imageErrorMessage(for error: ImageProcessorError) -> String {
        switch error {
        case .cannotDecodeSource: return "That file doesn't look like an image."
        case .cannotEncodeJPEG:   return "Couldn't encode that image to JPEG."
        case .cannotFit(let cap): return "Image is too big to fit under \(cap / 1024) KB even after resizing."
        }
    }
    #endif

    private func remove(_ attachment: ComposeAttachment) {
        attachments.removeAll { $0.id == attachment.id }
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

// MARK: - AttachmentRow

/// One row in the Images section: thumbnail + alt-text TextField +
/// remove button. Kept in this file because it has no reason to be
/// reused elsewhere and the binding into the parent's `attachments`
/// array makes lifetime tied to ComposeView.
private struct AttachmentRow: View {
    @Binding var attachment: ComposeAttachment
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Alt text (required for accessibility)", text: $attachment.altText, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.callout)
                    Text("\(attachment.pixelWidth)×\(attachment.pixelHeight)px · \((attachment.jpegData.count / 1024)) KB")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Button(role: .destructive, action: onRemove) {
                Label("Remove image", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: attachment.jpegData) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            Rectangle().fill(.thinMaterial)
        }
        #else
        Rectangle().fill(.thinMaterial)
        #endif
    }
}

#Preview("Compose — idle") {
    ComposeView()
    // No apiClient injected — Send stays disabled via the api-nil guard.
}
