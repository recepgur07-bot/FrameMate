import XCTest

final class XcodeProjectConfigurationTests: XCTestCase {
    func testInfoPlistContainsCameraAndMicrophoneUsageDescriptions() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")

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

    func testUnitTestsUseBuiltVideoRecorderAppAsTestHost() throws {
        let projectFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.xcodeproj/project.pbxproj")

        let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

        XCTAssertTrue(
            projectContents.contains("TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/VideoRecorder.app/Contents/MacOS/VideoRecorder\";"),
            "Xcode unit tests should point to the built VideoRecorder app bundle."
        )
        XCTAssertFalse(
            projectContents.contains("TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/VideoRecorderApp.app/Contents/MacOS/VideoRecorderApp\";"),
            "Stale VideoRecorderApp test-host paths break `xcodebuild test`."
        )
    }

    func testUnitTestsGenerateTheirOwnInfoPlist() throws {
        let projectFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.xcodeproj/project.pbxproj")

        let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

        XCTAssertTrue(
            projectContents.contains("GENERATE_INFOPLIST_FILE = YES;"),
            "The Xcode test bundle needs an Info.plist to build and code sign."
        )
    }

    func testAppTargetKeepsVideoRecorderAppModuleName() throws {
        let projectFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.xcodeproj/project.pbxproj")

        let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

        XCTAssertTrue(
            projectContents.contains("PRODUCT_MODULE_NAME = VideoRecorderApp;"),
            "The Xcode target should expose the same module name as the Swift package target."
        )
    }

    func testProjectResignsDebugAppAfterBuildAction() throws {
        let schemeFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.xcodeproj/xcshareddata/xcschemes/VideoRecorderApp.xcscheme")

        let schemeContents = try String(contentsOf: schemeFileURL, encoding: .utf8)

        XCTAssertTrue(
            schemeContents.contains("Resign Debug App For Stable Privacy Permissions"),
            "The generated scheme should re-sign the debug app after the build action completes."
        )
        XCTAssertTrue(
            schemeContents.contains("Apple Development:"),
            "The scheme post-action should look for an Apple Development signing identity."
        )
    }

    func testAppLifecycleUsesRegularActivationPolicy() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VideoRecorderApp/VideoRecorderApp.swift")

        let sourceContents = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            sourceContents.contains("NSApplication.shared.setActivationPolicy(.regular)"),
            "The app should force regular activation before the UI scene is built so the menu bar and standard shortcuts appear reliably."
        )
    }

    func testProjectBundlesRecordingSoundEffects() throws {
        let projectFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.xcodeproj/project.pbxproj")

        let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

        XCTAssertTrue(
            projectContents.contains("baslama.wav in Resources"),
            "The recording start sound should be copied into the app bundle."
        )
        XCTAssertTrue(
            projectContents.contains("bitis.wav in Resources"),
            "The recording stop sound should be copied into the app bundle."
        )
        XCTAssertTrue(
            projectContents.contains("yeni-ses.wav in Resources"),
            "The shorter pause/resume sound should be copied into the app bundle."
        )
    }

    func testAppInfoPlistContainsMacAppStoreMetadata() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")

        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            plist["LSApplicationCategoryType"] as? String,
            "public.app-category.video",
            "The app should declare a valid Mac App Store category."
        )
        XCTAssertEqual(
            plist["CFBundleIconFile"] as? String,
            "AppIcon",
            "The app should declare the bundled ICNS icon file."
        )
    }

    func testProjectBundlesAppIconIcns() throws {
        let projectFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.xcodeproj/project.pbxproj")

        let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

        XCTAssertTrue(
            projectContents.contains("AppIcon.icns in Resources"),
            "The macOS app icon should be copied into the app bundle."
        )
    }

    func testSandboxEntitlementsAvoidUnsupportedScreenCaptureKey() throws {
        let entitlementsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.entitlements")

        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: entitlementsData, format: nil) as? [String: Any]
        )

        XCTAssertNil(
            entitlements["com.apple.security.screen-capture"],
            "ScreenCaptureKit should rely on the system permission prompt instead of an unsupported App Sandbox entitlement."
        )
        XCTAssertEqual(
            entitlements["com.apple.security.app-sandbox"] as? Bool,
            true,
            "The Mac App Store build should remain sandboxed."
        )
    }

    func testProjectBundlesStringCatalog() throws {
        let projectFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.xcodeproj/project.pbxproj")

        let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

        XCTAssertTrue(
            projectContents.contains("Localizable.xcstrings in Resources"),
            "The English string catalog should be copied into the app bundle."
        )
    }

    func testProjectIncludesAppAccessManagerSource() throws {
        let projectFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VideoRecorder.xcodeproj/project.pbxproj")

        let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

        XCTAssertTrue(
            projectContents.contains("AppAccessManager.swift in Sources"),
            "The trial and purchase access manager should be compiled into the app target."
        )
    }
}
