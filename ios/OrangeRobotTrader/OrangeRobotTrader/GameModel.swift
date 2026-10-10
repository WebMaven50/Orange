import SwiftUI
import Observation
import OrangeRobotKit

/// Persistent sat balance shared across runs (the book's "sat wallet").
enum Wallet {
    private static let key = "tor_sats"
    static var sats: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@MainActor @Observable
final class GameModel {
    enum Phase { case intro, playing, ended }

    var phase: Phase = .intro
    var session: GameSession = .random()
    var timeframe = 15
    /// Indicators the player has switched on for this run (peek tools, off by default).
    var indicators: Set<IndicatorKind> = []
    var showIndicatorMenu = false
    /// Remembered between runs.
    var chartStyle: ChartStyle =
        ChartStyle(rawValue: UserDefaults.standard.string(forKey: "chart_style") ?? "") ?? .candles {
        didSet { UserDefaults.standard.set(chartStyle.rawValue, forKey: "chart_style") }
    }
    /// Every new run starts at Normal; the player's choice applies to the current run only.
    private(set) var speed: PlaybackSpeed = .normal
    var side: Side = .buy
    var orderType: OrderType = .market
    var fraction = 0.75
    var levelText = ""
    var flash: String?
    var totalSats = Wallet.sats
    var showInfo = false
    var showLeaderboard = false
    var showPrologue = false
    var showStartPicker = false
    var showOrderForm = false
    var showPositions = false
    var showNews = false

    // News
    private(set) var newsTracker = NewsTracker(startDay: 0)
    private(set) var banner: NewsItem?
    private var bannerQueue: [NewsItem] = []
    private var lastSeenNewsDay = 0
    /// Headlines that arrived since the News page was last opened.
    var unreadNews: Int { newsTracker.unread(after: lastSeenNewsDay, day: session.currentDayNumber) }
    /// What the player may read right now (never anything from later than the ticker).
    func visibleNews(limit: Int = 80) -> [NewsItem] {
        newsTracker.visible(day: session.currentDayNumber, limit: limit)
    }
    private var autoPaused = false

    // Leaderboard save state for the current run
    var savedInitials: String?
    var savedRank: Int?
    var isSaving = false
    var saveError: String?
    var lastInitials = UserDefaults.standard.string(forKey: "tor_initials") ?? ""
    private let leaderboard = LeaderboardClient()

    private var timer: Timer?
    private var lastTick = Date()
    private var banked = false

    /// Player setting (Info screen): small live price flickers. On by default.
    static var liveFlicker: Bool {
        UserDefaults.standard.object(forKey: "live_flicker") as? Bool ?? true
    }

    // MARK: Lifecycle

    /// True while any sheet is covering the game, so the market can wait.
    var anySheetOpen: Bool { showInfo || showLeaderboard || showPrologue || showStartPicker || showPositions || showNews }

    func startNewRun(_ choice: StartChoice = .random) {
        switch choice {
        case .random: session = .random(microMoves: Self.liveFlicker)
        case .moment(let d): session = .starting(at: d, microMoves: Self.liveFlicker)
        }
        speed = .normal
        session.speed = .normal
        indicators = []
        showIndicatorMenu = false
        autoPaused = false
        showOrderForm = false
        showPositions = false
        showNews = false
        banner = nil
        bannerQueue = []
        // Events dated on the start day itself still flash; earlier ones are only in the feed.
        newsTracker = NewsTracker(startDay: session.currentDayNumber)
        lastSeenNewsDay = session.currentDayNumber
        phase = .playing
        trackNews()
        side = .buy
        orderType = .market
        fraction = 0.75
        banked = false
        savedInitials = nil; savedRank = nil; saveError = nil; isSaving = false
        Activity.track(.gameStart)
        resetLevel()
        lastTick = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard phase == .playing else { return }
        session.advance(seconds: dt)
        trackNews()
        if session.outcome != nil { finish() }
    }

    // MARK: News

    private func trackNews() {
        let released = newsTracker.update(day: session.currentDayNumber, price: session.lastPrice)
        if !released.isEmpty {
            bannerQueue.append(contentsOf: released)
            if bannerQueue.count > 4 { bannerQueue.removeFirst(bannerQueue.count - 4) }
        }
        presentNextBanner()
    }

    private func presentNextBanner() {
        // Wait for the player to wake up from a sleep so the banner isn't missed.
        guard banner == nil, !session.isSleeping, !bannerQueue.isEmpty else { return }
        let item = bannerQueue.removeFirst()
        banner = item
        Haptics.notify(.warning)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5.5))
            guard let self, self.banner?.id == item.id else { return }
            self.banner = nil
        }
    }

    func dismissBanner() { banner = nil }

    func openNews() {
        banner = nil
        showNews = true
    }

    func markNewsSeen() { lastSeenNewsDay = session.currentDayNumber }

    private func finish() {
        timer?.invalidate()
        timer = nil
        showOrderForm = false
        showPositions = false
        showNews = false
        banner = nil
        phase = .ended
        Activity.track(.gameEnd)
        if session.outcome == .win { Activity.track(.gameWin) }
        // Practice runs (player-chosen dates) never bank sats.
        if !banked {
            banked = true
            if session.isRandomStart {
                Wallet.sats += session.satsEarned
                totalSats = Wallet.sats
            }
        }
        Haptics.notify(session.outcome == .bust ? .error : .success)
    }

    // MARK: Ticket

    var maxAmount: Double { session.maxAmount(for: side) }
    var amountUSD: Double { maxAmount * fraction }
    var needsLevel: Bool { orderType != .market }

    func toggleIndicator(_ k: IndicatorKind) {
        if indicators.contains(k) { indicators.remove(k) } else { indicators.insert(k) }
        Haptics.impact()
    }
    func clearIndicators() { indicators = []; showIndicatorMenu = false }

    func setSide(_ s: Side) { side = s; resetLevel() }

    func openOrderForm(_ s: Side) {
        guard phase == .playing else { return }
        setSide(s)
        showOrderForm = true
        Haptics.impact()
    }
    func setOrderType(_ t: OrderType) { orderType = t; resetLevel() }

    func resetLevel() {
        let p = session.lastPrice
        switch orderType {
        case .market: levelText = ""
        case .limit: levelText = String(format: "%.0f", side == .buy ? p * 0.98 : p * 1.02)
        case .stop: levelText = String(format: "%.0f", side == .buy ? p * 1.02 : p * 0.98)
        case .trailing: levelText = "2"
        }
    }

    func submit() {
        let level = Double(levelText.replacingOccurrences(of: ",", with: ""))
        do {
            try session.place(side: side, type: orderType, amountUSD: amountUSD, level: level)
            Haptics.impact()
            flash = orderType == .market ? (side == .buy ? "Bought" : "Sold") : "Order placed"
            showOrderForm = false
            if session.outcome != nil { finish() }
        } catch {
            Haptics.notify(.warning)
            switch error as? OrderError {
            case .invalidPrice: flash = needsLevel ? "Enter a valid \(orderType == .trailing ? "trail %" : "price")" : nil
            case .amountTooSmall: flash = "Nothing to trade"
            default: flash = nil
            }
        }
        if flash != nil {
            let msg = flash
            Task { try? await Task.sleep(for: .seconds(1.2)); if flash == msg { flash = nil } }
        }
    }

    /// Save this finished run to the shared leaderboard (same board as the website).
    func saveScore(initials raw: String) async {
        guard !isSaving, savedInitials == nil, phase == .ended, session.isRandomStart else { return }
        guard let initials = LeaderboardClient.cleanInitials(raw) else {
            saveError = "Enter 1–3 letters or numbers."
            return
        }
        isSaving = true; saveError = nil
        defer { isSaving = false }
        do {
            let score = Int(max(0, session.equity).rounded())
            let r = try await leaderboard.submit(initials: initials, score: score, sats: session.satsEarned)
            savedInitials = initials
            savedRank = r.rank
            lastInitials = initials
            Activity.track(.scoreSaved)
            UserDefaults.standard.set(initials, forKey: "tor_initials")
        } catch {
            saveError = "Couldn't reach the leaderboard. Check your connection and try again."
        }
    }

    func setSpeed(_ new: PlaybackSpeed) {
        speed = new
        session.speed = new
        Haptics.impact()
    }

    // MARK: Pause

    func togglePause() {
        guard phase == .playing else { return }
        autoPaused = false
        if session.isPaused { session.resume() } else { session.pause() }
        Haptics.impact()
    }

    /// Pause because something else came to the front (a sheet, another app).
    func autoPause() {
        guard phase == .playing, !session.isPaused else { return }
        session.pause()
        autoPaused = true
    }

    /// Undo an automatic pause when the sheet closes. A pause the player chose stays.
    func autoResume() {
        guard autoPaused else { return }
        autoPaused = false
        if phase == .playing { session.resume() }
    }

    /// Leaving the app always pauses and stays paused until the player resumes.
    func pauseForBackground() {
        guard phase == .playing else { return }
        autoPaused = false
        session.pause()
    }

    func sleep() { if session.startSleep() { Haptics.impact() } }
    func cashOut() { session.cashOut(); finish() }
    func cancel(_ id: Int) { session.cancelOrder(id: id); Haptics.impact() }
    func updateOrder(id: Int, level: Double, fraction: Double) throws {
        try session.modifyOrder(id: id, level: level, amountFraction: fraction)
        Haptics.impact()
        flash = "Order updated"
        Task { try? await Task.sleep(for: .seconds(1.2)); if flash == "Order updated" { flash = nil } }
    }

    func cancelAll() { session.cancelAllOrders(); Haptics.impact() }

    func closePosition() {
        if session.closePosition() {
            flash = "Position closed"
            Haptics.impact()
            if session.outcome != nil { finish() }
            Task { try? await Task.sleep(for: .seconds(1.2)); if flash == "Position closed" { flash = nil } }
        }
    }
}

enum Haptics {
    static func impact() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func notify(_ t: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(t)
    }
}
