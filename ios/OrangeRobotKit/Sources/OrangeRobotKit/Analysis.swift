import Foundation

/// A simple "how did this rule do against just holding" number.
///
/// 0 = ended with the same money as holding; +100 = ended with 100% more money
/// than holding; −50 = ended with 50% less than holding.
public enum Score {
    public static func vsHold(robotReturn: Double, holdReturn: Double) -> Double {
        let h = 1 + holdReturn
        guard h > 1e-9 else { return 0 }
        return ((1 + robotReturn) / h - 1) * 100
    }

    public static func label(_ s: Double) -> String {
        String(format: "%@%.0f", s >= 0 ? "+" : "−", abs(s))
    }
}

public struct Finding: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case right, wrong, note }
    public let id: Int
    public let kind: Kind
    public let title: String
    public let detail: String
    /// Rough effect on the final result, in percentage points of the starting money (nil when not measurable).
    public let points: Double?
}

public struct Analysis: Sendable {
    public let score: Double
    public let headline: String
    public let findings: [Finding]
    public let suggestions: [String]
}

public enum Analyzer {
    /// Explain, in plain terms, why a rule set ended where it did against holding.
    public static func analyze(strategy: Strategy, result: BacktestResult, hold: BacktestResult,
                               history: PriceHistory, settings: BacktestSettings = BacktestSettings()) -> Analysis {
        let bars = history.bars
        let days = result.days
        let robotRet = result.metrics.totalReturn
        let holdRet = hold.metrics.totalReturn
        let score = Score.vsHold(robotReturn: robotRet, holdReturn: holdRet)
        var out: [Finding] = []
        var tips: [String] = []
        func add(_ k: Finding.Kind, _ t: String, _ d: String, _ p: Double? = nil) {
            out.append(Finding(id: out.count, kind: k, title: t, detail: d, points: p))
        }
        func pct(_ x: Double) -> String { String(format: "%.0f%%", abs(x) * 100) }

        // Which days was the robot holding bitcoin at the close?
        var invested = [Bool](repeating: false, count: days.count)
        for t in result.trades {
            for d in max(t.entryDay, days.lowerBound)..<min(t.exitDay, days.upperBound) {
                invested[d - days.lowerBound] = true
            }
        }
        if let first = result.purchases.first {
            for d in max(first.day, days.lowerBound)..<days.upperBound { invested[d - days.lowerBound] = true }
        }

        // Compounded market move on the days it was out, and on the days it was in.
        var outFactor = 1.0, inFactor = 1.0
        var outDays = 0
        for (k, d) in days.enumerated() {
            let prev = d > 0 ? bars[d - 1].close : bars[d].open
            let r = bars[d].close / prev
            if invested[k] { inFactor *= r } else { outFactor *= r; outDays += 1 }
        }
        let outShare = days.isEmpty ? 0 : Double(outDays) / Double(days.count)

        // Headline
        let diff = score
        let headline: String
        if abs(diff) < 3 { headline = "Roughly level with just holding (score \(Score.label(diff)))." }
        else if diff > 0 { headline = "Finished with \(Int(diff.rounded()))% more money than just holding (score \(Score.label(diff)))." }
        else { headline = "Finished with \(Int((-diff).rounded()))% less money than just holding (score \(Score.label(diff)))." }

        if strategy.dca != nil {
            let n = result.purchases.count
            let avg = result.trades.first?.entryPrice ?? 0
            if let firstBar = days.first.map({ bars[$0].open }), firstBar > 0 {
                let change = avg / firstBar - 1
                if change < -0.02 {
                    add(.right, "Averaged in cheaper than a single start",
                        "Spread over \(n) buys, the average price paid was \(pct(change)) below the price on day one. Buying through the dips paid off.")
                } else if change > 0.02 {
                    add(.wrong, "Paid more on average than a single start",
                        "Because the price kept rising, later buys cost more: the average price was \(pct(change)) above day one's. Holding put all the money to work at the lowest price.")
                }
            }
            if holdRet > robotRet, holdRet > 0 {
                add(.wrong, "Some of the money sat waiting in cash",
                    "DCA only invests a little at a time, so in a rising market part of your money was not yet working. That's the price of spreading risk.")
            }
            if holdRet < 0, robotRet > holdRet {
                add(.right, "Smaller falls",
                    "In a falling market DCA kept buying cheaper and lost less than putting everything in at the start.")
            }
            let plan = strategy.dca!
            let spent = result.purchases.map(\.amount).reduce(0, +)
            let idle = max(settings.startCash - spent, 0)
            add(.note, "How it works",
                "\(n) purchases of \(DCAPlan.money(result.purchases.first?.amount ?? 0)), \(plan.label): \(DCAPlan.money(spent)) invested in total. Fees and slippage were charged on each.")
            if plan.reinvests {
                let extra = result.purchases.map(\.bonus).reduce(0, +)
                if extra > 0 {
                    add(.note, "Reinvested profits",
                        "\(String(format: "%g", plan.reinvestPercent ?? 0))% of the profit so far was added to each purchase: \(DCAPlan.money(extra)) extra in total, paid from cash that was waiting.")
                } else {
                    add(.note, "Reinvesting did nothing here",
                        "There was no profit to reinvest at the time of any purchase (or no cash left), so every buy was the plain amount.")
                }
            }
            if idle >= settings.startCash * 0.05 {
                add(.note, "Part of your cash never went in",
                    "\(DCAPlan.money(idle)) of the \(DCAPlan.money(settings.startCash)) stayed in cash the whole test, which lowers the return compared with holding, because holding invests everything on day one.",
                    nil)
                tips.append("Raise the amount per purchase (or choose \"spread evenly\") to compare like with like against holding.")
            }
            tips.append("DCA is about steady habit, not beating the market. Try a different interval, or compare the same plan over a falling year to see what it's for.")
            return Analysis(score: score, headline: headline, findings: out, suggestions: tips)
        }

        // Out of the market
        if outShare > 0.05 {
            let outMove = outFactor - 1
            if outMove > 0.03 {
                add(.wrong, "Missed a rise while in cash",
                    "The robot was in cash \(pct(outShare)) of the time, and Bitcoin gained \(pct(outMove)) over those days.",
                    -outMove * 100)
            } else if outMove < -0.03 {
                add(.right, "Dodged a fall while in cash",
                    "In cash \(pct(outShare)) of the time, it sat out a \(pct(outMove)) drop in Bitcoin.",
                    -outMove * 100)
            }
        }
        // In the market
        if outShare < 0.95 {
            let inMove = inFactor - 1
            if inMove > 0.03 {
                add(.right, "Held through gains", "While invested, Bitcoin rose \(pct(inMove)) over those days.", inMove * 100)
            } else if inMove < -0.03 {
                add(.wrong, "Held through losses", "While invested, Bitcoin fell \(pct(inMove)) over those days.", inMove * 100)
            }
        }

        // Trades
        let trades = result.trades
        if trades.isEmpty {
            add(.note, "It never traded", "No buy signal appeared in this period, so the robot stayed in cash the whole time.")
            tips.append("Loosen the buy condition (a higher RSI level, a shorter average) or test a period with more movement.")
        } else {
            let wins = trades.filter { $0.returnPercent > 0 }
            let losses = trades.filter { $0.returnPercent <= 0 }
            if let best = trades.max(by: { $0.returnPercent < $1.returnPercent }), best.returnPercent > 0 {
                add(.right, "Best trade: \(String(format: "%+.0f", best.returnPercent))%",
                    "\(wins.count) of \(trades.count) trades made money.", nil)
            }
            if let worst = trades.min(by: { $0.returnPercent < $1.returnPercent }), worst.returnPercent < -3 {
                add(.wrong, "Worst trade: \(String(format: "%+.0f", worst.returnPercent))%",
                    "Closed by \(worst.reason.title.lowercased()). \(losses.count) of \(trades.count) trades lost money.", nil)
            }

            // Stopped out, then the price recovered
            let stops = trades.filter { $0.reason == .stopLoss || $0.reason == .trailingStop }
            var whipsaws = 0
            for t in stops {
                let end = min(t.exitDay + 21, bars.count)
                guard t.exitDay + 1 < end else { continue }
                let high = bars[(t.exitDay + 1)..<end].map(\.high).max() ?? 0
                if high >= t.entryPrice || high >= t.exitPrice * 1.10 { whipsaws += 1 }
            }
            if whipsaws > 0 {
                add(.wrong, "Stopped out, then the price came back",
                    "\(whipsaws) of \(stops.count) stop exits were followed by a recovery within three weeks.", nil)
                tips.append("Try a wider stop-loss or a trailing stop that gives the price more room to wobble.")
            } else if !stops.isEmpty {
                add(.right, "Stops did their job",
                    "\(stops.count) stop exit\(stops.count == 1 ? "" : "s") limited losses and the price did not quickly recover.", nil)
            }

            // Sold early after a take-profit
            let tps = trades.filter { $0.reason == .takeProfit }
            var early = 0
            for t in tps {
                let end = min(t.exitDay + 31, bars.count)
                guard t.exitDay + 1 < end else { continue }
                if (bars[(t.exitDay + 1)..<end].map(\.high).max() ?? 0) >= t.exitPrice * 1.20 { early += 1 }
            }
            if early > 0 {
                add(.wrong, "Took profit too early", "\(early) of \(tps.count) take-profit exits were followed by another 20% rise within a month.", nil)
                tips.append("Raise the take-profit level, or use a trailing stop so winners can keep running.")
            }

            // Gave back gains before selling
            var give: [Double] = []
            for t in trades where t.exitDay > t.entryDay {
                let peak = bars[t.entryDay...min(t.exitDay, bars.count - 1)].map(\.high).max() ?? t.exitPrice
                if peak > 0 { give.append((peak - t.exitPrice) / peak) }
            }
            if !give.isEmpty {
                let avg = give.reduce(0, +) / Double(give.count)
                if avg > 0.20 {
                    add(.wrong, "Gave back a lot before selling",
                        "On average, trades sold \(pct(avg)) below the highest price reached while holding.", nil)
                    tips.append("Add a trailing stop, or make the exit condition quicker to react.")
                }
            }

            // Costs
            let drag = Double(trades.count) * 2 * (settings.fee + settings.slippage) * 100
            if drag >= 1.5 {
                add(.note, "Costs added up", "\(trades.count) trades cost roughly \(String(format: "%.1f", drag)) percentage points in fees and slippage.", -drag)
            }
            if trades.count < 4 {
                add(.note, "Very few trades", "Only \(trades.count) trade\(trades.count == 1 ? "" : "s"): the result could easily be luck. Try other periods before trusting it.", nil)
                tips.append("Run the same rules over several different periods and compare in the Notebook.")
            }
        }

        if score < -20, outShare > 0.6 {
            tips.append("The robot was out of the market most of the time. Try a quicker buy signal, or keep part of your money invested.")
        }
        if score > 20 {
            tips.append("This looks good, but it is one period. Run a live test to see how it handles days it hasn't seen.")
        }
        return Analysis(score: score, headline: headline, findings: out, suggestions: tips)
    }
}
