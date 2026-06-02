import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private let appState: AppState
    private var panel: NSPanel?

    init(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show() {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        if let screen = NSScreen.main, !panel.isVisible {
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
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    private func createPanel() {
        let hosting = NSHostingView(
            rootView: StatusWidgetView(appState: appState) {
                NSApp.terminate(nil)
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hosting
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
    }
}
