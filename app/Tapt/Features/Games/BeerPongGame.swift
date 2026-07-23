import SwiftUI
import SpriteKit

/// Cup Pong: a SpriteKit physics game. Slingshot the ball with
/// a live trajectory preview, real gravity, rim bounces and rattle-outs, splash
/// particles, streak multipliers, screen shake, haptics, and a persistent best
/// score. All game state and HUD live inside the scene (SKLabelNodes), so the
/// SwiftUI wrapper stays a thin shell and Swift 6 actor boundaries stay clean.
struct BeerPongGame: View {
    @State private var scene = PongScene()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: configured(size: proxy.size))
                .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle("Cup Pong")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptic.tap()
                    scene.restart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private func configured(size: CGSize) -> PongScene {
        if scene.size != size, size.width > 0 {
            scene.size = size
            scene.scaleMode = .resizeFill
        }
        return scene
    }
}

// MARK: - Scene

// @preconcurrency: the project uses MainActor default isolation while
// SKPhysicsContactDelegate is nonisolated. SpriteKit delivers contacts on the
// main thread, so this is dynamically safe (and runtime-checked).
final class PongScene: SKScene, @preconcurrency SKPhysicsContactDelegate {

    // Physics categories
    private enum Cat {
        static let ball: UInt32 = 1 << 0
        static let rim: UInt32 = 1 << 1
        static let floor: UInt32 = 1 << 2
        static let mouth: UInt32 = 1 << 3   // sensor inside the cup
        static let wall: UInt32 = 1 << 4
    }

    // Brand palette (SpriteKit-side)
    private let malt = SKColor(red: 0.10, green: 0.07, blue: 0.02, alpha: 1)
    private let maltDeep = SKColor(red: 0.05, green: 0.03, blue: 0.01, alpha: 1)
    private let gold = SKColor(red: 0.95, green: 0.66, blue: 0.00, alpha: 1)
    private let goldDeep = SKColor(red: 0.77, green: 0.42, blue: 0.06, alpha: 1)
    private let foam = SKColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1)
    private let hop = SKColor(red: 0.25, green: 0.56, blue: 0.36, alpha: 1)

    // State
    private var ball: SKShapeNode?
    private var cups: [SKNode] = []
    private var aimDots: [SKShapeNode] = []
    private var dragStart: CGPoint?
    private var ballInFlight = false
    private var ballSunkThisFlight = false
    private var score = 0
    private var streak = 0
    private var ballsLeft = 10
    private var roundOver = false
    private var best: Int {
        get { UserDefaults.standard.integer(forKey: "pongBestScore") }
        set { UserDefaults.standard.set(newValue, forKey: "pongBestScore") }
    }

    // HUD
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let streakLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let ballsLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let bestLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let banner = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let world = SKNode()

    override func didMove(to view: SKView) {
        backgroundColor = malt
        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self
        addChild(world)
        buildTable()
        buildHUD()
        restart()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, children.contains(world) else { return }
        world.removeAllChildren()
        buildTable()
        layoutHUD()
        rackUp()
        spawnBall()
    }

    // MARK: build

    private func buildTable() {
        // Side walls + a floor sensor a bit below the visible table edge.
        let bounds = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: -80, width: size.width, height: size.height + 160))
        bounds.categoryBitMask = Cat.wall
        bounds.restitution = 0.5
        world.physicsBody = bounds

        let floor = SKNode()
        floor.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: -40), to: CGPoint(x: size.width, y: -40))
        floor.physicsBody?.categoryBitMask = Cat.floor
        floor.physicsBody?.contactTestBitMask = Cat.ball
        world.addChild(floor)

        // Table glow behind the rack for depth.
        let glow = SKShapeNode(ellipseOf: CGSize(width: size.width * 0.9, height: size.height * 0.34))
        glow.position = CGPoint(x: size.width / 2, y: size.height * 0.74)
        glow.fillColor = goldDeep.withAlphaComponent(0.08)
        glow.strokeColor = .clear
        glow.zPosition = -1
        world.addChild(glow)
    }

    private func buildHUD() {
        for (label, sizePt) in [(scoreLabel, 30.0), (streakLabel, 15.0), (ballsLabel, 15.0), (bestLabel, 13.0), (banner, 24.0)] {
            label.fontSize = sizePt
            label.fontColor = foam
            label.zPosition = 50
            addChild(label)
        }
        scoreLabel.fontColor = gold
        streakLabel.fontColor = hop
        bestLabel.fontColor = foam.withAlphaComponent(0.55)
        banner.isHidden = true
        layoutHUD()
    }

    private func layoutHUD() {
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - 64)
        streakLabel.position = CGPoint(x: size.width / 2, y: size.height - 86)
        ballsLabel.position = CGPoint(x: 56, y: size.height - 64)
        bestLabel.position = CGPoint(x: size.width - 64, y: size.height - 64)
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.5)
    }

    private func refreshHUD() {
        scoreLabel.text = "\(score)"
        streakLabel.text = streak >= 2 ? "STREAK x\(streak)" : ""
        ballsLabel.text = "BALLS \(ballsLeft)"
        bestLabel.text = "BEST \(max(best, score))"
    }

    // MARK: cups

    /// A brand pint cup: tapered gold body + foam lip, rim physics on both lips
    /// (so balls can rattle in and out) + a sunk sensor inside the mouth.
    private func makeCup(width: CGFloat) -> SKNode {
        let cup = SKNode()
        let h = width * 1.22
        let taper = width * 0.14

        let body = CGMutablePath()
        body.move(to: CGPoint(x: -width / 2, y: h / 2))
        body.addLine(to: CGPoint(x: width / 2, y: h / 2))
        body.addLine(to: CGPoint(x: width / 2 - taper, y: -h / 2))
        body.addLine(to: CGPoint(x: -width / 2 + taper, y: -h / 2))
        body.closeSubpath()
        let shape = SKShapeNode(path: body)
        shape.fillColor = gold
        shape.strokeColor = maltDeep
        shape.lineWidth = 3
        cup.addChild(shape)

        let lip = SKShapeNode(ellipseOf: CGSize(width: width * 1.02, height: width * 0.30))
        lip.position = CGPoint(x: 0, y: h / 2)
        lip.fillColor = foam
        lip.strokeColor = maltDeep
        lip.lineWidth = 3
        cup.addChild(lip)

        // Rim physics: one small static ball on each lip edge.
        for sx in [-1.0, 1.0] {
            let rim = SKNode()
            rim.position = CGPoint(x: CGFloat(sx) * width / 2, y: h / 2)
            rim.physicsBody = SKPhysicsBody(circleOfRadius: 3)
            rim.physicsBody?.isDynamic = false
            rim.physicsBody?.restitution = 0.6
            rim.physicsBody?.categoryBitMask = Cat.rim
            cup.addChild(rim)
        }

        // Sunk sensor: just below the mouth. Contact while falling = splash.
        let mouth = SKNode()
        mouth.position = CGPoint(x: 0, y: h / 2 - width * 0.30)
        mouth.physicsBody = SKPhysicsBody(circleOfRadius: width * 0.20)
        mouth.physicsBody?.isDynamic = false
        mouth.physicsBody?.categoryBitMask = Cat.mouth
        mouth.physicsBody?.contactTestBitMask = Cat.ball
        mouth.physicsBody?.collisionBitMask = 0
        mouth.name = "mouth"
        cup.addChild(mouth)
        return cup
    }

    private func rackUp() {
        cups.forEach { $0.removeFromParent() }
        cups = []
        let cupW: CGFloat = min(52, size.width * 0.13)
        let gap = cupW * 1.18
        let topY = size.height * 0.80
        // 3-2-1 triangle pointing at the shooter.
        let rows: [[CGFloat]] = [[-1, 0, 1], [-0.5, 0.5], [0]]
        for (r, xs) in rows.enumerated() {
            for x in xs {
                let cup = makeCup(width: cupW)
                cup.position = CGPoint(x: size.width / 2 + x * gap, y: topY - CGFloat(r) * cupW * 1.05)
                world.addChild(cup)
                cups.append(cup)
            }
        }
    }

    // MARK: ball + aiming

    private func spawnBall() {
        ball?.removeFromParent()
        let b = SKShapeNode(circleOfRadius: 11)
        b.fillColor = foam
        b.strokeColor = maltDeep.withAlphaComponent(0.35)
        b.lineWidth = 1.5
        b.position = CGPoint(x: size.width / 2, y: size.height * 0.14)
        b.physicsBody = SKPhysicsBody(circleOfRadius: 11)
        b.physicsBody?.isDynamic = false        // becomes dynamic on launch
        b.physicsBody?.restitution = 0.55
        b.physicsBody?.linearDamping = 0.25
        b.physicsBody?.categoryBitMask = Cat.ball
        b.physicsBody?.contactTestBitMask = Cat.mouth | Cat.floor
        b.physicsBody?.collisionBitMask = Cat.rim | Cat.wall
        world.addChild(b)
        ball = b
        ballInFlight = false
        ballSunkThisFlight = false
    }

    private func launchVelocity(from drag: CGVector) -> CGVector {
        // Slingshot: pull down-back, fly up-forward. Clamped so every shot is playable.
        let power: CGFloat = 7.4
        let vx = max(-620, min(620, -drag.dx * power))
        let vy = max(300, min(1450, -drag.dy * power))
        return CGVector(dx: vx, dy: vy)
    }

    private func showAim(from drag: CGVector) {
        clearAim()
        guard let ball else { return }
        let v = launchVelocity(from: drag)
        let g = physicsWorld.gravity
        // Sample the projectile arc: p = p0 + v t + 0.5 g t^2
        for i in 1...12 {
            let t = CGFloat(i) * 0.055
            let x = ball.position.x + v.dx * t
            let y = ball.position.y + v.dy * t + 0.5 * g.dy * 150 * t * t
            let dot = SKShapeNode(circleOfRadius: max(2, 5 - CGFloat(i) * 0.25))
            dot.position = CGPoint(x: x, y: y)
            dot.fillColor = gold.withAlphaComponent(0.9 - CGFloat(i) * 0.06)
            dot.strokeColor = .clear
            dot.zPosition = 5
            world.addChild(dot)
            aimDots.append(dot)
        }
    }

    private func clearAim() {
        aimDots.forEach { $0.removeFromParent() }
        aimDots = []
    }

    // MARK: touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        if roundOver { restart(); return }
        guard !ballInFlight else { return }
        dragStart = t.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = dragStart, !ballInFlight else { return }
        let p = t.location(in: self)
        showAim(from: CGVector(dx: p.x - start.x, dy: p.y - start.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = dragStart, let ball, !ballInFlight, !roundOver else { dragStart = nil; return }
        let p = t.location(in: self)
        let drag = CGVector(dx: p.x - start.x, dy: p.y - start.y)
        clearAim()
        dragStart = nil
        // Ignore taps; require a real pull.
        guard abs(drag.dy) > 18 || abs(drag.dx) > 18 else { return }
        ball.physicsBody?.isDynamic = true
        ball.physicsBody?.velocity = launchVelocity(from: drag)
        ball.physicsBody?.angularVelocity = -drag.dx * 0.08
        ballInFlight = true
        ballsLeft -= 1
        refreshHUD()
        Haptic.firm()
    }

    // MARK: contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let cats = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if cats == Cat.ball | Cat.mouth, !ballSunkThisFlight,
           let ballBody = (contact.bodyA.categoryBitMask == Cat.ball ? contact.bodyA : contact.bodyB) as SKPhysicsBody?,
           ballBody.velocity.dy < 0,
           let mouthNode = (contact.bodyA.categoryBitMask == Cat.mouth ? contact.bodyA.node : contact.bodyB.node),
           let cup = mouthNode.parent {
            ballSunkThisFlight = true
            sink(cup: cup)
        }

        if cats == Cat.ball | Cat.floor, ballInFlight {
            missed()
        }
    }

    private func sink(cup: SKNode) {
        streak += 1
        score += 100 * streak
        Haptic.success()
        splash(at: cup.position)
        shake()

        cup.run(.sequence([
            .group([.scale(to: 0.1, duration: 0.22), .fadeOut(withDuration: 0.22)]),
            .removeFromParent()
        ]))
        cups.removeAll { $0 === cup }
        ball?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        ballInFlight = false

        if cups.isEmpty {
            score += 500
            ballsLeft += 4
            floatText("RACK CLEARED  +500", color: gold)
            Haptic.celebrate()
            run(.sequence([.wait(forDuration: 0.7), .run { [weak self] in self?.rackUp() }]))
        } else if streak >= 2 {
            floatText("SPLASH  x\(streak)", color: hop)
        } else {
            floatText("SPLASH  +100", color: gold)
        }
        refreshHUD()
        nextBallOrEnd(delay: 0.6)
    }

    private func missed() {
        guard ballInFlight else { return }
        ballInFlight = false
        if streak >= 2 { floatText("STREAK LOST", color: foam.withAlphaComponent(0.6)) }
        streak = 0
        Haptic.tap()
        ball?.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        refreshHUD()
        nextBallOrEnd(delay: 0.45)
    }

    private func nextBallOrEnd(delay: TimeInterval) {
        if ballsLeft <= 0 {
            run(.sequence([.wait(forDuration: delay), .run { [weak self] in self?.endRound() }]))
        } else {
            run(.sequence([.wait(forDuration: delay), .run { [weak self] in self?.spawnBall() }]))
        }
    }

    private func endRound() {
        roundOver = true
        let newBest = score > best
        if newBest {
            best = score
            Haptic.celebrate()
            for _ in 0..<3 { splash(at: CGPoint(x: CGFloat.random(in: size.width * 0.2...size.width * 0.8), y: size.height * 0.6)) }
        }
        banner.text = newBest ? "NEW BEST \(score) · TAP TO PLAY" : "ROUND OVER \(score) · TAP TO PLAY"
        banner.fontColor = newBest ? gold : foam
        banner.isHidden = false
        banner.setScale(0.6)
        banner.run(.scale(to: 1, duration: 0.25))
        refreshHUD()
    }

    func restart() {
        roundOver = false
        banner.isHidden = true
        score = 0
        streak = 0
        ballsLeft = 10
        rackUp()
        spawnBall()
        refreshHUD()
    }

    // MARK: juice

    /// Gold droplet burst, hand-rolled so no particle asset files are needed.
    private func splash(at p: CGPoint) {
        for _ in 0..<14 {
            let d = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...4.5))
            d.fillColor = Bool.random() ? gold : foam
            d.strokeColor = .clear
            d.position = p
            d.zPosition = 20
            d.physicsBody = SKPhysicsBody(circleOfRadius: 2)
            d.physicsBody?.velocity = CGVector(dx: .random(in: -220...220), dy: .random(in: 120...420))
            d.physicsBody?.collisionBitMask = 0
            d.physicsBody?.categoryBitMask = 0
            world.addChild(d)
            d.run(.sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
    }

    private func shake() {
        let amount: CGFloat = 7
        world.run(.sequence([
            .moveBy(x: amount, y: 0, duration: 0.035),
            .moveBy(x: -amount * 2, y: 0, duration: 0.05),
            .moveBy(x: amount, y: 0, duration: 0.035)
        ]))
    }

    private func floatText(_ text: String, color: SKColor) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 20
        label.fontColor = color
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        label.zPosition = 40
        label.setScale(0.5)
        addChild(label)
        label.run(.sequence([
            .group([.scale(to: 1.1, duration: 0.18), .moveBy(x: 0, y: 26, duration: 0.7), .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.3)])]),
            .removeFromParent()
        ]))
    }
}
