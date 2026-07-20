import XCTest

final class XcodeProjectConfigurationTests: XCTestCase {
    func testInfoPlistContainsCameraAndMicrophoneUsageDescriptions() throws {
        let plistURL = try resourceURL(named: "AppInfoFixture", withExtension: "plist")

        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertFalse((plist["NSCameraUsageDescription"] as? String)?.isEmpty ?? true)
        XCTAssertFalse((plist["NSMicrophoneUsageDescription"] as? String)?.isEmpty ?? true)
        XCTAssertNil(
            plist["NSPrincipalClass"],
            "The app should use the standard SwiftUI/AppKit lifecycle instead of a custom NSApplication principal class."
        )
    }

    func testRuntimeInfoPlistDoesNotLaunchAsAgentApp() throws {
        let plistURL = try resourceURL(named: "AppInfoFixture", withExtension: "plist")

        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertNil(
            plist["LSUIElement"],
            "FrameMate should not be marked as an LSUIElement agent app because that hides standard app/menu behavior such as reliable Cmd+Q handling."
        )
    }

    func testAppEntitlementsAllowSandboxedMicrophoneInput() throws {
        let entitlementsURL = try resourceURL(named: "VideoRecorder", withExtension: "entitlements")

        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: entitlementsData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(entitlements["com.apple.security.device.microphone"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.device.audio-input"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.assets.movies.read-write"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
        XCTAssertNil(entitlements["com.apple.security.files.downloads.read-write"])
    }

    func testUnitTestsUseBuiltFrameMateAppAsTestHost() throws {
        let projectContents = try projectContents()

        XCTAssertTrue(
            projectContents.contains("TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/FrameMate.app/Contents/MacOS/FrameMate\";"),
            "Xcode unit tests should point to the built FrameMate app bundle."
        )
        XCTAssertFalse(
            projectContents.contains("TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/VideoRecorderApp.app/Contents/MacOS/VideoRecorderApp\";"),
            "Stale VideoRecorderApp test-host paths break `xcodebuild test`."
        )
    }

    func testUnitTestsGenerateTheirOwnInfoPlist() throws {
        let projectContents = try projectContents()

        XCTAssertTrue(
            projectContents.contains("GENERATE_INFOPLIST_FILE = YES;"),
            "The Xcode test bundle needs an Info.plist to build and code sign."
        )
    }

    func testAppTargetUsesFrameMateModuleName() throws {
        let projectContents = try projectContents()

        XCTAssertTrue(
            projectContents.contains("PRODUCT_MODULE_NAME = FrameMate;"),
            "The Xcode target should expose the FrameMate module name consistently."
        )
    }

    func testProjectDoesNotResignDebugAppAfterBuildAction() throws {
        let schemeFileURL = try resourceURL(named: "FrameMate", withExtension: "xcscheme")
        let schemeContents = try String(contentsOf: schemeFileURL, encoding: .utf8)

        XCTAssertFalse(
            schemeContents.contains("Resign Debug App For Stable Privacy Permissions"),
            "The debug scheme should not trigger extra signing or keychain prompts during local permission testing."
        )
    }

    func testAppLifecycleUsesRegularActivationPolicy() throws {
        let sourceURL = try resourceURL(named: "VideoRecorderApp", withExtension: "txt")
        let sourceContents = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            sourceContents.contains("NSApplication.shared.setActivationPolicy(.regular)"),
            "The app should force regular activation before the UI scene is built so the menu bar and standard shortcuts appear reliably."
        )
    }

    func testProjectBundlesRecordingSoundEffects() throws {
        let projectContents = try projectContents()

        XCTAssertTrue(projectContents.contains("baslama.wav in Resources"))
        XCTAssertTrue(projectContents.contains("bitis.wav in Resources"))
        XCTAssertTrue(projectContents.contains("yeni-ses.wav in Resources"))
    }

    func testAppInfoPlistContainsMacAppStoreMetadata() throws {
        let plistURL = try resourceURL(named: "AppInfoFixture", withExtension: "plist")

        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["LSApplicationCategoryType"] as? String, "public.app-category.video")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(
            plist["FrameMateDisablePurchasesForInternalTesting"] as? Bool,
            false,
            "Store submissions must keep purchases enabled; the internal-testing bypass hides IAP from App Review and grants free Pro access."
        )
    }

    func testRuntimeInfoPlistKeepsPurchasesEnabledForStoreSubmissions() throws {
        let plistURL = repoRootURL()
            .appendingPathComponent("Resources")
            .appendingPathComponent("Info.plist")

        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            plist["FrameMateDisablePurchasesForInternalTesting"] as? Bool,
            false,
            "Store submissions must keep purchases enabled; flip this flag only on throwaway internal TestFlight branches."
        )
    }

    func testProjectBundlesAppIconIcns() throws {
        let projectContents = try projectContents()
        XCTAssertTrue(projectContents.contains("AppIcon.icns in Resources"))
    }

    func testSandboxEntitlementsAvoidUnsupportedScreenCaptureKey() throws {
        let entitlementsURL = try resourceURL(named: "VideoRecorder", withExtension: "entitlements")

        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: entitlementsData, format: nil) as? [String: Any]
        )

        XCTAssertNil(entitlements["com.apple.security.screen-capture"])
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
    }

    func testProjectBundlesStringCatalog() throws {
        let projectContents = try projectContents()
        XCTAssertTrue(projectContents.contains("Localizable.xcstrings in Resources"))
    }

    func testProjectBundlesPrivacyManifest() throws {
        let projectContents = try projectContents()
        XCTAssertTrue(projectContents.contains("PrivacyInfo.xcprivacy in Resources"))
    }

    func testPrivacyManifestDeclaresLocalOnlyAppBehaviorAndRequiredReasonAPIs() throws {
        let manifestURL = try resourceURL(named: "PrivacyInfo", withExtension: "xcprivacy")

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: manifestData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)

        let accessedAPITypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let declaredTypes = Set(accessedAPITypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })

        XCTAssertTrue(declaredTypes.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        XCTAssertTrue(declaredTypes.contains("NSPrivacyAccessedAPICategorySystemBootTime"))
        XCTAssertTrue(declaredTypes.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
    }

    func testFastlaneMetadataIncludesRequiredPrivacyAndSupportURLs() throws {
        for locale in ["tr", "en-US"] {
            let privacyURL = try String(
                contentsOf: try resourceURL(named: "fastlane-metadata-\(locale)-privacy-url", withExtension: "txt"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let supportURL = try String(
                contentsOf: try resourceURL(named: "fastlane-metadata-\(locale)-support-url", withExtension: "txt"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            XCTAssertTrue(privacyURL.hasPrefix("https://"))
            XCTAssertTrue(supportURL.hasPrefix("https://"))
            XCTAssertTrue(privacyURL.contains("framemate"))
            XCTAssertTrue(supportURL.contains("framemate"))
        }
    }

    func testProjectIncludesAppAccessManagerSource() throws {
        let projectContents = try projectContents()
        XCTAssertTrue(projectContents.contains("AppAccessManager.swift in Sources"))
    }

    func testReadmeDocumentsXcodeSchemeBuildAndTestCommands() throws {
        let readmeContents = try String(
            contentsOf: repoRootURL().appendingPathComponent("README.md"),
            encoding: .utf8
        )

        XCTAssertTrue(
            readmeContents.contains("xcodebuild build -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'"),
            "README should point contributors at the Xcode scheme-based build command."
        )
        XCTAssertTrue(
            readmeContents.contains("xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'"),
            "README should point contributors at the Xcode scheme-based test command."
        )
        XCTAssertFalse(
            readmeContents.contains("swift build"),
            "README should not recommend SwiftPM build commands for this Xcode project."
        )
        XCTAssertFalse(
            readmeContents.contains("swift test"),
            "README should not recommend SwiftPM test commands for this Xcode project."
        )
        XCTAssertFalse(
            readmeContents.contains("scripts/package-app.sh"),
            "README should not reference a packaging script that is not present in the repo."
        )
    }

    func testRepoAgentsGuidanceDocumentsCanonicalAutomationWorkflow() throws {
        let agentsContents = try String(
            contentsOf: repoRootURL().appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )

        XCTAssertTrue(
            agentsContents.contains("xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'"),
            "Repo guidance should define the canonical verification command."
        )
        XCTAssertTrue(
            agentsContents.contains("Do not treat old `swift test`, `swift build`, or `VideoRecorderApp` scheme references as canonical"),
            "Repo guidance should warn agents away from stale historical commands."
        )
        XCTAssertTrue(
            agentsContents.contains("Use Browser only"),
            "Repo guidance should explain when browser automation is appropriate."
        )
        XCTAssertTrue(
            agentsContents.contains("Use App Store Connect MCP"),
            "Repo guidance should route release facts through App Store Connect MCP."
        )
    }

    func testRepoCodexProjectConfigAndSkillsExist() {
        let repoRoot = repoRootURL()
        let requiredPaths = [
            ".codex/config.toml",
            ".agents/skills/xcode-smoke-check/SKILL.md",
            ".agents/skills/macos-release-readiness/SKILL.md",
            ".agents/skills/framemate-ui-check/SKILL.md",
        ]

        for relativePath in requiredPaths {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(relativePath).path),
                "Missing required Codex workflow file at \(relativePath)"
            )
        }
    }

    func testGeneratorCreatesCodexReadyMacOSStarterProject() throws {
        let repoRoot = repoRootURL()
        let scriptURL = repoRoot.appendingPathComponent("tools/create_macos_codex_starter.rb")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-starter-\(UUID().uuidString)", isDirectory: true)

        defer {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/ruby"),
            arguments: [
                scriptURL.path,
                "--name", "StarterDemo",
                "--display-name", "Starter Demo",
                "--bundle-id", "com.example.StarterDemo",
                "--output", outputURL.path,
            ],
            currentDirectoryURL: repoRoot
        )

        if result.timedOut {
            throw XCTSkip("Ruby generator process hung inside the sandboxed test host (environment flake); skipping instead of blocking the suite.")
        }

        XCTAssertEqual(result.exitCode, 0, "Generator failed: \(result.output)")

        let expectedFiles = [
            "AGENTS.md",
            ".codex/config.toml",
            ".agents/skills/xcode-smoke-check/SKILL.md",
            ".agents/skills/macos-release-readiness/SKILL.md",
            ".agents/skills/macos-app-ui-check/SKILL.md",
            "README.md",
            "project.yml",
            "fastlane/Appfile",
            "fastlane/Fastfile",
            "Resources/Info.plist",
            "Resources/PrivacyInfo.xcprivacy",
            "Sources/App/AppConfig.swift",
            "Sources/App/AppMain.swift",
            "Sources/App/ContentView.swift",
            "Tests/AppTests/AppSmokeTests.swift",
            "Tests/ProjectTests/WorkflowConfigurationTests.swift",
            "StarterDemo.xcodeproj/project.pbxproj",
        ]

        for relativePath in expectedFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputURL.appendingPathComponent(relativePath).path),
                "Missing generated file at \(relativePath)"
            )
        }

        let readmeContents = try String(
            contentsOf: outputURL.appendingPathComponent("README.md"),
            encoding: .utf8
        )
        XCTAssertTrue(readmeContents.contains("StarterDemo.xcodeproj"))
        XCTAssertTrue(readmeContents.contains("-scheme StarterDemo"))

        let agentsContents = try String(
            contentsOf: outputURL.appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )
        XCTAssertTrue(agentsContents.contains("xcodebuild test -project StarterDemo.xcodeproj -scheme StarterDemo"))
        XCTAssertTrue(agentsContents.contains("xcodegen generate"))
    }

    private var resourceBundle: Bundle {
        Bundle(for: Self.self)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func projectContents() throws -> String {
        try String(contentsOf: try resourceURL(named: "project", withExtension: "pbxproj"), encoding: .utf8)
    }

    private func resourceURL(named name: String, withExtension ext: String?) throws -> URL {
        try XCTUnwrap(
            resourceBundle.url(forResource: name, withExtension: ext),
            "Missing bundled resource \(name).\(ext ?? "")"
        )
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        timeout: TimeInterval = 120
    ) throws -> (exitCode: Int32, output: String, timedOut: Bool) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        // Spawned processes can hang indefinitely inside the sandboxed test host
        // (observed: ruby stuck in getcwd at interpreter startup). Never block the
        // whole suite on waitUntilExit without a deadline.
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()

        var timedOut = false
        if terminated.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if terminated.wait(timeout: .now() + 5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 5)
            }
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return (process.terminationStatus, output, timedOut)
    }
}
