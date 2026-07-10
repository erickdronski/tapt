import SwiftUI

/// Beer Pong, GamePigeon style. Drag the ball back and flick, it arcs toward
/// the rack with real depth (scales down at the apex), lands on aim + power.
/// Pass-and-play: 2 players, each clears the other's 6-cup rack. Swipe physics.
struct BeerPongGame: View {
    @State private var racks: [[Bool]] = [Array(repeating: true, count: 6), Array(repeating: true, count: 6)]
    @State private var turn = 0
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var throwing = false
    @State private var throwProgress: Double = 0
    @State private var landing: CGPoint = .zero
    @State private var start: CGPoint = .zero
    @State private var message = ""
    @State private var splash: Int? = nil

    private var targetRack: Int { 1 - turn }
    private var cupsLeft: [Int] { racks.map { $0.filter { $0 }.count } }
    private var gameOver: Bool { cupsLeft.contains(0) }

    var body: some View {
        VStack(spacing: 14) {
            scoreboard

            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack {
                    // Target rack (opponent's cups)
                    rackView(rackIndex: targetRack, center: CGPoint(x: w/2, y: h*0.22), cup: 46)

                    // The ball
                    let apex = throwProgress < 0.5 ? throwProgress*2 : (1-throwProgress)*2
                    let pos = CGPoint(
                        x: start.x + (landing.x - start.x) * throwProgress,
                        y: start.y + (landing.y - start.y) * throwProgress - CGFloat(apex) * h * 0.22
                    )
                    Circle()
                        .fill(RadialGradient(colors: [.white, Color(hex: 0xE8E2D0)], center: .topLeading, startRadius: 2, endRadius: 26))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Brand.malt.opacity(0.2)))
                        .scaleEffect(throwing ? (0.55 + 0.45*(1-apex)) : (dragging ? 1.1 : 1))
                        .shadow(color: Brand.malt.opacity(0.3), radius: 3, y: 2)
                        .position(throwing ? pos : ballRest(w: w, h: h))
                        .offset(throwing ? .zero : drag)

                    if let splash {
                        Text("SPLASH!")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(Brand.gold)
                            .position(x: w/2, y: h*0.22)
                            .transition(.scale.combined(with: .opacity))
                            .id(splash)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            guard !throwing, !gameOver else { return }
                            dragging = true
                            drag = CGSize(width: v.translation.width*0.5, height: min(max(v.translation.height,-10),100)*0.6)
                            start = ballRest(w: w, h: h)
                        }
                        .onEnded { v in
                            dragging = false
                            guard !throwing, !gameOver else { drag = .zero; return }
                            throwBall(velocity: v.predictedEndTranslation, w: w, h: h)
                            drag = .zero
                        }
                )
            }
            .frame(height: 340)

            Text(gameOver ? "" : (dragging ? "Release to throw!" : "\(playerName(turn)): drag down, flick up at the cups"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(dragging ? Brand.copper : Brand.muted)
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(Brand.hop)
            }
            if gameOver { resultPanel }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
        .navigationTitle("Beer Pong")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ballRest(w: CGFloat, h: CGFloat) -> CGPoint { CGPoint(x: w/2, y: h*0.86) }

    private func rackView(rackIndex: Int, center: CGPoint, cup: CGFloat) -> some View {
        // 6-cup triangle: rows of 3, 2, 1
        let rows = [3, 2, 1]
        var idx = 0
        var cups: [(Int, CGPoint)] = []
        for (r, count) in rows.enumerated() {
            let rowW = CGFloat(count) * cup
            for c in 0..<count {
                let x = center.x - rowW/2 + cup/2 + CGFloat(c)*cup
                let y = center.y + CGFloat(r)*cup*0.82
                cups.append((idx, CGPoint(x: x, y: y)))
                idx += 1
            }
        }
        return ForEach(cups, id: \.0) { i, p in
            Group {
                if racks[rackIndex][i] {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Brand.copper, Color(hex: 0x8D3D16)], startPoint: .top, endPoint: .bottom))
                        Circle().fill(Brand.malt.opacity(0.55)).padding(7)
                        Circle().fill(Brand.gold.opacity(0.85)).padding(9)
                    }
                    .frame(width: cup-6, height: cup-6)
                    .position(p)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private func throwBall(velocity: CGSize, w: CGFloat, h: CGFloat) {
        let power = max(-velocity.height, 60)
        guard power > 60 else { return }
        Haptic.firm()
        start = ballRest(w: w, h: h)

        // Aim from horizontal flick; accuracy decays with wild/over-hard flicks.
        let center = w/2
        let aimX = center + velocity.width*0.30
        let over = max(0, power - 520)*0.15
        let scatter = 14 + over + abs(velocity.width)*0.12
        let seed = CGFloat((turn*991 + Int(power)) % 200)/100 - 1
        let landX = min(max(aimX + seed*scatter, 20), w-20)
        let landY = h*0.22 + max(0, (420 - power))*0.10 + seed*scatter*0.5

        landing = CGPoint(x: landX, y: min(max(landY, h*0.12), h*0.42))
        throwing = true
        throwProgress = 0
        withAnimation(.easeOut(duration: 0.62)) { throwProgress = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            resolveHit(w: w, h: h)
        }
    }

    private func resolveHit(w: CGFloat, h: CGFloat) {
        // Nearest live cup to the landing point
        let rows = [3, 2, 1]; let cup: CGFloat = 46
        let center = CGPoint(x: w/2, y: h*0.22)
        var idx = 0; var best: (Int, CGFloat) = (-1, .greatestFiniteMagnitude)
        for (r, count) in rows.enumerated() {
            let rowW = CGFloat(count)*cup
            for c in 0..<count {
                let x = center.x - rowW/2 + cup/2 + CGFloat(c)*cup
                let y = center.y + CGFloat(r)*cup*0.82
                if racks[targetRack][idx] {
                    let d = hypot(landing.x - x, landing.y - y)
                    if d < best.1 { best = (idx, d) }
                }
                idx += 1
            }
        }
        let hit = best.0 >= 0 && best.1 < cup*0.5
        if hit {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { racks[targetRack][best.0] = false }
            splash = (splash ?? 0) + 1
            message = "\(playerName(turn)) sinks one!"
            Haptic.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { splash = nil }
        } else {
            message = "Miss, off the table."
        }
        throwing = false
        throwProgress = 0
        if gameOver { Haptic.celebrate() }
        else { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { turn = 1 - turn } }
    }

    private var scoreboard: some View {
        HStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { i in
                VStack(spacing: 2) {
                    Text(playerName(i)).font(.caption.weight(.bold))
                        .foregroundStyle(turn == i && !gameOver ? Brand.malt : Brand.muted)
                    Text("\(cupsLeft[1-i]) cups left")
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(turn == i && !gameOver ? Brand.malt : Brand.text)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(turn == i && !gameOver ? (i == 0 ? Brand.copper : Brand.gold) : Brand.surface,
                            in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var resultPanel: some View {
        VStack(spacing: 10) {
            Text("🏆 \(playerName(cupsLeft[1] == 0 ? 0 : 1)) clears the table!")
                .font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Button("Rematch") {
                racks = [Array(repeating: true, count: 6), Array(repeating: true, count: 6)]
                turn = 0; message = ""
            }
            .font(.system(.headline, design: .rounded))
            .padding(.horizontal, 26).padding(.vertical, 12)
            .background(Brand.gold, in: Capsule()).foregroundStyle(Brand.malt)
            .buttonStyle(.taptPress)
        }
    }

    private func playerName(_ i: Int) -> String { i == 0 ? "Player 1" : "Player 2" }
}
