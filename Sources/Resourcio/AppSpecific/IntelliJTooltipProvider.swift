import Foundation

struct IntelliJTooltipProvider: AppSpecificTooltipProvider {
    private let bundlePrefixes = [
        "com.jetbrains.",
    ]

    private let nameTokens = [
        "intellij",
        "jetbrains",
        "idea",
    ]

    func matches(_ app: AppImpact) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier?.lowercased() {
            if bundlePrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
                return true
            }
        }

        let lowerName = app.name.lowercased()
        return nameTokens.contains { lowerName.contains($0) }
    }

    func tooltipLines(for app: AppImpact) -> [String] {
        var lines: [String] = ["IntelliJ-specific checks:"]

        if commandDetected(in: app, tokens: ["java", "jbr"]) {
            lines.append("- Java runtime detected: editor, indexing, and plugin execution share this process tree.")
        }

        if commandDetected(in: app, tokens: ["copilot", "language-server", "jetbrains-ai"]) {
            lines.append("- AI assistant process detected: completion/chat features are active and included in this app's totals.")
        }

        if commandDetected(in: app, tokens: ["gradle", "javac", "kotlinc", "kotlin", "maven"]) {
            lines.append("- Build tooling detected: compile/build workers are contributing to CPU usage.")
        }

        if commandDetected(in: app, tokens: ["index", "fsnotifier", "clangd", "tsserver"]) {
            lines.append("- Indexer/language-service activity detected: project model and symbol search data are being updated.")
        }

        if lines.count == 1 {
            lines.append("- No IntelliJ-specific child command signatures were observed in this refresh window.")
        }

        return lines
    }
}
