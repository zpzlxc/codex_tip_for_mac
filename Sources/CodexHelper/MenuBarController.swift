import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let settingsController: SettingsWindowController
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var primaryResetItem: NSMenuItem?
    private var secondaryResetItem: NSMenuItem?
    private var resetCreditsItem: NSMenuItem?
    private var resetCreditExpiryItems: [NSMenuItem] = []
    private var refreshUsageItem: NSMenuItem?
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

        appState.$resetCredits
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildResetCreditExpiryItems()
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        appState.$usageError
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)

    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        self.menu = menu
        primaryResetItem = quotaInfoItem()
        secondaryResetItem = quotaInfoItem()
        menu.addItem(primaryResetItem!)
        menu.addItem(secondaryResetItem!)
        resetCreditsItem = quotaInfoItem()
        menu.addItem(resetCreditsItem!)
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
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 12, y: 2, width: 296, height: 22)
        label.lineBreakMode = .byTruncatingTail
        label.tag = 1

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        container.addSubview(label)
        item.view = container
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateDisplay()
    }

    private var statusTitle: String {
        let primary = quotaWindow(id: "primary").map { "\($0.remainingPercent)%" } ?? "--"
        let secondary = quotaWindow(id: "secondary").map { "\($0.remainingPercent)%" } ?? "--"
        return "5h \(primary) · 1w \(secondary)"
    }

    private func updateDisplay() {
        statusItem?.button?.title = statusTitle
        updateQuotaInfo(
            primaryResetItem,
            prefix: "5h重置：",
            value: resetValue(window: quotaWindow(id: "primary"))
        )
        updateQuotaInfo(
            secondaryResetItem,
            prefix: "1w重置：",
            value: resetValue(window: quotaWindow(id: "secondary"))
        )
        updateQuotaInfo(
            resetCreditsItem,
            prefix: "可用重置：",
            value: resetCreditsValue
        )
        refreshUsageItem?.title = refreshUsageTitle
    }

    private func updateQuotaInfo(_ item: NSMenuItem?, prefix: String, value: String) {
        guard let view = item?.view else { return }
        let fontSize = NSFont.menuFont(ofSize: 0).pointSize
        let prefixAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSMutableAttributedString(string: prefix, attributes: prefixAttributes)
        text.append(NSAttributedString(string: " \(value)", attributes: valueAttributes))
        (view.viewWithTag(1) as? NSTextField)?.attributedStringValue = text
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
        guard let window else {
            return appState.usageError == nil ? "获取中..." : "刷新失败"
        }
        guard let resetDate = resolvedResetDate(for: window) else {
            return "暂无重置时间"
        }
        return MenuDateFormatters.resetTime(resetDate)
    }

    private var resetCreditsValue: String {
        guard let credits = appState.resetCredits else {
            return appState.usageError == nil ? "获取中..." : "刷新失败"
        }
        return "\(credits.availableCount) 次"
    }

    private func rebuildResetCreditExpiryItems() {
        guard let menu, let refreshUsageItem else { return }
        resetCreditExpiryItems.forEach(menu.removeItem)
        resetCreditExpiryItems.removeAll()

        let insertionIndex = menu.index(of: refreshUsageItem)
        guard insertionIndex >= 0 else { return }
        for (index, expiresAt) in (appState.resetCredits?.expiresAt ?? []).enumerated() {
            let item = quotaInfoItem()
            updateQuotaInfo(
                item,
                prefix: "重置\(index + 1)：",
                value: MenuDateFormatters.resetTime(Date(timeIntervalSince1970: TimeInterval(expiresAt)))
            )
            menu.insertItem(item, at: insertionIndex + index)
            resetCreditExpiryItems.append(item)
        }
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
