import AppKit
import SwiftUI

enum XNoxTheme {
    static let pagePadding: CGFloat = 24
    static let cardSpacing: CGFloat = 16
    static let cardCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 10
    static let grid: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
}

enum XNoxTypography {
    static let display = Font.custom("Avenir Next Demi Bold", size: 34, relativeTo: .largeTitle)
    static let sectionTitle = Font.custom("Avenir Next Demi Bold", size: 24, relativeTo: .title2)
    static let cardTitle = Font.custom("Avenir Next Demi Bold", size: 18, relativeTo: .headline)
    static let body = Font.custom("Avenir Next", size: 14, relativeTo: .body)
    static let bodyStrong = Font.custom("Avenir Next Medium", size: 14, relativeTo: .body)
    static let caption = Font.custom("Avenir Next Medium", size: 12, relativeTo: .caption)
    static let button = Font.custom("Avenir Next Demi Bold", size: 13, relativeTo: .callout)
    static let mono = Font.custom("Menlo", size: 12, relativeTo: .caption)
}

enum XNoxPalette {
    // Brand primary: #4096FF
    private static let brandPrimaryLight = NSColor(calibratedRed: 64 / 255, green: 150 / 255, blue: 1, alpha: 1)
    private static let brandPrimaryDark = NSColor(calibratedRed: 96 / 255, green: 171 / 255, blue: 1, alpha: 1)

    static let textPrimary = dynamic(
        light: NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.15, alpha: 1),
        dark: NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.93, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: NSColor(calibratedRed: 0.40, green: 0.44, blue: 0.47, alpha: 1),
        dark: NSColor(calibratedRed: 0.62, green: 0.67, blue: 0.70, alpha: 1)
    )

    static let canvas = dynamic(
        light: NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.93, alpha: 1),
        dark: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let canvasSubtle = dynamic(
        light: NSColor(calibratedRed: 0.93, green: 0.92, blue: 0.90, alpha: 1),
        dark: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.14, alpha: 1)
    )
    static let sidebarBackground = dynamic(
        light: NSColor(calibratedRed: 0.91, green: 0.90, blue: 0.87, alpha: 1),
        dark: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    )

    static let panelBackground = dynamic(
        light: NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.97, alpha: 1),
        dark: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.16, alpha: 1)
    )
    static let panelInsetBackground = dynamic(
        light: NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.93, alpha: 1),
        dark: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    )
    static let panelBorder = dynamic(
        light: NSColor(calibratedRed: 0.83, green: 0.82, blue: 0.78, alpha: 1),
        dark: NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.27, alpha: 1)
    )

    static let accentStart = dynamic(
        light: brandPrimaryLight,
        dark: brandPrimaryDark
    )
    static let accentEnd = dynamic(
        light: NSColor(calibratedRed: 46 / 255, green: 124 / 255, blue: 1, alpha: 1),
        dark: brandPrimaryLight
    )

    static let success = dynamic(
        light: NSColor(calibratedRed: 0.12, green: 0.62, blue: 0.39, alpha: 1),
        dark: NSColor(calibratedRed: 0.35, green: 0.80, blue: 0.58, alpha: 1)
    )
    static let warning = dynamic(
        light: NSColor(calibratedRed: 0.84, green: 0.52, blue: 0.12, alpha: 1),
        dark: NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.30, alpha: 1)
    )
    static let error = dynamic(
        light: NSColor(calibratedRed: 0.78, green: 0.23, blue: 0.24, alpha: 1),
        dark: NSColor(calibratedRed: 0.95, green: 0.46, blue: 0.45, alpha: 1)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return match == .darkAqua ? dark : light
            }
        )
    }
}

struct AppGradientBackground: View {
    var body: some View {
        ZStack {
            XNoxPalette.canvas

            Rectangle()
                .fill(XNoxPalette.canvasSubtle)
                .frame(height: 1)
                .offset(y: -120)
                .opacity(0.8)
        }
        .ignoresSafeArea()
    }
}
