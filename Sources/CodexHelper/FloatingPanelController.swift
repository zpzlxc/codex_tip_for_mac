import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private let appState: AppState
    private var panel: NSPanel?
    private var hostingView: NSHostingView<StatusWidgetView>?
    private var isPanelShowing = false

    init(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool {
        isPanelShowing
    }

    func show() {
        if panel == nil || hostingView == nil {
            createPanel()
        }

        guard let panel else { return }

        if let screen = NSScreen.main, !isPanelShowing {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.maxX - panel.frame.width - 24,
                    y: frame.maxY - panel.frame.height - 24
                )
            )
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        isPanelShowing = true
    }

    func hide() {
        panel?.orderOut(nil)
        isPanelShowing = false
    }

    func toggle() {
        if isPanelShowing {
            hide()
        } else {
            show()
        }
    }

    private func createPanel() {
        let contentView = StatusWidgetView(appState: appState) {
            NSApp.terminate(nil)
        }

        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 300))
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        panel.contentView = container
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        self.panel = panel
        self.hostingView = hosting
        self.isPanelShowing = false
    }
}
