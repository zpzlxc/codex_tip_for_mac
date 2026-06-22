import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let settingsController: SettingsWindowController
    private var statusItem: NSStatusItem?
    private var primaryResetItem: NSMenuItem?
    private var secondaryResetItem: NSMenuItem?
    private var refreshUsageItem: NSMenuItem?
    private var activityItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    init(
        appState: AppState,
        settingsController: SettingsWindowController
    ) {
        self.appState = appState
        self.settingsController = settingsController
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        button.image = nil
        button.title = statusTitle
        button.toolTip = "Codex 额度"

        let menu = buildMenu()
        menu.delegate = self
        statusItem?.menu = menu

        appState.$quotaWindows
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        appState.$lastUsageRefresh
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        appState.$activityState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        activityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(activityItem!)
        menu.addItem(.separator())
        primaryResetItem = quotaInfoItem()
        secondaryResetItem = quotaInfoItem()
        menu.addItem(primaryResetItem!)
        menu.addItem(secondaryResetItem!)
        menu.addItem(.separator())
        refreshUsageItem = append(to: menu, title: refreshUsageTitle, action: #selector(refreshUsage))
        menu.addItem(.separator())
        append(to: menu, title: "设置…", action: #selector(openSettings))
        menu.addItem(.separator())
        append(to: menu, title: "退出 Codex Helper", action: #selector(quit))
        return menu
    }

    @discardableResult
    private func append(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = menuItem(title, action: action)
        menu.addItem(item)
        return item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func quotaInfoItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let prefixLabel = NSTextField(labelWithString: "")
        prefixLabel.frame = NSRect(x: 12, y: 2, width: 70, height: 22)
        prefixLabel.font = NSFont.menuFont(ofSize: 0)
        prefixLabel.textColor = .labelColor
        prefixLabel.alignment = .left
        prefixLabel.tag = 1

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.frame = NSRect(x: 70, y: 2, width: 180, height: 22)
        valueLabel.font = NSFont.menuFont(ofSize: 0)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.tag = 2

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        container.addSubview(prefixLabel)
        container.addSubview(valueLabel)
        item.view = container
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateDisplay()
    }

    private var statusTitle: String {
        let primary = quotaWindow(id: "primary").map { "\($0.remainingPercent)%" } ?? "--"
        let secondary = quotaWindow(id: "secondary").map { "\($0.remainingPercent)%" } ?? "--"
        return "\(appState.activityState.title) · 5h \(primary) · 1w \(secondary)"
    }

    private func updateDisplay() {
        statusItem?.button?.attributedTitle = activityTitle(statusTitle)
        activityItem?.attributedTitle = activityTitle("●  \(appState.activityState.title)")
        updateQuotaInfo(
            primaryResetItem,
            prefix: "5h 重置：",
            value: resetValue(window: quotaWindow(id: "primary"))
        )
        updateQuotaInfo(
            secondaryResetItem,
            prefix: "1w 重置：",
            value: resetValue(window: quotaWindow(id: "secondary"))
        )
        refreshUsageItem?.title = refreshUsageTitle
    }

    private func activityTitle(_ title: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title.hasPrefix("●") ? title : "●  \(title)",
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor
            ]
        )
        result.addAttribute(
            .foregroundColor,
            value: activityColor,
            range: NSRange(location: 0, length: 1)
        )
        return result
    }

    private var activityColor: NSColor {
        switch appState.activityState {
        case .idle:
            return .systemGreen
        case .running:
            return .systemYellow
        case .awaitingApproval:
            return .systemRed
        }
    }

    private func updateQuotaInfo(_ item: NSMenuItem?, prefix: String, value: String) {
        guard let view = item?.view else { return }
        (view.viewWithTag(1) as? NSTextField)?.stringValue = prefix
        (view.viewWithTag(2) as? NSTextField)?.stringValue = value
    }

    private var refreshUsageTitle: String {
        guard let lastRefresh = appState.lastUsageRefresh else {
            return "更新："
        }
        return "更新：\(MenuDateFormatters.timeWithSeconds(lastRefresh))"
    }

    private func quotaWindow(id: String) -> QuotaWindow? {
        appState.quotaWindows.first { $0.id == id }
    }

    private func resetValue(window: QuotaWindow?) -> String {
        guard let window, let resetDate = resolvedResetDate(for: window) else {
            return "获取中..."
        }
        return MenuDateFormatters.resetTime(resetDate)
    }

    private func resolvedResetDate(for window: QuotaWindow) -> Date? {
        window.resetAt
    }

    @objc private func refreshUsage() {
        Task { [weak self] in
            guard let self else { return }
            await appState.refreshUsage()
            updateDisplay()
        }
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private enum MenuDateFormatters {
    private static let timeWithSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd ahh:mm:ss"
        return formatter
    }()

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd ahh:mm:ss"
        return formatter
    }()

    static func timeWithSeconds(_ date: Date) -> String {
        timeWithSecondsFormatter.string(from: date)
    }

    static func resetTime(_ date: Date) -> String {
        resetFormatter
            .string(from: date)
            .replacingOccurrences(of: "上午 ", with: "上午")
            .replacingOccurrences(of: "下午 ", with: "下午")
    }
}
