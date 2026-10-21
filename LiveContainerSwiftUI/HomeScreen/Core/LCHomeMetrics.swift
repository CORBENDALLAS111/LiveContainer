import Foundation

/// Window dimensions, rather than the device's original orientation, drive placement.
struct LCHomeMetrics: Equatable {
    let columns: Int
    let rows: Int
    let iconSide: Double
    let horizontalInset: Double
    let rowSpacing: Double
    var capacity: Int { columns * rows }

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
