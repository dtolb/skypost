import Foundation
import Observation

/// Pending hand-off from the Templates module to whoever is listening
/// (in production: ComposeView). One-shot — the consumer calls `consume()`
/// after ingesting `pending` to clear the slot.
///
/// `tick` is monotonic across the applier's lifetime (NOT reset by `consume()`)
/// so `.onChange(of: pending?.tick)` distinguishes successive applications of
/// the same template.
@MainActor
@Observable
public final class TemplateApplier {

    public struct Pending: Sendable, Equatable {
        public let body: String
        public let hashtags: [String]
        public let tick: Int

        // Synthesized memberwise inits are `internal` even when the type and
        // its stored properties are public — this explicit init is required
        // for cross-module construction (e.g. tests).
        public init(body: String, hashtags: [String], tick: Int) {
            self.body = body
            self.hashtags = hashtags
            self.tick = tick
        }
    }

    public private(set) var pending: Pending?

    // WHY: internal bookkeeping; consumers should observe `pending.tick`, not this counter.
    @ObservationIgnored private var lastTick: Int = 0

    public init() {}

    public func apply(_ template: Template) {
        lastTick += 1
        pending = Pending(
            body: template.body,
            hashtags: template.hashtags,
            tick: lastTick
        )
    }

    public func consume() {
        pending = nil
    }
}
