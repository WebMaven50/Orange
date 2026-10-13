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
    /// Where the chart is looking: live, or pinned back in time, plus the price-scale zoom.
    private(set) var viewport = ChartViewport()
    var showChartHint = false
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
    /// While the order ticket is open the market waits on Normal and Fast, where prices move
    /// too quickly to type an order against. Actual speed (real time) keeps running.
    var showNotifyPrompt = false
    var showOrderForm = false {
        didSet {
            guard phase == .playing, showOrderForm != oldValue else { return }
            if showOrderForm { if speed != .actual { autoPause() } }
            else { autoResume() }
        }
    }
    var showPositions = false
    var showNews = false

    // Quote shown before each run
    static let showQuotesKey = "show_quotes"
    private(set) var quote: Quote?
    private var quoteDeck = GameModel.loadQuoteDeck()
    private static func loadQuoteDeck() -> QuoteDeck {
        let d = UserDefaults.standard
        return QuoteDeck(seen: Set(d.stringArray(forKey: "quotes_seen") ?? []),
                         last: d.string(forKey: "quotes_last"),
                         recent: d.stringArray(forKey: "quotes_recent") ?? [])
    }
    func dismissQuote() {
        withAnimation(.easeOut(duration: 0.25)) { quote = nil }
    }
    private func presentQuote() {
        guard UserDefaults.standard.object(forKey: Self.showQuotesKey) as? Bool ?? true,
              let next = quoteDeck.next() else { return }
        let d = UserDefaults.standard
        d.set(Array(quoteDeck.seen), forKey: "quotes_seen")
        d.set(quoteDeck.last, forKey: "quotes_last")
        d.set(quoteDeck.recent, forKey: "quotes_recent")
        quote = next
    }

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
    var vaultTotal: Int?
    var isSaving = false
    var saveError: String?
    var lastInitials = UserDefaults.standard.string(forKey: "tor_initials") ?? ""
    private let leaderboard = LeaderboardClient()

    // Saved run (so closing or losing the app never loses a game)
    private struct SavedRun: Codable {
        var snapshot: SessionSnapshot
        var timeframe: Int
        var lastSeenNewsDay: Int
        var summary: String
    }
    private static let savedRunKey = "saved_run_v1"
    private var savedRun: SavedRun? = GameModel.loadSavedRun()
    private var lastSave = Date.distantPast
    /// "Mar 12, 2020 · $104.2K" for the Continue button, nil when there is nothing to continue.
    var savedRunSummary: String? { savedRun?.summary }

    private static func loadSavedRun() -> SavedRun? {
        guard let data = UserDefaults.standard.data(forKey: savedRunKey) else { return nil }
        return try? JSONDecoder().decode(SavedRun.self, from: data)
    }

    /// Write the current run to disk. Cheap; called on backgrounding, every few seconds, and
    /// whenever the run's shape changes.
    func saveRun() {
        guard phase == .playing, let snap = session.snapshot() else { return }
        lastSave = Date()
        let run = SavedRun(snapshot: snap, timeframe: timeframe, lastSeenNewsDay: lastSeenNewsDay,
                           summary: "\(Fmt.date(session.currentDate)) · \(Fmt.compact(session.equity)) equity")
        savedRun = run
        if let data = try? JSONEncoder().encode(run) {
            UserDefaults.standard.set(data, forKey: Self.savedRunKey)
        }
    }

    private func clearSavedRun() {
        savedRun = nil
        UserDefaults.standard.removeObject(forKey: Self.savedRunKey)
    }

    /// Pick the previous game back up, paused, exactly where it was left.
    func continueSavedRun() {
        guard phase != .playing, let saved = savedRun,
              let restored = GameSession(snapshot: saved.snapshot) else { clearSavedRun(); return }
        session = restored
        speed = saved.snapshot.speed
        timeframe = saved.timeframe
        indicators = []
        showIndicatorMenu = false
        autoPaused = false
        viewport.reset()
        moments = MomentMonitor()
        wasSleeping = false
        stopLiveFeed()
        showOrderForm = false; showPositions = false; showNews = false
        banner = nil; bannerQueue = []
        quote = nil
        // Headlines already passed stay in the feed; nothing floods the screen on return.
        let startDay = Int((session.engine.date(forDayOffset: 0).timeIntervalSince1970 / 86_400).rounded())
        newsTracker = NewsTracker(startDay: startDay)
        _ = newsTracker.update(day: session.currentDayNumber, price: session.lastPrice)
        lastSeenNewsDay = saved.lastSeenNewsDay
        phase = .playing
        side = .buy
        orderType = .market
        fraction = 0.75
        banked = false
        savedInitials = nil; savedRank = nil; vaultTotal = nil; saveError = nil; isSaving = false
        resetLevel()
        startTimer()
        Feedback.play(.select)
    }

    private func startTimer() {
        lastTick = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var timer: Timer?
    /// Real-time feed: polls the live price once the clock has caught up with the data.
    private var liveFeedTask: Task<Void, Never>?
    private(set) var liveFeedFailed = false
    private var moments = MomentMonitor()
    private var wasSleeping = false
    private var lastTick = Date()
    private var banked = false

    /// Player setting (Info screen): small live price flickers. On by default.
    static var liveFlicker: Bool {
        UserDefaults.standard.object(forKey: "live_flicker") as? Bool ?? true
    }

    // MARK: Lifecycle

    /// True while any sheet is covering the game, so the market can wait.
    var anySheetOpen: Bool { showInfo || showLeaderboard || showPrologue || showStartPicker || showPositions || showNews || quote != nil }

    func startNewRun(_ choice: StartChoice = .random) {
        stopLiveFeed()
        switch choice {
        case .random: session = .random(microMoves: Self.liveFlicker)
        case .moment(let d): session = .starting(at: d, microMoves: Self.liveFlicker)
        }
        speed = .normal
        session.speed = .normal
        indicators = []
        showIndicatorMenu = false
        autoPaused = false
        viewport.reset()
        moments = MomentMonitor()
        wasSleeping = false
        Feedback.play(.start)
        maybeShowChartHint()
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
        savedInitials = nil; savedRank = nil; vaultTotal = nil; saveError = nil; isSaving = false
        Activity.track(.gameStart)
        presentQuote()
        resetLevel()
        startTimer()
        if session.isLive { enterRealTime(announce: false) }
        saveRun()
    }

    private func step() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard phase == .playing else { return }
        let fillsBefore = session.fills.count
        session.advance(seconds: dt)
        if session.isLive && liveFeedTask == nil { enterRealTime(announce: true) }
        if session.fills.count > fillsBefore, let f = session.fills.first, f.via != .market {
            Feedback.play(f.side == .buy ? .buy : .sell)
            flash = "\(f.via.rawValue.capitalized) \(f.side.rawValue) filled"
            Task { try? await Task.sleep(for: .seconds(1.4)); if flash?.hasSuffix("filled") == true { flash = nil } }
        }
        trackNews()
        trackMoments()
        if session.outcome != nil { finish() }
        else if Date().timeIntervalSince(lastSave) > 5 { saveRun() }
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
        Feedback.play(.news)
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

    /// Subtle physical cues for what's happening in the market.
    private func trackMoments() {
        let sleeping = session.isSleeping
        if wasSleeping && !sleeping {
            Feedback.play(.wake)
            moments.resetSwing(at: session.absMinute)
        }
        wasSleeping = sleeping
        guard !session.isPaused else { return }
        let triggers = session.pendingOrders.map { (id: $0.id, price: session.triggerPrice(for: $0)) }
        let found = moments.update(equity: session.equity, price: session.lastPrice,
                                   absMinute: session.absMinute, orderTriggers: triggers,
                                   allowSwing: !sleeping)
        for m in found {
            switch m {
            case .milestone: Feedback.play(.milestone)
            case .danger: Feedback.play(.danger)
            case .near: Feedback.play(.near)
            case .swing: Feedback.play(.swing)
            }
        }
    }

    /// The game has caught up with the newest real data: run at Actual speed on the live price.
    private func enterRealTime(announce: Bool) {
        speed = .actual
        session.speed = .actual
        startLiveFeed()
        guard announce else { return }
        flash = "Caught up with the latest data. Now in real time."
        Task { try? await Task.sleep(for: .seconds(3.2)); if flash?.hasPrefix("Caught up") == true { flash = nil } }
    }

    private func startLiveFeed() {
        liveFeedTask?.cancel()
        liveFeedTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let price = try await LivePrice.fetch()
                    guard let self, !Task.isCancelled else { return }
                    self.session.recordLivePrice(price)
                    self.liveFeedFailed = false
                } catch {
                    self?.liveFeedFailed = true
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func stopLiveFeed() {
        liveFeedTask?.cancel()
        liveFeedTask = nil
        liveFeedFailed = false
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        stopLiveFeed()
        // Ask once, after the first finished game. Declining keeps everything off.
        if !UserDefaults.standard.bool(forKey: GameNotifications.askedKey) {
            UserDefaults.standard.set(true, forKey: GameNotifications.askedKey)
            showNotifyPrompt = true
        }
        clearSavedRun()
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
        switch session.outcome {
        case .win: Feedback.play(.win)
        case .bust: Feedback.play(.bust)
        default: Feedback.play(.finished)
        }
    }

    // MARK: Ticket

    var maxAmount: Double { session.maxAmount(for: side) }
    var amountUSD: Double { maxAmount * fraction }
    var needsLevel: Bool { orderType != .market }

    /// Whether the ticket's amount field is in BTC (otherwise USD).
    var amountInBTC = false

    /// Price the order is sized at: the limit/stop level when one is typed, else the market.
    var referencePrice: Double {
        if orderType == .limit || orderType == .stop,
           let v = Double(levelText.replacingOccurrences(of: ",", with: "")), v > 0 { return v }
        return session.lastPrice
    }
    /// Most BTC this order could be for. Selling a position is exactly what you hold.
    var maxQuantity: Double {
        if side == .sell && session.btc > 0 { return session.btc }
        let p = referencePrice
        guard p > 0 else { return 0 }
        return maxAmount * (side == .buy ? (1 - GameSession.fee) : 1) / p
    }
    var quantity: Double { maxQuantity * fraction }
    func setQuantity(_ q: Double) {
        guard maxQuantity > 0 else { return }
        fraction = min(max(q / maxQuantity, 0), 1)
    }

    func toggleIndicator(_ k: IndicatorKind) {
        if indicators.contains(k) { indicators.remove(k) } else { indicators.insert(k) }
        Feedback.play(.select)
    }
    func clearIndicators() { indicators = []; showIndicatorMenu = false }

    func setSide(_ s: Side) { side = s; resetLevel() }

    func openOrderForm(_ s: Side) {
        guard phase == .playing else { return }
        setSide(s)
        showOrderForm = true
        Feedback.play(.select)
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
            if orderType == .market { Feedback.play(side == .buy ? .buy : .sell) } else { Feedback.play(.tap) }
            flash = orderType == .market ? (side == .buy ? "Bought" : "Sold") : "Order placed"
            showOrderForm = false
            if session.outcome != nil { finish() }
        } catch {
            Haptics.notify(.warning)
            switch error as? OrderError {
            case .invalidPrice: flash = needsLevel ? "Enter a valid \(orderType == .trailing ? "trail %" : "price")" : nil
            case .amountTooSmall: flash = "Nothing to trade"
            case .stopOnWrongSide(let s):
                let now = Fmt.usd(session.lastPrice, decimals: session.lastPrice < 1000 ? 2 : 0)
                flash = s == .sell
                    ? "A sell stop must sit below the market (\(now)). To sell higher, use Limit."
                    : "A buy stop must sit above the market (\(now)). To buy lower, use Limit."
            default: flash = nil
            }
        }
        if flash != nil {
            let msg = flash
            let secs = (msg?.count ?? 0) > 30 ? 3.2 : 1.2
            Task { try? await Task.sleep(for: .seconds(secs)); if flash == msg { flash = nil } }
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
            vaultTotal = r.vaultTotal
            lastInitials = initials
            Feedback.play(.finished)
            Activity.track(.scoreSaved)
            UserDefaults.standard.set(initials, forKey: "tor_initials")
        } catch {
            saveError = "Couldn't reach the leaderboard. Check your connection and try again."
        }
    }

    func setSpeed(_ new: PlaybackSpeed) {
        guard !session.isLive else { return }   // real time is always Actual
        speed = new
        session.speed = new
        Feedback.play(.select)
    }

    // MARK: Chart viewport

    /// Candles for the chart, ending at the pinned moment when scrolled back.
    func visibleCandles(count: Int) -> [Candle] {
        let end = viewport.effectiveEnd(timeframe: timeframe, liveMinute: session.absMinute)
        return session.candles(timeframeMinutes: timeframe, count: count, atMinute: end)
    }

    /// Start minute (game clock) of each of the last `count` candles, in order.
    func visibleCandleStarts(count: Int) -> [Double] {
        let tf = timeframe
        let end = viewport.effectiveEnd(timeframe: tf, liveMinute: session.absMinute)
        let lastBucket: Int
        if tf >= 1440 {
            lastBucket = Int(floor(end / 1440)) / (tf / 1440)     // same bucketing as the engine
        } else {
            lastBucket = Int(floor(end / Double(tf)))
        }
        return (0..<count).map { k in Double(lastBucket - (count - 1 - k)) * Double(tf) }
    }

    /// "Mar 8, 2017 · 9:15 AM" (or just the date for daily and longer candles).
    func timeLabel(forMinute m: Double) -> String {
        let date = Fmt.date(session.engine.date(forDayOffset: Int(floor(m / 1440))))
        if timeframe >= 10_080 { return "Week of " + date }
        if timeframe >= 1_440 { return date }
        var mod = m.truncatingRemainder(dividingBy: 1440)
        if mod < 0 { mod += 1440 }
        return date + " · " + Fmt.clock(minuteOfDay: Int(mod))
    }

    /// The date at the chart's right edge when scrolled back; nil when live.
    var viewedDate: Date? {
        guard !viewport.isLive else { return nil }
        let end = viewport.effectiveEnd(timeframe: timeframe, liveMinute: session.absMinute)
        return session.engine.date(forDayOffset: Int(floor(end / 1440)))
    }

    func panChart(candlesBack n: Double) {
        let wasLive = viewport.isLive
        viewport.pan(candlesBack: n, timeframe: timeframe, liveMinute: session.absMinute,
                     startDay: session.engine.startDay)
        if !wasLive && viewport.isLive { Feedback.play(.select) }
    }

    func chartGoLive() { viewport.goLive(); Feedback.play(.select) }
    func zoomPrice(by f: Double) { viewport.zoom(by: f) }
    func resetPriceScale() { viewport.resetZoom(); Feedback.play(.select) }

    /// A one-time hint about the chart gestures.
    func maybeShowChartHint() {
        guard !UserDefaults.standard.bool(forKey: "chart_hint_seen") else { return }
        UserDefaults.standard.set(true, forKey: "chart_hint_seen")
        showChartHint = true
        Task { try? await Task.sleep(for: .seconds(6)); showChartHint = false }
    }

    // MARK: Pause

    func togglePause() {
        guard phase == .playing else { return }
        autoPaused = false
        if session.isPaused { session.resume() } else { session.pause() }
        Feedback.play(session.isPaused ? .pause : .resume)
    }

    /// Pause because something else came to the front (a sheet, another app).
    func autoPause() {
        guard phase == .playing, !session.isPaused else { return }
        session.pause()
        autoPaused = true
    }

    /// Undo an automatic pause when the sheet closes. A pause the player chose stays.
    func autoResume() {
        guard autoPaused, !showOrderForm else { return }
        autoPaused = false
        if phase == .playing { session.resume() }
    }

    /// Leaving the app always pauses and stays paused until the player resumes.
    func pauseForBackground() {
        guard phase == .playing else { return }
        autoPaused = false
        session.pause()
        saveRun()
    }

    func sleep() { if session.startSleep() { Feedback.play(.pause) } }
    /// Jump ahead one day at a time. Each press is instant and stacks: seven presses is a week.
    func skipDay() {
        guard session.skipDays(1) else { return }
        Feedback.play(.select)
        trackNews()
        trackMoments()
        if session.outcome != nil { finish() } else { saveRun() }
        flash = "Jumped to \(Fmt.date(session.currentDate))"
        Task { try? await Task.sleep(for: .seconds(1.6)); if flash?.hasPrefix("Jumped") == true { flash = nil } }
    }
    func cashOut() { session.cashOut(); finish() }
    func cancel(_ id: Int) { session.cancelOrder(id: id); Feedback.play(.select) }
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

/// Thin wrapper so existing call sites respect the player's Haptics switch.
enum Haptics {
    static func impact() { Feedback.play(.tap) }
    static func notify(_ t: UINotificationFeedbackGenerator.FeedbackType) {
        switch t {
        case .success: Feedback.play(.finished)
        case .error: Feedback.play(.bust)
        default: Feedback.play(.news)
        }
    }
}
