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
//
// Phase F link-card auto-detect: when the user types a http/https URL,
// `.task(id: detectedURL)` debounces 600ms, then calls the injected
// `ExternalLinkResolver` to fetch OG metadata. Result renders as a
// `LinkCardRow` in the Link section. User can dismiss via Remove (URL
// goes into `dismissedURLs` so it doesn't auto-re-attach). Images embed
// wins per Bluesky's exclusive embed slot — when `!attachments.isEmpty`,
// `detectedURL` returns nil and no card surfaces. URL still becomes a
// clickable facet via ATFacetParser server-side.

import SwiftUI
import SwiftData
import Bluesky
import Camera
import DesignSystem
import Models
import Templates

#if canImport(Pow)
import Pow
#endif

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(UIKit)
import UIKit
#endif

public struct ComposeView: View {

    @Environment(\.apiClient) private var api: APIClient?
    @Environment(\.externalLinkResolver) private var resolver: (any ExternalLinkResolver)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TemplateApplier.self) private var applier: TemplateApplier?
    // Optional because the environment value may be absent in previews and
    // tests; `sessionLog?.append(...)` is a no-op when nil. Wired into
    // AppRoot as a long-lived `@State` and injected via
    // `.environment(sessionLog)`.
    @Environment(SentSessionLog.self) private var sessionLog: SentSessionLog?

    @Query(sort: \Template.updatedAt, order: .reverse) private var templates: [Template]

    // Picker selection is TRANSIENT (not derived from applier.pending) —
    // once Composer ingests an apply, applier.consume() nils pending out,
    // but the picker label should keep showing "Daily Fuji" until the
    // user explicitly picks something else (including "None"). nil = None.
    //
    // Named `templatePickerSelection` (not `pickerSelection`) to avoid
    // colliding with the existing PhotosPicker selection below.
    @State private var templatePickerSelection: PersistentIdentifier?

    @State private var text: String = ""
    @State private var attachments: [ComposeAttachment] = []
    @State private var send: SendState = .idle
    // Monotonic tick that fires the send-spray + success haptic exactly once
    // per successful post (architecture §11 step 5).
    @State private var sendSuccessTick: Int = 0
    // Link-card flow (Phase F): four-state machine driven by
    // `.task(id: detectedURL)`. `dismissedURLs` is the user's "I don't
    // want a card for this URL" memory — Remove drops the URL in here so
    // re-evaluating `detectedURL` after the next keystroke doesn't
    // auto-re-attach the same card.
    @State private var linkState: LinkLoadState = .idle
    @State private var dismissedURLs: Set<URL> = []
    @FocusState private var editorFocused: Bool

    #if canImport(PhotosUI)
    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var attachmentError: String?
    #endif

    #if os(iOS)
    @State private var cameraPresented: Bool = false
    #endif

    // Equatable so `.task(id: send)` can detect transitions, and so the
    // computed helpers below can pattern-match cleanly.
    private enum SendState: Equatable {
        case idle
        case sending
        case sent(uri: String)
        case failed(message: String)
    }

    // Equatable so `.task(id: linkState)` style observers are possible
    // and the .loaded case can compare ExternalLinkCards by value.
    private enum LinkLoadState: Equatable {
        case idle
        case loading(URL)
        case loaded(ExternalLinkCard)
        case failed(URL, reason: String)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TemplatePickerLabel(
                        selection: templatePickerSelection,
                        templates: templates,
                        onSelect: handlePickerSelection(_:)
                    )
                    .disabled(isSending)
                }

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
                                ? AnyShapeStyle(BrandColor.error)
                                : AnyShapeStyle(.secondary))
                    }
                }

                Section {
                    #if canImport(PhotosUI)
                    // Snapshot the count so the picker's @Sendable label
                    // closure doesn't capture the main-actor-isolated
                    // `attachments` array directly (Swift 6 strict).
                    let currentCount = attachments.count
                    HStack {
                        PhotosPicker(
                            selection: $pickerSelection,
                            maxSelectionCount: ComposeText.attachmentLimit - currentCount,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Add image (\(currentCount)/\(ComposeText.attachmentLimit))", systemImage: "photo.badge.plus")
                        }
                        .disabled(!ComposeText.canAttach(currentCount: currentCount) || isSending)
                        #if os(iOS)
                        Spacer()
                        Button {
                            cameraPresented = true
                        } label: {
                            Image(systemName: "camera")
                                .font(.body.weight(.semibold))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!ComposeText.canAttach(currentCount: currentCount) || isSending)
                        .accessibilityLabel("Take photo")
                        #endif
                    }
                    #else
                    Text("Image attachments are iOS-only.")
                        .foregroundStyle(.secondary)
                    #endif

                    #if canImport(PhotosUI)
                    if let attachmentError {
                        Label(attachmentError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(BrandColor.error)
                            .font(.callout)
                    }
                    #endif

                    ForEach($attachments) { $attachment in
                        AttachmentRow(attachment: $attachment, onRemove: { remove(attachment) })
                    }
                } header: {
                    BrandSectionHeader("Images")
                }

                // Hide the Link section entirely when idle; rendering an
                // empty Section still draws its header chrome.
                switch linkState {
                case .idle:
                    EmptyView()
                case .loading, .loaded, .failed:
                    Section {
                        linkSectionContent
                    } header: {
                        BrandSectionHeader("Link")
                    }
                }

                Section {
                    sendButton
                }

                resultSection
            }
            .navigationTitle("Compose")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
            #endif
            .onAppear { editorFocused = true }
            .onDisappear { dismissKeyboard() }
            // Auto-clear after success: 2-second URI dwell, then reset.
            // Re-check the case before mutating so a brand-new send started
            // during the dwell window isn't clobbered back to idle.
            .task(id: send) {
                guard case .sent = send else { return }
                // Bump BEFORE the dwell so the Pow spray + success haptic fire
                // immediately on success, not after the auto-clear delay.
                sendSuccessTick += 1
                try? await Task.sleep(for: .seconds(2))
                guard case .sent = send else { return }
                text = ""
                attachments = []
                linkState = .idle
                dismissedURLs.removeAll()
                templatePickerSelection = nil
                send = .idle
            }
            // Phase F link-card flow: re-fires whenever `detectedURL`
            // changes (text edits, attachments toggling, user dismissal).
            // SwiftUI auto-cancels the previous task — `Task.sleep` throws
            // CancellationError, which we treat as "newer URL took over".
            .task(id: detectedURL) {
                guard let url = detectedURL else {
                    linkState = .idle
                    return
                }
                // Debounce so we don't fetch on every keystroke. If the
                // user keeps typing within 600ms, the task is cancelled
                // and we never reach the resolver.
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                guard let resolver else {
                    // No resolver injected (previews / tests). Surface
                    // nothing — URL still becomes a clickable facet
                    // server-side via ATFacetParser.
                    linkState = .idle
                    return
                }
                linkState = .loading(url)
                do {
                    let card = try await resolver.resolve(url: url)
                    guard !Task.isCancelled else { return }
                    linkState = .loaded(card)
                } catch {
                    guard !Task.isCancelled else { return }
                    linkState = .failed(url, reason: "Couldn't load preview.")
                }
            }
            // Phase E hand-off: when a template is applied from the Templates
            // tab, ingest its body + hashtags wholesale (architecture §6.1 +
            // Phase E plan decision: REPLACE, not append — template
            // application is an explicit user-driven action; carrying
            // half-typed prose into the merge is worse UX than starting
            // fresh).
            //
            // `initial: true` covers the lazy-tab-init case: when an apply
            // from the Templates tab (row tap) is the same event that
            // materializes ComposeView (TabView with `selection:` binding
            // lazy-instantiates the non-selected tab child), the inserted
            // view captures the already-changed tick as its baseline and a
            // vanilla `.onChange` never fires. `initial: true` runs the
            // closure on first attachment with the current value, so the
            // FIRST apply ingests correctly. The guard handles "no pending
            // at appearance". Less relevant post-G1 (Compose is the default
            // tab), but still load-bearing for cold-launch-on-Templates-tab
            // flows and for in-Compose picker selections that race
            // ComposeView's first body evaluation.
            // consume() below re-triggers this (pending: n → nil); guard short-circuits.
            .onChange(of: applier?.pending?.tick, initial: true) { _, newTick in
                guard let newTick,
                      let pending = applier?.pending,
                      pending.tick == newTick
                else { return }
                text = ComposeText.applyTemplate(body: pending.body, hashtags: pending.hashtags)
                attachments = []
                linkState = .idle
                dismissedURLs.removeAll()
                send = .idle
                applier?.consume()
                editorFocused = true
            }
            #if canImport(PhotosUI)
            // PhotosPickerItems land here async; the picker itself can't host
            // an async loader. We move loaded items into the typed
            // `ComposeAttachment` list and immediately clear `pickerSelection`
            // so the picker is ready for the next add (also stops the loader
            // from re-firing on the same items if state diff'd weirdly).
            .onChange(of: pickerSelection) { _, newItems in
                // Our removeAll() reset re-fires .onChange with an empty array; ignore the round-trip.
                guard !newItems.isEmpty else { return }
                attachmentError = nil
                Task {
                    await ingest(items: newItems)
                    pickerSelection.removeAll()
                }
            }
            #endif
            #if os(iOS)
            .sheet(isPresented: $cameraPresented) {
                CameraCaptureView { data, width, height in
                    ingestCameraCapture(data: data, pixelWidth: width, pixelHeight: height)
                }
            }
            #endif
        }
    }

    // MARK: - Send button

    // Extracted so the `#if canImport(Pow)` branch wraps a single expression
    // instead of repeating the surrounding Section + result-section plumbing.
    @ViewBuilder
    private var sendButton: some View {
        let button = Button(action: submit) {
            HStack {
                if isSending { ProgressView() }
                Text(sendButtonTitle).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSend)

        #if canImport(Pow)
        // Reduce-motion gate (architecture §9.2): the spray is a delight
        // flourish — for users who opted out of motion, the haptic stays
        // off too because the visual+haptic pairing is a unit.
        // Pow's haptic API is iOS-only; spray itself is cross-platform.
        #if os(iOS)
        button
            .changeEffect(
                .spray(origin: .center) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                },
                value: sendSuccessTick,
                isEnabled: !reduceMotion
            )
            .changeEffect(
                .feedback(hapticNotification: .success),
                value: sendSuccessTick,
                isEnabled: !reduceMotion
            )
        #else
        button
            .changeEffect(
                .spray(origin: .center) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                },
                value: sendSuccessTick,
                isEnabled: !reduceMotion
            )
        #endif
        #else
        button
        #endif
    }

    // MARK: - Link section

    @ViewBuilder
    private var linkSectionContent: some View {
        switch linkState {
        case .idle:
            // Unreachable: the call site already guards `if case .idle`
            // around the surrounding Section. Kept for exhaustiveness.
            EmptyView()
        case .loading(let url):
            // Escape hatch: if the resolver hangs (slow network, pre-timeout),
            // the user can dismiss. The button inserts the URL into
            // `dismissedURLs`, which `detectedURL` checks — that makes
            // `detectedURL` return nil, re-keys `.task(id: detectedURL)`,
            // and SwiftUI cancels the in-flight resolver task implicitly.
            HStack {
                ProgressView()
                Text(url.host ?? "Loading preview…")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Spacer()
                Button("Remove") {
                    dismissedURLs.insert(url)
                    linkState = .idle
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove link preview")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading link preview for \(url.host ?? url.absoluteString)")
            .accessibilityAddTraits(.updatesFrequently)
        case .loaded(let card):
            LinkCardRow(card: card, onRemove: {
                dismissedURLs.insert(card.url)
                linkState = .idle
            })
        case .failed(let url, let reason):
            HStack {
                Label(reason, systemImage: "link.badge.minus")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove") {
                    dismissedURLs.insert(url)
                    linkState = .idle
                }
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
            // Mantis hero treatment: 5-stop gradient WelcomeHero spans the
            // row edge-to-edge (matches LoginView H2: clear row background +
            // zero insets). Copy-URI contextMenu preserved. Accessibility
            // label is composed manually instead of relying on WelcomeHero's
            // default so VoiceOver also surfaces the hold-to-copy
            // affordance. The 2-second auto-clear in `.task(id: send)`
            // wipes this back to .idle after the user gets to see the
            // celebration.
            Section {
                WelcomeHero(
                    "Posted!",
                    subtitle: uri
                )
                .contextMenu {
                    Button {
                        copy(uri)
                    } label: {
                        Label("Copy URI", systemImage: "doc.on.doc")
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityLabel("Posted to Bluesky. URI \(uri). Tap and hold to copy.")
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandColor.error)
            }
        }
    }

    // MARK: - Derived state

    /// The URL currently eligible for an auto-attached link card, or nil.
    /// Drives `.task(id: detectedURL)` — SwiftUI re-keys the task whenever
    /// this changes, which gets us free debounce/cancel semantics.
    ///
    /// Filters NSDataDetector's broader catch (mailto:, tel:, file:) down
    /// to http/https — sending an `external` embed with a `mailto:` URL
    /// would card incorrectly. Suppresses URLs the user has dismissed via
    /// Remove, and honors Bluesky's exclusive embed slot: when images are
    /// attached, no card surfaces (the URL stays as a clickable facet).
    private var detectedURL: URL? {
        guard let url = URLDetector.firstURL(in: text) else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        guard !dismissedURLs.contains(url) else { return nil }
        guard attachments.isEmpty else { return nil }
        return url
    }

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

    // MARK: Template picker

    private func handlePickerSelection(_ option: TemplatePickerOption) {
        switch option {
        case .none:
            templatePickerSelection = nil
            resetDraft()
        case .template(let pid, _):
            templatePickerSelection = pid
            if let template = templates.first(where: { $0.persistentModelID == pid }) {
                applier?.apply(template)
                // applier.apply → SignedInView's .onChange flips tab if needed
                // (no-op when already on Compose) → ComposeView's own
                // .onChange(of: applier?.pending?.tick) ingests body/hashtags.
                // Nothing else to do here.
            }
        }
    }

    /// Resets the editor's local state to the same shape the auto-clear
    /// path uses after a successful post. Called when the user picks
    /// "None" from the template picker — explicit user intent to start
    /// blank.
    private func resetDraft() {
        text = ""
        attachments = []
        linkState = .idle
        dismissedURLs.removeAll()
        send = .idle
        #if canImport(PhotosUI)
        pickerSelection.removeAll()
        attachmentError = nil
        #endif
    }

    // MARK: Send

    // Named `submit()` rather than `send()` because the @State property is
    // also `send` — Swift's same-namespace rule for stored property vs
    // zero-arg method would collide. Matches LoginView's verb choice.
    private func submit() {
        guard let api else {
            // Preview / un-injected: don't crash, surface why nothing happened.
            send = .failed(message: "No account connected.")
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
        // Phase F: pass the loaded card through. APIClient enforces the
        // exclusive-embed-slot rule (images win) and falls through to the
        // external-only path when images is empty.
        let card: ExternalLinkCard? = if case .loaded(let c) = linkState { c } else { nil }
        dismissKeyboard()
        send = .sending
        Task {
            do {
                let uri = try await api.createPost(text: body, images: pack, external: card)
                // The await above already succeeded — record into the
                // in-memory session log before flipping to .sent so HomeView's
                // "Sent this session" list picks up the new entry. Optional
                // chaining keeps previews/tests crash-free when no log is
                // injected.
                sessionLog?.append(uri: uri, body: body)
                send = .sent(uri: uri)
            } catch {
                send = .failed(message: error.localizedDescription)
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
        attachmentError = nil   // a fresh ingest clears any prior banner
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

    #if os(iOS)
    @MainActor
    private func ingestCameraCapture(data: Data, pixelWidth: Int, pixelHeight: Int) {
        guard attachments.count < ComposeText.attachmentLimit else { return }
        attachments.append(ComposeAttachment(
            jpegData: data,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        ))
        attachmentError = nil
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
        #else
        // visionOS/watchOS/etc. — no clipboard surface today. Intentional no-op;
        // revisit if a new target ships.
        _ = string
        #endif
    }

    private func dismissKeyboard() {
        editorFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
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
                    Text("\(attachment.pixelWidth)×\(attachment.pixelHeight)px · \(attachment.jpegData.count.formatted(.byteCount(style: .file)))")
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

// MARK: - LinkCardRow

/// One row in the Link section: thumbnail + title/description/host +
/// remove button. Visual sibling of AttachmentRow — same 72pt
/// thumbnail, same trailing destructive button, same vertical padding.
/// File-private because it's tightly coupled to ComposeView's
/// `dismissedURLs` set via the `onRemove` callback.
private struct LinkCardRow: View {
    let card: ExternalLinkCard
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    Text(card.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(card.url.host ?? card.url.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            // Combine the preview elements into one VoiceOver focus so the
            // user doesn't have to swipe through title / description / host
            // serially. Scoped to the inner HStack so the destructive
            // Remove button below stays separately focusable.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Link preview: \(card.title)\(card.description.isEmpty ? "" : ". \(card.description)"). \(card.url.host ?? "")")
            Button(role: .destructive, action: onRemove) {
                Label("Remove link card", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if let data = card.thumbnailJPEG, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Rectangle().fill(.thinMaterial).overlay {
                Image(systemName: "link").foregroundStyle(.secondary)
            }
        }
        #else
        Rectangle().fill(.thinMaterial).overlay {
            Image(systemName: "link").foregroundStyle(.secondary)
        }
        #endif
    }
}

// MARK: - TemplatePickerLabel

/// Pinned picker row — renders as `Template: [Title ▾]` with a Menu
/// listing "None (blank)" + every saved template. Stateless: parent
/// owns `selection`, this view just renders + forwards taps.
private struct TemplatePickerLabel: View {
    let selection: PersistentIdentifier?
    let templates: [Template]
    let onSelect: (TemplatePickerOption) -> Void

    var body: some View {
        Menu {
            ForEach(TemplatePickerOption.options(from: templates)) { option in
                Button(option.menuTitle) { onSelect(option) }
            }
        } label: {
            HStack(spacing: 12) {
                LeadIcon(systemName: "doc.text", tint: BrandColor.tint)
                Text("Template")
                    .foregroundStyle(.primary)
                Spacer()
                Text(currentTitle)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("Template picker, currently \(currentTitle)")
    }

    private var currentTitle: String {
        guard let selection,
              let t = templates.first(where: { $0.persistentModelID == selection })
        else { return "None" }
        return t.title
    }
}

#Preview("Compose — idle") {
    ComposeView()
    // No apiClient injected — Send stays disabled via the api-nil guard.
}

#Preview("Compose — with templates") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Template.self, configurations: config)
    let context = ModelContext(container)
    context.insert(Template(title: "Daily standup", body: "What did you ship?", hashtags: ["work"]))
    context.insert(Template(title: "Hello bluesky", body: "Hi from the templates app.", hashtags: ["bsky"]))
    return ComposeView()
        .modelContainer(container)
}
