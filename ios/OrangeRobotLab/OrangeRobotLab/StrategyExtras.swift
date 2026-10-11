import OrangeRobotKit

extension Strategy {
    /// The same rules with the name blanked, so renamed copies still count as "saved".
    var dropName: Strategy { var s = self; s.name = ""; return s }
}
