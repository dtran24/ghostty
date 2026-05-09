import AppKit
import Testing
@testable import Ghostty

@Suite
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
        let tempConfig = try TemporaryConfig("")
        let app = Ghostty.App(configPath: tempConfig.temporaryFile.path)

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

    func presentWindows() {
        NSApp.activate(ignoringOtherApps: true)
        primaryWindow.makeKeyAndOrderFront(nil)
        secondaryWindow.makeKeyAndOrderFront(nil)
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
        super.init(ghostty)

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
