import Foundation

/// Window dimensions, rather than the device's original orientation, drive placement.
struct LCHomeMetrics: Equatable {
    let columns: Int
    let rows: Int
    let iconSide: Double
    let horizontalInset: Double
    let rowSpacing: Double
    var capacity: Int { columns * rows }

    static func isMini(model: String, shortSide: Double) -> Bool {
        let olderMinis: Set<String> = ["iPad2,5", "iPad2,6", "iPad2,7", "iPad4,4", "iPad4,5", "iPad4,6",
            "iPad4,7", "iPad4,8", "iPad4,9", "iPad5,1", "iPad5,2", "iPad11,1", "iPad11,2"]
        return olderMinis.contains(model) || shortSide <= 744
    }

    init(width: Double, height: Double, tablet: Bool, mini: Bool, accessibility: Bool = false, isLandscape: Bool? = nil) {
        let landscape = isLandscape ?? (width > height)
        if tablet {
            columns = width < 600 ? 4 : (landscape ? 6 : 5)
            rows = mini && !landscape ? 6 : 5
        } else {
            columns = landscape ? 6 : 4
            rows = landscape ? 3 : 6
        }
        horizontalInset = tablet ? max(20, min(64, width * 0.055)) : 20
        let cellWidth = max(1, (width - 2 * horizontalInset) / Double(columns))
        iconSide = max(42, min(accessibility ? 72 : (tablet ? 68 : 62), cellWidth - 18))
        // Six rows remain scrollable on small displays and with large accessibility text.
        rowSpacing = max(12, min(38, (height - Double(rows) * (iconSide + 30) - 20) / Double(max(1, rows - 1))))
    }
}

struct LCHomeFolderMetrics {
    let columns: Int
    let rows: Int
    let side: Double
    let width: Double
    let height: Double
    let spacing: Double
    let inset: Double
    let centerY: Double
    let compact: Bool
    var capacity: Int { rows * columns }
    init(width windowWidth: Double, height windowHeight: Double, iconSide: Double) {
        compact = windowHeight < 500
        width = max(200, min(windowWidth, 440) - 48)
        columns = compact && width >= 300 ? 4 : 3
        rows = compact ? 2 : 3
        spacing = compact ? 10 : 22
        inset = compact ? 16 : 24
        let cellWidth = (width - 48 - Double(columns - 1) * 12) / Double(columns)
        let room = (windowHeight - 80 - inset * 2 - Double(rows - 1) * spacing) / Double(rows) - 30
        side = min(iconSide, cellWidth, compact ? max(32, room) : iconSide)
        height = Double(rows) * (side + 30) + Double(rows - 1) * spacing + inset * 2
        centerY = compact ? 44 + height / 2 : windowHeight / 2
    }
}
