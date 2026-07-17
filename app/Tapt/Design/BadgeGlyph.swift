import SwiftUI

/// Custom, hand-drawn badge artwork. No emoji, no stock SF Symbols: every
/// achievement gets a unique Tapt-drawn vector glyph rendered in a `Canvas`,
/// so the passport medals feel like real, designed awards. Each glyph is drawn
/// in a normalized square and inked in a single contrast color (the tier disc
/// underneath carries the color), with a lighter accent for depth.
struct BadgeGlyph: View {
    let badge: Badge
    /// Main "ink" color drawn on top of the medal disc.
    var ink: Color = Brand.malt
    /// A softer accent used for fills/highlights.
    var accent: Color = Brand.malt.opacity(0.35)

    private var kind: GlyphKind { GlyphKind(for: badge) }

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let o = CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2)
            kind.draw(&ctx, s: s, origin: o, ink: ink, accent: accent)
        }
        .accessibilityHidden(true)
    }
}

/// Which drawing to use for a badge, resolved from its metric plus a few
/// special-cased milestone ids (the legend crown, the spectrum rainbow, etc.).
enum GlyphKind {
    case pintFilling      // first pour
    case pintTiered       // collection ladder
    case crown            // legend / master
    case flight           // styles
    case rainbow          // full spectrum
    case hopCone          // hoppy
    case moon             // dark
    case wheat            // wheat
    case lemon            // sour
    case chalice          // belgian
    case snowflake        // crisp
    case zeroDrop         // no / low
    case globePin         // countries
    case compass          // continents
    case pennant          // states
    case kettle           // breweries
    case seasonWheel      // seasons

    init(for badge: Badge) {
        switch badge.id {
        case "legend", "stylemaster": self = .crown; return
        case "spectrum": self = .rainbow; return
        case "first": self = .pintFilling; return
        default: break
        }
        switch badge.metric {
        case .pours:         self = .pintFilling
        case .beers:         self = .pintTiered
        case .styles:        self = .flight
        case .styleFamilies: self = .rainbow
        case .hoppy:         self = .hopCone
        case .dark:          self = .moon
        case .wheat:         self = .wheat
        case .sour:          self = .lemon
        case .belgian:       self = .chalice
        case .crisp:         self = .snowflake
        case .noLow:         self = .zeroDrop
        case .countries:     self = .globePin
        case .continents:    self = .compass
        case .states:        self = .pennant
        case .breweries:     self = .kettle
        case .seasons:       self = .seasonWheel
        }
    }

    func draw(_ ctx: inout GraphicsContext, s: CGFloat, origin o: CGPoint, ink: Color, accent: Color) {
        // Work in a 0...1 unit box, mapped into the square at `o` with side `s`.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        let lw = s * 0.055
        let stroke = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
        let inkStyle = GraphicsContext.Shading.color(ink)
        let accentStyle = GraphicsContext.Shading.color(accent)

        switch self {
        case .pintFilling, .pintTiered:
            // Shaker pint: wider mouth, tapered base, foam cap, partial fill.
            var glass = Path()
            glass.move(to: p(0.34, 0.30)); glass.addLine(to: p(0.40, 0.76))
            glass.addQuadCurve(to: p(0.44, 0.80), control: p(0.40, 0.80))
            glass.addLine(to: p(0.56, 0.80))
            glass.addQuadCurve(to: p(0.60, 0.76), control: p(0.60, 0.80))
            glass.addLine(to: p(0.66, 0.30))
            let fillLevel: CGFloat = self == .pintFilling ? 0.62 : 0.42
            var beer = Path()
            beer.move(to: p(0.355, fillLevel)); beer.addLine(to: p(0.40, 0.76))
            beer.addQuadCurve(to: p(0.44, 0.80), control: p(0.40, 0.80))
            beer.addLine(to: p(0.56, 0.80))
            beer.addQuadCurve(to: p(0.60, 0.76), control: p(0.60, 0.80))
            beer.addLine(to: p(0.645, fillLevel)); beer.closeSubpath()
            ctx.fill(beer, with: accentStyle)
            ctx.stroke(glass, with: inkStyle, style: stroke)
            // Foam cap.
            var foam = Path()
            foam.addRoundedRect(in: CGRect(x: o.x + 0.33 * s, y: o.y + 0.22 * s, width: 0.34 * s, height: 0.10 * s),
                                cornerSize: CGSize(width: 0.05 * s, height: 0.05 * s))
            ctx.fill(foam, with: inkStyle)
            // Rising bubble (only on the first pour, to feel alive).
            if self == .pintFilling {
                ctx.fill(Path(ellipseIn: CGRect(x: o.x + 0.485 * s, y: o.y + 0.50 * s, width: 0.05 * s, height: 0.05 * s)),
                         with: inkStyle)
            }

        case .crown:
            var c = Path()
            c.move(to: p(0.24, 0.68)); c.addLine(to: p(0.20, 0.34))
            c.addLine(to: p(0.34, 0.48)); c.addLine(to: p(0.50, 0.28))
            c.addLine(to: p(0.66, 0.48)); c.addLine(to: p(0.80, 0.34))
            c.addLine(to: p(0.76, 0.68)); c.closeSubpath()
            ctx.fill(c, with: accentStyle)
            ctx.stroke(c, with: inkStyle, style: stroke)
            var base = Path(); base.addRoundedRect(
                in: CGRect(x: o.x + 0.24 * s, y: o.y + 0.70 * s, width: 0.52 * s, height: 0.08 * s),
                cornerSize: CGSize(width: 0.03 * s, height: 0.03 * s))
            ctx.fill(base, with: inkStyle)
            for gx: CGFloat in [0.20, 0.50, 0.80] {
                ctx.fill(Path(ellipseIn: CGRect(x: o.x + (gx - 0.035) * s, y: o.y + 0.25 * s, width: 0.07 * s, height: 0.07 * s)), with: inkStyle)
            }

        case .flight:
            // Three tasting glasses in a row.
            for (i, cx) in [CGFloat(0.26), 0.50, 0.74].enumerated() {
                var g = Path()
                g.move(to: p(cx - 0.09, 0.34)); g.addLine(to: p(cx - 0.055, 0.72))
                g.addQuadCurve(to: p(cx, 0.76), control: p(cx - 0.055, 0.76))
                g.addQuadCurve(to: p(cx + 0.055, 0.72), control: p(cx + 0.055, 0.76))
                g.addLine(to: p(cx + 0.09, 0.34))
                let lvl: CGFloat = [0.46, 0.52, 0.58][i]
                var fill = Path()
                fill.move(to: p(cx - 0.075, lvl)); fill.addLine(to: p(cx - 0.055, 0.72))
                fill.addQuadCurve(to: p(cx, 0.76), control: p(cx - 0.055, 0.76))
                fill.addQuadCurve(to: p(cx + 0.055, 0.72), control: p(cx + 0.055, 0.76))
                fill.addLine(to: p(cx + 0.075, lvl)); fill.closeSubpath()
                ctx.fill(fill, with: accentStyle)
                ctx.stroke(g, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round, lineJoin: .round))
            }

        case .rainbow:
            // Fanned arcs = the spectrum of styles explored.
            for (i, r) in [CGFloat(0.34), 0.26, 0.18].enumerated() {
                var arc = Path()
                arc.addArc(center: p(0.5, 0.66), radius: r * s,
                           startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                ctx.stroke(arc, with: i == 1 ? accentStyle : inkStyle,
                           style: StrokeStyle(lineWidth: lw * 1.05, lineCap: .round))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: o.x + 0.47 * s, y: o.y + 0.63 * s, width: 0.06 * s, height: 0.06 * s)), with: inkStyle)

        case .hopCone:
            // Overlapping bracts forming a hop cone, with a little stem.
            var stem = Path(); stem.move(to: p(0.5, 0.20)); stem.addLine(to: p(0.5, 0.30))
            ctx.stroke(stem, with: inkStyle, style: stroke)
            var cone = Path()
            cone.move(to: p(0.5, 0.28))
            cone.addQuadCurve(to: p(0.30, 0.52), control: p(0.28, 0.34))
            cone.addQuadCurve(to: p(0.5, 0.80), control: p(0.34, 0.74))
            cone.addQuadCurve(to: p(0.70, 0.52), control: p(0.66, 0.74))
            cone.addQuadCurve(to: p(0.5, 0.28), control: p(0.72, 0.34))
            ctx.fill(cone, with: accentStyle)
            ctx.stroke(cone, with: inkStyle, style: stroke)
            // Bract veins.
            for y: CGFloat in [0.42, 0.54, 0.66] {
                var v = Path(); v.move(to: p(0.5, y - 0.02)); v.addLine(to: p(0.5, y + 0.06))
                var l = Path(); l.move(to: p(0.5, y)); l.addLine(to: p(0.5 - 0.13, y + 0.05))
                var r = Path(); r.move(to: p(0.5, y)); r.addLine(to: p(0.5 + 0.13, y + 0.05))
                for pth in [v, l, r] { ctx.stroke(pth, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round)) }
            }

        case .moon:
            // Crescent + two stars.
            var outer = Path(ellipseIn: CGRect(x: o.x + 0.30 * s, y: o.y + 0.28 * s, width: 0.40 * s, height: 0.40 * s))
            outer.addEllipse(in: CGRect(x: o.x + 0.42 * s, y: o.y + 0.24 * s, width: 0.36 * s, height: 0.36 * s))
            ctx.fill(outer, with: inkStyle, style: FillStyle(eoFill: true))
            star(&ctx, center: p(0.72, 0.34), r: 0.05 * s, ink: ink)
            star(&ctx, center: p(0.66, 0.54), r: 0.035 * s, ink: ink)

        case .wheat:
            // Central stalk + paired grain heads.
            var stalk = Path(); stalk.move(to: p(0.5, 0.82)); stalk.addLine(to: p(0.5, 0.30))
            ctx.stroke(stalk, with: inkStyle, style: stroke)
            for y: CGFloat in [0.34, 0.44, 0.54, 0.64] {
                for dir: CGFloat in [-1, 1] {
                    var grain = Path()
                    grain.move(to: p(0.5, y + 0.02))
                    grain.addQuadCurve(to: p(0.5 + dir * 0.17, y - 0.04), control: p(0.5 + dir * 0.11, y + 0.04))
                    grain.addQuadCurve(to: p(0.5, y - 0.02), control: p(0.5 + dir * 0.11, y - 0.08))
                    ctx.fill(grain, with: dir < 0 ? accentStyle : inkStyle)
                    ctx.stroke(grain, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.6, lineJoin: .round))
                }
            }

        case .lemon:
            // A half-lemon wedge: rind arc + inner segments.
            var wedge = Path()
            wedge.move(to: p(0.5, 0.72))
            wedge.addArc(center: p(0.5, 0.72), radius: 0.30 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            wedge.closeSubpath()
            ctx.fill(wedge, with: accentStyle)
            ctx.stroke(wedge, with: inkStyle, style: stroke)
            for a in stride(from: 200.0, through: 340.0, by: 35.0) {
                var seg = Path(); seg.move(to: p(0.5, 0.72))
                let rad = CGFloat(a) * .pi / 180
                seg.addLine(to: CGPoint(x: o.x + (0.5 + cos(rad) * 0.26) * s, y: o.y + (0.72 + sin(rad) * 0.26) * s))
                ctx.stroke(seg, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.6, lineCap: .round))
            }

        case .chalice:
            // Belgian goblet: rounded bowl, stem, foot.
            var bowl = Path()
            bowl.move(to: p(0.34, 0.30))
            bowl.addQuadCurve(to: p(0.5, 0.60), control: p(0.34, 0.60))
            bowl.addQuadCurve(to: p(0.66, 0.30), control: p(0.66, 0.60))
            ctx.fill(bowl, with: accentStyle)
            ctx.stroke(bowl, with: inkStyle, style: stroke)
            var rim = Path(); rim.move(to: p(0.34, 0.30)); rim.addLine(to: p(0.66, 0.30))
            var stem = Path(); stem.move(to: p(0.5, 0.58)); stem.addLine(to: p(0.5, 0.74))
            var foot = Path(); foot.move(to: p(0.38, 0.78)); foot.addLine(to: p(0.62, 0.78))
            for pth in [rim, stem, foot] { ctx.stroke(pth, with: inkStyle, style: stroke) }

        case .snowflake:
            for a in stride(from: 0.0, to: 360.0, by: 60.0) {
                let rad = CGFloat(a) * .pi / 180
                let tip = CGPoint(x: o.x + (0.5 + cos(rad) * 0.30) * s, y: o.y + (0.5 + sin(rad) * 0.30) * s)
                var arm = Path(); arm.move(to: p(0.5, 0.5)); arm.addLine(to: tip)
                ctx.stroke(arm, with: inkStyle, style: stroke)
                let mid = CGPoint(x: o.x + (0.5 + cos(rad) * 0.20) * s, y: o.y + (0.5 + sin(rad) * 0.20) * s)
                for da in [-40.0, 40.0] {
                    let r2 = CGFloat(a + da) * .pi / 180
                    var br = Path(); br.move(to: mid)
                    br.addLine(to: CGPoint(x: mid.x + cos(r2) * 0.09 * s, y: mid.y + sin(r2) * 0.09 * s))
                    ctx.stroke(br, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round))
                }
            }

        case .zeroDrop:
            // A droplet with a hollow "0" = a clean, zero-proof choice.
            var drop = Path()
            drop.move(to: p(0.5, 0.24))
            drop.addQuadCurve(to: p(0.70, 0.62), control: p(0.74, 0.44))
            drop.addArc(center: p(0.5, 0.62), radius: 0.20 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            drop.addQuadCurve(to: p(0.5, 0.24), control: p(0.26, 0.44))
            ctx.fill(drop, with: accentStyle)
            ctx.stroke(drop, with: inkStyle, style: stroke)
            ctx.stroke(Path(ellipseIn: CGRect(x: o.x + 0.42 * s, y: o.y + 0.52 * s, width: 0.16 * s, height: 0.20 * s)),
                       with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.9))

        case .globePin:
            let g = CGRect(x: o.x + 0.26 * s, y: o.y + 0.26 * s, width: 0.40 * s, height: 0.40 * s)
            ctx.stroke(Path(ellipseIn: g), with: inkStyle, style: stroke)
            var meridian = Path(); meridian.addEllipse(in: CGRect(x: g.midX - 0.09 * s, y: g.minY, width: 0.18 * s, height: g.height))
            var equator = Path(); equator.move(to: CGPoint(x: g.minX, y: g.midY)); equator.addLine(to: CGPoint(x: g.maxX, y: g.midY))
            for pth in [meridian, equator] { ctx.stroke(pth, with: accentStyle, style: StrokeStyle(lineWidth: lw * 0.7)) }
            // Map pin, top-right.
            var pin = Path()
            pin.addArc(center: p(0.70, 0.40), radius: 0.10 * s, startAngle: .degrees(150), endAngle: .degrees(30), clockwise: false)
            pin.addLine(to: p(0.70, 0.66)); pin.closeSubpath()
            ctx.fill(pin, with: inkStyle)
            ctx.fill(Path(ellipseIn: CGRect(x: o.x + 0.665 * s, y: o.y + 0.355 * s, width: 0.07 * s, height: 0.07 * s)),
                     with: GraphicsContext.Shading.color(accent.opacity(1)))

        case .compass:
            ctx.stroke(Path(ellipseIn: CGRect(x: o.x + 0.24 * s, y: o.y + 0.24 * s, width: 0.52 * s, height: 0.52 * s)),
                       with: inkStyle, style: stroke)
            var needle = Path()
            needle.move(to: p(0.5, 0.28)); needle.addLine(to: p(0.58, 0.5))
            needle.addLine(to: p(0.5, 0.72)); needle.addLine(to: p(0.42, 0.5)); needle.closeSubpath()
            ctx.fill(needle, with: accentStyle)
            ctx.stroke(needle, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.8, lineJoin: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: o.x + 0.475 * s, y: o.y + 0.475 * s, width: 0.05 * s, height: 0.05 * s)), with: inkStyle)

        case .pennant:
            var pole = Path(); pole.move(to: p(0.32, 0.24)); pole.addLine(to: p(0.32, 0.80))
            ctx.stroke(pole, with: inkStyle, style: stroke)
            var flag = Path()
            flag.move(to: p(0.32, 0.28)); flag.addLine(to: p(0.74, 0.36))
            flag.addLine(to: p(0.58, 0.46)); flag.addLine(to: p(0.74, 0.56))
            flag.addLine(to: p(0.32, 0.50)); flag.closeSubpath()
            ctx.fill(flag, with: accentStyle)
            ctx.stroke(flag, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.8, lineJoin: .round))

        case .kettle:
            // Brew kettle: a tank with a domed lid and a spout.
            var tank = Path()
            tank.addRoundedRect(in: CGRect(x: o.x + 0.32 * s, y: o.y + 0.38 * s, width: 0.36 * s, height: 0.34 * s),
                                cornerSize: CGSize(width: 0.06 * s, height: 0.06 * s))
            ctx.fill(tank, with: accentStyle)
            ctx.stroke(tank, with: inkStyle, style: stroke)
            var lid = Path()
            lid.move(to: p(0.34, 0.38))
            lid.addQuadCurve(to: p(0.66, 0.38), control: p(0.5, 0.24))
            ctx.stroke(lid, with: inkStyle, style: stroke)
            var knob = Path(); knob.move(to: p(0.5, 0.30)); knob.addLine(to: p(0.5, 0.24))
            var spout = Path(); spout.move(to: p(0.68, 0.52)); spout.addLine(to: p(0.78, 0.56)); spout.addLine(to: p(0.78, 0.62))
            for pth in [knob, spout] { ctx.stroke(pth, with: inkStyle, style: stroke) }

        case .seasonWheel:
            // Quadrant wheel: sun ray + leaf + snow dot + sprout, around a hub.
            ctx.stroke(Path(ellipseIn: CGRect(x: o.x + 0.26 * s, y: o.y + 0.26 * s, width: 0.48 * s, height: 0.48 * s)),
                       with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.8))
            // sun (top)
            for a in stride(from: -110.0, through: -70.0, by: 20.0) {
                let r = CGFloat(a) * .pi / 180
                var ray = Path()
                ray.move(to: CGPoint(x: o.x + (0.5 + cos(r) * 0.14) * s, y: o.y + (0.5 + sin(r) * 0.14) * s))
                ray.addLine(to: CGPoint(x: o.x + (0.5 + cos(r) * 0.20) * s, y: o.y + (0.5 + sin(r) * 0.20) * s))
                ctx.stroke(ray, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round))
            }
            // leaf (right)
            var leaf = Path()
            leaf.move(to: p(0.62, 0.5))
            leaf.addQuadCurve(to: p(0.78, 0.5), control: p(0.70, 0.42))
            leaf.addQuadCurve(to: p(0.62, 0.5), control: p(0.70, 0.58))
            ctx.fill(leaf, with: accentStyle); ctx.stroke(leaf, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.7))
            // snow (bottom)
            star(&ctx, center: p(0.5, 0.72), r: 0.05 * s, ink: ink)
            // sprout (left)
            var sprout = Path(); sprout.move(to: p(0.30, 0.56)); sprout.addLine(to: p(0.34, 0.46))
            ctx.stroke(sprout, with: inkStyle, style: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: o.x + 0.47 * s, y: o.y + 0.47 * s, width: 0.06 * s, height: 0.06 * s)), with: inkStyle)
        }
    }

    private func star(_ ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, ink: Color) {
        var path = Path()
        for i in 0..<10 {
            let radius = i % 2 == 0 ? r : r * 0.45
            let a = CGFloat(i) * .pi / 5 - .pi / 2
            let pt = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(ink))
    }
}
