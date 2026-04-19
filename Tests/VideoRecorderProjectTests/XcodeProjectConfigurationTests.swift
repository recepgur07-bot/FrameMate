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

    func testAppEntitlementsAllowHardenedRuntimeMicrophoneInput() throws {
        let entitlementsURL = try resourceURL(named: "VideoRecorder", withExtension: "entitlements")

        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: entitlementsData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(entitlements["com.apple.security.device.audio-input"] as? Bool, true)
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

    private var resourceBundle: Bundle {
        Bundle(for: Self.self)
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
}
