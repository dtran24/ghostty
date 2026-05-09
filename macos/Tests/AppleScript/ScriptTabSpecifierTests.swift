import AppKit
import Testing
@testable import Ghostty

@Suite(.serialized)
struct ScriptTabSpecifierTests {
    @MainActor
    @Test func resolvesLegacyWindowSpecifierAfterTabGroupForms() throws {
        let context = try ScriptTabSpecifierTestContext()
        defer { context.closeWindows() }

        let staleWindow = ScriptWindow(primaryController: context.secondaryController)
        #expect(staleWindow.stableID.hasPrefix("window-"))

        context.enableTabbing()
        context.presentWindows()
        #expect(context.primaryWindow.addTabbedWindowSafely(context.secondaryWindow, ordered: .above))
        context.spinRunLoop()

        let tabID = ScriptTab.stableID(controller: context.secondaryController)
        let resolvedWindow = try #require(
            NSApp.valueInScriptWindows(uniqueID: staleWindow.stableID)
        )

        #expect(resolvedWindow.stableID.hasPrefix("tab-group-"))
        #expect(resolvedWindow.valueInTabs(uniqueID: tabID) != nil)
    }

    @MainActor
    @Test func tabObjectSpecifierPrefersLiveWindowAfterTabGroupForms() throws {
        let context = try ScriptTabSpecifierTestContext()
        defer { context.closeWindows() }

        let staleWindow = ScriptWindow(primaryController: context.secondaryController)
        let tab = ScriptTab(window: staleWindow, controller: context.secondaryController)

        context.enableTabbing()
        context.presentWindows()
        #expect(context.primaryWindow.addTabbedWindowSafely(context.secondaryWindow, ordered: .above))
        context.spinRunLoop()

        let specifier = try #require(tab.objectSpecifier as? NSUniqueIDSpecifier)
        let containerSpecifier = try #require(specifier.container as? NSUniqueIDSpecifier)
        let resolvedWindow = try #require(
            NSApp.valueInScriptWindows(uniqueID: containerSpecifier.uniqueID as? String ?? "")
        )

        #expect(resolvedWindow.stableID.hasPrefix("tab-group-"))
        #expect((containerSpecifier.uniqueID as? String) == resolvedWindow.stableID)
    }
}

@MainActor
private final class ScriptTabSpecifierTestContext {
    let primaryController: BaseTerminalController
    let secondaryController: BaseTerminalController
    let primaryWindow: NSWindow
    let secondaryWindow: NSWindow

    init() throws {
        let app = try Self.sharedApp()

        let primaryController = ScriptTabSpecifierTestController(app, title: "Primary")
        let secondaryController = ScriptTabSpecifierTestController(app, title: "Secondary")

        guard let primaryWindow = primaryController.window,
              let secondaryWindow = secondaryController.window else {
            throw ScriptTabSpecifierTestError.missingWindow
        }

        self.primaryController = primaryController
        self.secondaryController = secondaryController
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }

    /// Reuse a single Ghostty.App across the whole test bundle.
    ///
    /// `Ghostty.App.init` initializes the libghostty Zig core and registers
    /// callbacks via an unretained `self` pointer. Constructing multiple
    /// instances during a test run can race with Zig threads and crash the
    /// test runner; a single shared instance avoids that.
    private static var sharedAppInstance: Ghostty.App?
    private static var sharedTempConfig: TemporaryConfig?

    private static func sharedApp() throws -> Ghostty.App {
        if let existing = sharedAppInstance { return existing }
        let tempConfig = try TemporaryConfig("")
        let app = Ghostty.App(configPath: tempConfig.temporaryFile.path)
        sharedTempConfig = tempConfig
        sharedAppInstance = app
        return app
    }

    func presentWindows() {
        // Avoid `NSApp.activate(ignoringOtherApps:)` here — it mutates global
        // app activation state and races with parallel test bundles.
        primaryWindow.orderFront(nil)
        secondaryWindow.orderFront(nil)
        spinRunLoop()
    }

    func enableTabbing() {
        primaryWindow.tabbingMode = .automatic
        secondaryWindow.tabbingMode = .automatic
    }

    func spinRunLoop() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    func closeWindows() {
        primaryWindow.close()
        secondaryWindow.close()
        spinRunLoop()
    }
}

@MainActor
private final class ScriptTabSpecifierTestController: BaseTerminalController {
    init(_ ghostty: Ghostty.App, title: String) {
        // Pass an empty surface tree so init does not spawn a real terminal
        // surface (which forks a login shell). The specifier tests only need
        // a controller-with-window, not a live PTY.
        super.init(ghostty, baseConfig: nil, surfaceTree: SplitTree())

        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.title = title
        self.window = window
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for tests")
    }
}

private enum ScriptTabSpecifierTestError: Error {
    case missingWindow
}
