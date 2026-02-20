import AppKit
import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TopConsumerAppsMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppImpactStore()
    @State private var hoveredAppID: pid_t?

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                if store.topApps.isEmpty {
                    Text("No eligible apps found")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.topApps) { app in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(app.name) \(Int(app.score.rounded()))%")
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 8)
                            Text(details(for: app))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                        .onHover { isHovering in
                            hoveredAppID = isHovering ? app.id : nil
                        }
                    }
                }

                if let hoveredApp = store.topApps.first(where: { $0.id == hoveredAppID }) {
                    Divider()
                    Text(tooltip(for: hoveredApp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                HStack {
                    Spacer()
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q")
                    Spacer()
                }
            }
            .padding(10)
            .frame(minWidth: 350, alignment: .leading)
        } label: {
            Label("Top Apps", systemImage: "gauge.with.needle")
        }
        .menuBarExtraStyle(.window)
    }

    private func details(for app: AppImpact) -> String {
        var parts = [
            "CPU \(Int(app.cpuImpact.rounded()))%",
            "MEM \(Int(app.memoryImpact.rounded()))%",
        ]

        if app.hasSustainedCPUSpike {
            parts.append("SPIKE")
        }

        if app.hasTabLikeMemoryPressure {
            parts.append("TABS")
        }

        if app.hasLikelyAIActivity {
            parts.append("AI")
        }

        return parts.joined(separator: "  ")
    }

    private func tooltip(for app: AppImpact) -> String {
        var lines: [String] = []

        if app.isFrontmost {
            lines.append("Foreground boost: active app gets extra weight.")
        }

        if app.hasSustainedCPUSpike {
            lines.append("SPIKE: sustained high CPU over recent samples.")
        }

        if app.hasTabLikeMemoryPressure {
            lines.append("TABS: high memory with low CPU and rising footprint.")
        }

        if let appSpecificTooltip = AppSpecificInsights.tooltip(for: app) {
            lines.append(appSpecificTooltip)
        }

        lines.append("Likely workload: \(workloadHint(for: app.name)).")
        return lines.joined(separator: "\n")
    }

    private func workloadHint(for appName: String) -> String {
        let name = appName.lowercased()
        let browserTokens = ["chrome", "safari", "firefox", "arc", "brave", "edge", "opera", "vivaldi"]
        let videoTokens = ["zoom", "teams", "meet", "slack", "discord", "webex"]
        let devTokens = ["xcode", "android studio", "cursor", "code", "intellij", "pycharm", "webstorm", "terminal", "iterm"]
        let creativeTokens = ["photoshop", "premiere", "after effects", "figma", "final cut", "davinci", "lightroom"]

        if browserTokens.contains(where: name.contains) {
            return "browser rendering, tab scripts, extensions, and media decode"
        }

        if videoTokens.contains(where: name.contains) {
            return "real-time video/audio encode-decode and network processing"
        }

        if devTokens.contains(where: name.contains) {
            return "indexing, builds, language servers, and file watchers"
        }

        if creativeTokens.contains(where: name.contains) {
            return "GPU/CPU-heavy media processing and large asset caching"
        }

        return "active UI work, background tasks, or cached data"
    }
}
