import Foundation
import Observation

/// Pending hand-off from the Templates module to whoever is listening
/// (in production: ComposeView). One-shot — the consumer calls `consume()`
/// after ingesting `pending` to clear the slot.
///
/// `tick` is monotonic across `apply(_:)` calls so `.onChange(of: pending?.tick)`
/// re-fires when the user applies the same template twice in a row. The counter
/// is preserved across `consume()` calls so consume+reapply still advances tick.
@MainActor
@Observable
public final class TemplateApplier {

    public struct Pending: Sendable, Equatable {
        public let body: String
        public let hashtags: [String]
        public let tick: Int

        public init(body: String, hashtags: [String], tick: Int) {
            self.body = body
            self.hashtags = hashtags
            self.tick = tick
        }
    }

    public private(set) var pending: Pending?

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
