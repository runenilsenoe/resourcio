import Foundation

enum AppSpecificTooltipRegistry {
    private static let providers: [any AppSpecificTooltipProvider] = [
        IntelliJTooltipProvider(),
    ]

    static func tooltipLines(for app: AppImpact) -> [String] {
        var lines: [String] = []
        for provider in providers where provider.matches(app) {
            lines.append(contentsOf: provider.tooltipLines(for: app))
        }
        return lines
    }
}
