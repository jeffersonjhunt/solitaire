import SolitaireEngine
import SwiftUI

/// The win animation the player chose (spec "Win animations"): Cascade (the default), Rainfall,
/// Decay or Shuffle; Random picks one of those four per game; None plays nothing. Reduce Motion
/// always means none.
enum WinAnimation: String, CaseIterable, Identifiable, Sendable {
    case cascade, rainfall, decay, shuffle, random, none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cascade: "Cascade"
        case .rainfall: "Rainfall"
        case .decay: "Decay"
        case .shuffle: "Shuffle"
        case .random: "Random"
        case .none: "None"
        }
    }

    static let playable: [WinAnimation] = [.cascade, .rainfall, .decay, .shuffle]

    /// What plays for the game dealt from `seed`: nil for None; Random settles on one of the four,
    /// the same one for that game every time it is asked.
    func resolved(seed: UInt64) -> WinAnimation? {
        switch self {
        case .none: nil
        case .random: Self.playable[Int(seed % UInt64(Self.playable.count))]
        default: self
        }
    }
}

extension EnvironmentValues {
    /// The win animation for the game on the board, already resolved (nil: none plays).
    @Entry var winAnimation: WinAnimation? = .cascade
}

/// Draws the chosen animation over the board once the game is won; `onFinished` fires when it
/// ends (the win card waits for it) or at once on a tap.
struct WinAnimationView: View {
    let kind: WinAnimation
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void

    var body: some View {
        switch kind {
        case .rainfall: WinRainfall(foundations: foundations, layout: layout, onFinished: onFinished)
        case .decay: WinDecay(foundations: foundations, layout: layout, onFinished: onFinished)
        case .shuffle: WinShuffle(foundations: foundations, layout: layout, onFinished: onFinished)
        default: WinCascade(foundations: foundations, layout: layout, onFinished: onFinished)
        }
    }
}

// MARK: - Timing (pure, so tests can check it)

/// Rainfall: kings first, round the four foundations, one card every 0.12 s drops from its pile
/// with a slight sway and a little spin, straight off the bottom.
enum RainfallTimeline {
    static let interval: TimeInterval = 0.12
    static let gravity: CGFloat = 1800

    /// Where launch number `index` is at `t` (seconds since the start): nil before it launches
    /// (it is still on its pile) and once it is below `bottom`.
    static func offset(index: Int, at t: TimeInterval, bottom: CGFloat) -> (dx: CGFloat, dy: CGFloat, angle: Double)? {
        let s = t - Double(index) * interval
        guard s >= 0 else { return nil }
        let dy = 0.5 * gravity * CGFloat(s * s)
        guard dy <= bottom else { return nil }
        let phase = Double(index) * 1.7
        return (14 * CGFloat(sin(s * 4 + phase)), dy, 10 * sin(s * 2.5 + phase))
    }

    static func launched(at t: TimeInterval, total: Int) -> Int {
        t < 0 ? 0 : min(total, Int(t / interval) + 1)
    }

    /// When the last card has fallen past `bottom`.
    static func duration(total: Int, bottom: CGFloat) -> TimeInterval {
        Double(max(total - 1, 0)) * interval + (2 * Double(bottom) / Double(gravity)).squareRoot()
    }
}

/// Decay: each pile dissolves from the top down — every card over 0.55 s, the next starting when
/// the one above is 60 % gone — the piles a quarter of a second apart.
enum DecayTimeline {
    static let cardDuration: TimeInterval = 0.55
    static let step: TimeInterval = 0.33
    static let pileStagger: TimeInterval = 0.25

    /// How far gone (0…1) the card `depth` from the top of pile `pile` is at `t`.
    static func progress(pile: Int, depth: Int, at t: TimeInterval) -> Double {
        let start = Double(pile) * pileStagger + Double(depth) * step
        return min(max((t - start) / cardDuration, 0), 1)
    }

    /// When the last card of the last pile is wholly gone (with a frame to spare, so rounding
    /// never ends it at 99.99 %).
    static func duration(deepest: Int) -> TimeInterval {
        3 * pileStagger + Double(max(deepest - 1, 0)) * step + cardDuration + 1.0 / 60
    }
}

/// Shuffle: the cards gather into two half-piles in the middle (0.9 s), riffle together into one
/// deck (1.2 s), turn face down (0.3 s) and slide onto the draw pile (0.6 s), where they stay.
enum ShuffleTimeline {
    static let gather: TimeInterval = 0.9
    static let riffle: TimeInterval = 1.2
    static let flip: TimeInterval = 0.3
    static let slide: TimeInterval = 0.6
    static var duration: TimeInterval { gather + riffle + flip + slide }

    static func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }

    /// Card number `i` of `total` (deck order after the riffle): its centre, and whether its face
    /// shows (the flip's first half) — given where it starts, the middle of the board, the draw
    /// pile and the card width.
    static func place(_ i: Int, of total: Int, at t: TimeInterval, from start: CGPoint,
                      middle: CGPoint, stock: CGPoint, cardWidth: CGFloat) -> (center: CGPoint, faceUp: Bool, squeeze: CGFloat) {
        let left = i % 2 == 0
        let half = CGPoint(x: middle.x + (left ? -0.85 : 0.85) * cardWidth, y: middle.y - CGFloat(i / 2) * 0.4)
        let stacked = CGPoint(x: middle.x, y: middle.y - CGFloat(i) * 0.4)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }
        if t < gather {
            let k = ease((t - Double(i) * 0.008) / (gather - 0.4))
            return (lerp(start, half, k), true, 1)
        }
        let r = t - gather
        if r < riffle {
            let hop = Double(i) / Double(max(total, 1)) * (riffle - 0.15)
            return (lerp(half, stacked, ease((r - hop) / 0.15)), true, 1)
        }
        let f = r - riffle
        if f < flip {
            let k = f / flip
            return (stacked, k < 0.5, CGFloat(abs(1 - 2 * k)))     // narrows to an edge, then the back widens
        }
        let k = ease((f - flip) / slide)
        let deck = CGPoint(x: stock.x, y: stock.y - CGFloat(i) * 0.25)
        return (lerp(stacked, deck, k), false, 1)
    }
}

// MARK: - The views

/// The shared frame for Rainfall, Decay and Shuffle: a timeline from the first frame, the card
/// images as Canvas symbols (`back` for face-down), finishing once, and a tap to skip.
private struct WinTimelineCanvas: View {
    let cards: [Card]
    let cardWidth: CGFloat
    let duration: TimeInterval
    let onFinished: () -> Void
    let draw: (inout GraphicsContext, CGSize, TimeInterval) -> Void
    @State private var clock = AnimationClock()
    @State private var finished = false

    static let backID = -1

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { timeline in
            Canvas { context, size in
                let t = clock.elapsed(at: timeline.date)
                draw(&context, size, t)
                if t >= duration && !finished {
                    Task { @MainActor in
                        finished = true
                        onFinished()
                    }
                }
            } symbols: {
                ForEach(cards) { card in
                    CardView(card: card, width: cardWidth).tag(card.id)
                }
                CardView(card: Card(suit: .spades, rank: 1, isFaceUp: false), width: cardWidth).tag(Self.backID)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinished() }
        .accessibilityHidden(true)
    }
}

/// The animation's own clock: started by the first frame it draws, like the cascade's simulation
/// (a reference type, so drawing can start it without a view update).
final class AnimationClock {
    private var start: Date?

    func elapsed(at date: Date) -> TimeInterval {
        if start == nil { start = date }
        return date.timeIntervalSince(start ?? date)
    }
}

private struct WinRainfall: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void

    var body: some View {
        let order = CascadeSimulation.launchOrder(foundations)
        let bottom = layout.metrics.size.height + layout.metrics.cardHeight
        WinTimelineCanvas(cards: order, cardWidth: layout.metrics.cardWidth,
                          duration: RainfallTimeline.duration(total: order.count, bottom: bottom),
                          onFinished: onFinished) { context, _, t in
            let launched = RainfallTimeline.launched(at: t, total: order.count)
            for (f, card) in CascadeSimulation.remainingTops(foundations, launched: launched).enumerated() {
                guard let card, let symbol = context.resolveSymbol(id: card.id) else { continue }
                let slot = layout.slot(.foundation(f))
                context.draw(symbol, at: CGPoint(x: slot.midX, y: slot.midY))
            }
            for (i, card) in order.enumerated() {
                guard let o = RainfallTimeline.offset(index: i, at: t, bottom: bottom),
                      let symbol = context.resolveSymbol(id: card.id),
                      let f = foundations.firstIndex(where: { $0.contains(card) }) else { continue }
                let slot = layout.slot(.foundation(f))
                var c = context
                c.translateBy(x: slot.midX + o.dx, y: slot.midY + o.dy)
                c.rotate(by: .degrees(o.angle))
                c.draw(symbol, at: .zero)
            }
        }
    }
}

private struct WinDecay: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var masks: DecayMasks?

    var body: some View {
        let deepest = foundations.map(\.count).max() ?? 0
        let width = layout.metrics.cardWidth, height = layout.metrics.cardHeight
        WinTimelineCanvas(cards: foundations.flatMap { $0 }, cardWidth: width,
                          duration: DecayTimeline.duration(deepest: deepest), onFinished: onFinished) { context, _, t in
            for (f, pile) in foundations.enumerated() {
                let slot = layout.slot(.foundation(f))
                let center = CGPoint(x: slot.midX, y: slot.midY)
                let rect = CGRect(x: slot.midX - width / 2, y: slot.midY - height / 2, width: width, height: height)
                // The card being eaten away and the one under it (which shows through the holes).
                let depths = (0..<pile.count).filter { DecayTimeline.progress(pile: f, depth: $0, at: t) < 1 }.prefix(2)
                for depth in depths.reversed() {
                    let card = pile[pile.count - 1 - depth]
                    guard let symbol = context.resolveSymbol(id: card.id) else { continue }
                    let p = DecayTimeline.progress(pile: f, depth: depth, at: t)
                    guard p > 0, let frame = masks?.frame(variant: card.id, progress: p) else {
                        context.draw(symbol, at: center)
                        continue
                    }
                    context.drawLayer { layer in
                        layer.draw(symbol, at: center)
                        layer.blendMode = .sourceAtop                 // the rim only over the card
                        layer.draw(Image(decorative: frame.rim, scale: frame.scale), in: rect)
                        layer.blendMode = .destinationIn              // then cut the holes
                        layer.draw(Image(decorative: frame.mask, scale: frame.scale), in: rect)
                    }
                }
            }
        }
        .task {
            let size = CGSize(width: width, height: height), scale = displayScale
            masks = await Task.detached(priority: .userInitiated) { DecayMasks(size: size, scale: scale) }.value
        }
    }
}

/// The dissolve for Decay, without a shader: a few fractal-noise fields made once at the card's
/// pixel size; each frame thresholds one into a mask (visible where the noise is above the rising
/// threshold) and a burnt-orange rim just ahead of the holes. Thresholds are taken in 48 steps
/// and cached.
final class DecayMasks: @unchecked Sendable {
    static let variants = 4
    static let steps = 48
    static let rim: Float = 0.07

    struct Frame { let mask: CGImage; let rim: CGImage; let scale: CGFloat }

    let scale: CGFloat
    private let width: Int, height: Int
    private let fields: [[Float]]
    private var cache: [Int: Frame] = [:]

    init(size: CGSize, scale: CGFloat) {
        self.scale = scale
        width = max(Int(size.width * scale), 1)
        height = max(Int(size.height * scale), 1)
        let cell = Float(size.width * scale) / 7
        fields = (0..<Self.variants).map { v in
            Self.field(width: max(Int(size.width * scale), 1), height: max(Int(size.height * scale), 1),
                       cell: cell, seed: Float(v) * 31.7)
        }
    }

    func frame(variant: Int, progress: Double) -> Frame? {
        let level = min(Int(progress * Double(Self.steps)), Self.steps)
        let key = (variant % Self.variants) * 1000 + level
        if let hit = cache[key] { return hit }
        let threshold = -Self.rim + (1 + Self.rim) * Float(level) / Float(Self.steps)
        let field = fields[variant % Self.variants]
        var mask = [UInt8](repeating: 0, count: width * height * 4)     // white, opaque where the card stays
        var rim = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let n = field[i]
            if n >= threshold { mask[i * 4] = 255; mask[i * 4 + 1] = 255; mask[i * 4 + 2] = 255; mask[i * 4 + 3] = 255 }
            if n >= threshold, n < threshold + Self.rim {
                let a = UInt8(255 * (1 - (n - threshold) / Self.rim))
                rim[i * 4] = UInt8(Float(a) * 0.8); rim[i * 4 + 1] = UInt8(Float(a) * 0.333); rim[i * 4 + 3] = a
            }
        }
        guard let m = Self.image(mask, width: width, height: height),
              let r = Self.image(rim, width: width, height: height) else { return nil }
        let frame = Frame(mask: m, rim: r, scale: scale)
        cache[key] = frame
        return frame
    }

    /// Premultiplied RGBA. (An alpha-only image would be smaller, but Core Graphics won't make one
    /// with a colour space, and drawing needs one.)
    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Fractal value noise, 0…1, four octaves.
    static func field(width: Int, height: Int, cell: Float, seed: Float) -> [Float] {
        func hash(_ x: Float, _ y: Float) -> Float {
            var px = (x * 123.34).truncatingRemainder(dividingBy: 1), py = (y * 456.21).truncatingRemainder(dividingBy: 1)
            let d = px * (px + 45.32) + py * (py + 45.32)
            px += d; py += d
            let v = (px * py).truncatingRemainder(dividingBy: 1)
            return v < 0 ? v + 1 : v
        }
        func noise(_ x: Float, _ y: Float) -> Float {
            let ix = x.rounded(.down), iy = y.rounded(.down), fx = x - ix, fy = y - iy
            let a = hash(ix, iy), b = hash(ix + 1, iy), c = hash(ix, iy + 1), d = hash(ix + 1, iy + 1)
            let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
            return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy
        }
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var px = Float(x) / cell + seed, py = Float(y) / cell + seed * 0.7
                var v: Float = 0, amplitude: Float = 0.5
                for _ in 0..<4 {
                    v += amplitude * noise(px, py)
                    px = px * 2.03 + 17; py = py * 2.03 + 17
                    amplitude *= 0.5
                }
                out[y * width + x] = v / 0.9375
            }
        }
        return out
    }
}

private struct WinShuffle: View {
    let foundations: [[Card]]
    let layout: BoardLayout
    let onFinished: () -> Void

    var body: some View {
        // Deck order after the riffle: the two halves interleaved.
        let deck = CascadeSimulation.launchOrder(foundations)
        let stockSlot = layout.slot(.stock)
        let width = layout.metrics.cardWidth
        WinTimelineCanvas(cards: deck, cardWidth: width, duration: ShuffleTimeline.duration,
                          onFinished: onFinished) { context, size, t in
            let middle = CGPoint(x: size.width / 2, y: size.height * 0.45)
            for (i, card) in deck.enumerated() {
                let f = foundations.firstIndex { $0.contains(card) } ?? 0
                let slot = layout.slot(.foundation(f))
                let place = ShuffleTimeline.place(i, of: deck.count, at: t, from: CGPoint(x: slot.midX, y: slot.midY),
                                                  middle: middle, stock: CGPoint(x: stockSlot.midX, y: stockSlot.midY),
                                                  cardWidth: width)
                guard let symbol = context.resolveSymbol(id: place.faceUp ? card.id : WinTimelineCanvas.backID) else { continue }
                var c = context
                c.translateBy(x: place.center.x, y: place.center.y)
                c.scaleBy(x: max(place.squeeze, 0.02), y: 1)
                c.draw(symbol, at: .zero)
            }
        }
    }
}
