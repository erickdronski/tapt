import SwiftUI

/// Connect 4, pass-and-play. Tap a column, the disc drops with gravity and a
/// bounce; four in a row wins with the line lit up.
struct ConnectFourGame: View {
    private let cols = 7, rows = 6
    @State private var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: 7), count: 6)
    @State private var turn = 1                     // 1 = copper, 2 = gold
    @State private var winner = 0
    @State private var winLine: [(Int, Int)] = []
    @State private var dropping = false
    @State private var moves = 0

    var body: some View {
        VStack(spacing: 18) {
            header

            GeometryReader { proxy in
                let cell = min(proxy.size.width / CGFloat(cols), proxy.size.height / CGFloat(rows))
                let boardW = cell * CGFloat(cols)
                let boardH = cell * CGFloat(rows)
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Brand.malt)
                        .frame(width: boardW + 12, height: boardH + 12)
                        .shadow(color: Brand.malt.opacity(0.35), radius: 16, y: 10)

                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach(0..<cols, id: \.self) { c in
                                    cellView(r: r, c: c)
                                        .frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let originX = (proxy.size.width - boardW) / 2
                    let col = Int((location.x - originX) / cell)
                    if col >= 0 && col < cols { drop(col) }
                }
            }
            .aspectRatio(CGFloat(cols) / CGFloat(rows), contentMode: .fit)
            .padding(.horizontal, 6)

            if winner > 0 || moves == rows * cols { resultPanel }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
        .navigationTitle("Connect 4")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cellView(r: Int, c: Int) -> some View {
        let value = grid[r][c]
        let isWin = winLine.contains { $0 == (r, c) }
        return ZStack {
            Circle()
                .fill(Brand.foam)
                .padding(4)
            if value > 0 {
                Circle()
                    .fill(value == 1 ? Brand.copper : Brand.gold)
                    .padding(6)
                    .overlay(
                        Circle()
                            .stroke(isWin ? Brand.foam : Brand.malt.opacity(0.25),
                                    lineWidth: isWin ? 4 : 2)
                            .padding(6)
                    )
                    .scaleEffect(isWin ? 1.06 : 1)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.42, dampingFraction: 0.62), value: value)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isWin)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ForEach([1, 2], id: \.self) { p in
                HStack(spacing: 8) {
                    Circle().fill(p == 1 ? Brand.copper : Brand.gold).frame(width: 18, height: 18)
                    Text(p == 1 ? "Copper" : "Gold")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(turn == p && winner == 0 ? Brand.malt : Brand.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    turn == p && winner == 0 ? (p == 1 ? Brand.copper.opacity(0.35) : Brand.gold.opacity(0.4)) : Brand.surface,
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
        }
    }

    private var resultPanel: some View {
        VStack(spacing: 10) {
            Text(winner == 0 ? "Board full. Draw! 🤝" : "🏆 \(winner == 1 ? "Copper" : "Gold") connects four!")
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
            Button("Rematch") {
                withAnimation { grid = Array(repeating: Array(repeating: 0, count: cols), count: rows) }
                turn = 1; winner = 0; winLine = []; moves = 0
            }
            .font(.system(.headline, design: .rounded))
            .padding(.horizontal, 26).padding(.vertical, 12)
            .background(Brand.gold, in: Capsule())
            .foregroundStyle(Brand.malt)
            .buttonStyle(.taptPress)
        }
    }

    private func drop(_ col: Int) {
        guard winner == 0, !dropping else { return }
        guard let row = (0..<rows).reversed().first(where: { grid[$0][col] == 0 }) else { return }
        dropping = true
        Haptic.tap()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
            grid[row][col] = turn
        }
        moves += 1
        if let line = winningLine(r: row, c: col) {
            winner = turn
            winLine = line
            Haptic.celebrate()
        } else {
            turn = 3 - turn
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dropping = false }
    }

    private func winningLine(r: Int, c: Int) -> [(Int, Int)]? {
        let player = grid[r][c]
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var line = [(r, c)]
            for sign in [1, -1] {
                var rr = r + dr * sign, cc = c + dc * sign
                while rr >= 0, rr < rows, cc >= 0, cc < cols, grid[rr][cc] == player {
                    line.append((rr, cc))
                    rr += dr * sign; cc += dc * sign
                }
            }
            if line.count >= 4 { return line }
        }
        return nil
    }
}
