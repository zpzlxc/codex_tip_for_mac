import SwiftUI

/// 悬浮窗浅色主题
enum WidgetTheme {
    static let background = Color.white
    static let border = Color(red: 0.82, green: 0.84, blue: 0.88)
    static let shadow = Color.black.opacity(0.12)

    static let title = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let primaryText = Color(red: 0.22, green: 0.24, blue: 0.28)
    static let secondaryText = Color(red: 0.45, green: 0.48, blue: 0.54)
    static let tertiaryText = Color(red: 0.58, green: 0.61, blue: 0.67)

    static let trackBackground = Color(red: 0.92, green: 0.93, blue: 0.95)
    static let cardBackground = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let closeButtonHover = Color(red: 0.94, green: 0.95, blue: 0.97)

    static let accentBlue = Color(red: 0.22, green: 0.52, blue: 0.96)
    static let accentPurple = Color(red: 0.52, green: 0.38, blue: 0.92)
}
