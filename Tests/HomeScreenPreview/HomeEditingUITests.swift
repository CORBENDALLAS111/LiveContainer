import XCTest

final class HomeEditingUITests: XCTestCase {
    func testOneContinuousGridScrollsFromFirstTo128thApp() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-LCOSHomeLongGridTests", "YES",
            "-LCOSPreviewEnabled", "NO",
            "-LCOSHomeGestureTests", "NO",
            "-AppleLanguages", "(en)"
        ]
        app.launch()

        let grid = app.scrollViews["lifecontainer.homeContinuousGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 20))
        let first = app.buttons["lifecontainer.appIcon.org.example.gesture.0"]
        let last = app.buttons["lifecontainer.appIcon.org.example.gesture.127"]

        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.isHittable)
        XCTAssertFalse(last.isHittable)

        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "home-continuous-grid-top"; top.lifetime = .keepAlways; add(top)

        // A root grid must continue vertically, not switch pages horizontally.
        for _ in 0..<24 {
            if last.exists && last.isHittable { break }
            grid.swipeUp()
        }
        XCTAssertTrue(last.exists && last.isHittable,
                      "The last installed app must be reachable in the same vertical grid")
        let bottom = XCTAttachment(screenshot: app.screenshot())
        bottom.name = "home-continuous-grid-bottom"; bottom.lifetime = .keepAlways; add(bottom)

        for _ in 0..<24 {
            if first.exists && first.isHittable { break }
            grid.swipeDown()
        }
        XCTAssertTrue(first.exists && first.isHittable,
                      "The same grid must scroll back to the initial app")
    }

    func testBlankSpaceAndGridGapEnterEditing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-LCOSHomeGestureTests", "YES", "-LCOSPreviewEnabled", "NO", "-AppleLanguages", "(en)"]
        app.launch()
        let icons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lifecontainer.appIcon."))
        XCTAssertTrue(icons.firstMatch.waitForExistence(timeout: 20))
        let done = app.buttons["lifecontainer.editDone"]
        let removes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lifecontainer.remove."))
        XCTAssertFalse(done.exists)
        XCTAssertEqual(removes.count, 0)

        // Real stationary touch on empty scroll content, without an edit-mode launch flag.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.7)
        print("BLANK TRACE", app.staticTexts["fixture.blankTrace"].label)
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(removes.count, 0)
        let moving = NSPredicate(format: "label != '0'")
        expectation(for: moving, evaluatedWith: app.staticTexts["fixture.jiggleCount"])
        waitForExpectations(timeout: 5)
        let portrait = XCTAttachment(screenshot: app.screenshot())
        portrait.name = "mini-editing-portrait"; portrait.lifetime = .keepAlways; add(portrait)
        done.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 1))
        XCTAssertEqual(removes.count, 0)

        // A stationary icon hold opens its menu and must not enable deletion.
        icons.firstMatch.press(forDuration: 0.8)
        XCTAssertFalse(done.exists)
        XCTAssertEqual(removes.count, 0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8)).tap()

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        let firstRow = icons.allElementsBoundByIndex.map(\.frame).filter { $0.minY < icons.firstMatch.frame.minY + 10 }.sorted { $0.minX < $1.minX }
        XCTAssertGreaterThan(firstRow.count, 1)
        let left = firstRow[0], right = firstRow[1]
        XCTAssertGreaterThan(right.minX, left.maxX)
        let gap = CGPoint(x: (left.maxX + right.minX) / 2, y: left.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: gap.x, dy: gap.y)).press(forDuration: 0.7)
        print("BLANK TRACE", app.staticTexts["fixture.blankTrace"].label)
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(removes.count, 0)

        expectation(for: moving, evaluatedWith: app.staticTexts["fixture.jiggleCount"])
        waitForExpectations(timeout: 5)
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "mini-editing-landscape"; landscape.lifetime = .keepAlways; add(landscape)
        done.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 1))
        XCTAssertEqual(removes.count, 0)
        XCUIDevice.shared.orientation = .portrait
    }
}
