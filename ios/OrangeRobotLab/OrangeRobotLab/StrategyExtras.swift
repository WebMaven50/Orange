import OrangeRobotKit

extension Strategy {
    /// The same rules with the name blanked, so renamed copies still count as "saved".
    var dropName: Strategy { var s = self; s.name = ""; return s }

    /// One line describing how the robot decides, for lists.
    var decisionSummary: String {
        if let d = dca { return "DCA: buys \(d.shortAmountText) \(d.label)" }
        return entry.map(\.summary).joined(separator: " and ")
    }
}
