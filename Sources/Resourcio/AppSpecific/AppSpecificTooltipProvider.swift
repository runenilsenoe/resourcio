import Foundation

protocol AppSpecificTooltipProvider: Sendable {
    func matches(_ app: AppImpact) -> Bool
    func tooltipLines(for app: AppImpact) -> [String]
}

extension AppSpecificTooltipProvider {
    func commandDetected(in app: AppImpact, tokens: [String]) -> Bool {
        guard !app.childCommandHints.isEmpty else { return false }
        let lowerCommands = app.childCommandHints.map { $0.lowercased() }
        return tokens.contains { token in
            lowerCommands.contains { $0.contains(token) }
        }
    }
}
