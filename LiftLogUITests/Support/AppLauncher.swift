import XCTest

/// Launch arguments understood by the app in DEBUG builds (see `LiftLogApp`).
enum LaunchArgument: String {
    /// Runs the app against an in-memory SwiftData store, so each UI test starts
    /// from an empty database and leaves nothing behind in the simulator.
    case inMemoryStore = "-uiTestInMemoryStore"
}

/// Single entry point for launching the app under test.
///
/// UI tests must not reuse a store between runs — SwiftData persistence in the
/// simulator would otherwise carry an unfinished workout from one test into the
/// next, and `RootTabView` resumes whatever active workout it finds.
enum AppLauncher {
    @discardableResult
    static func launch(
        arguments: [LaunchArgument] = [.inMemoryStore],
        extraArguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments.map(\.rawValue) + extraArguments
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        return app
    }
}

extension XCUIElement {
    /// `waitForExistence` with a message, so a failure names the element instead
    /// of reporting a bare `false`.
    @discardableResult
    func waitUntilVisible(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let appeared = waitForExistence(timeout: timeout)
        if !appeared {
            XCTFail("Элемент не появился за \(timeout)s: \(self)", file: file, line: line)
        }
        return appeared
    }
}
