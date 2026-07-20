import XCTest

final class WorkflowConfigurationTests: XCTestCase {
    func testReadmeUsesCanonicalXcodeCommands() throws {
        let readmeContents = try String(
            contentsOf: repoRootURL().appendingPathComponent("README.md"),
            encoding: .utf8
        )

        XCTAssertTrue(
            readmeContents.contains("xcodebuild build -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'")
        )
        XCTAssertTrue(
            readmeContents.contains("xcodebuild test -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'")
        )
        XCTAssertTrue(readmeContents.contains("xcodegen generate"))
        XCTAssertFalse(readmeContents.contains("swift build"))
        XCTAssertFalse(readmeContents.contains("swift test"))
    }

    func testAgentsGuidanceDocumentsCanonicalWorkflow() throws {
        let agentsContents = try String(
            contentsOf: repoRootURL().appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )

        XCTAssertTrue(agentsContents.contains("xcodebuild test -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__"))
        XCTAssertTrue(agentsContents.contains("xcodegen generate"))
        XCTAssertTrue(agentsContents.contains("Use Browser only"))
        XCTAssertTrue(agentsContents.contains("Use App Store Connect MCP"))
    }

    func testCodexFilesAndGeneratedProjectExist() {
        let repoRoot = repoRootURL()
        let requiredPaths = [
            ".codex/config.toml",
            ".agents/skills/xcode-smoke-check/SKILL.md",
            ".agents/skills/macos-release-readiness/SKILL.md",
            ".agents/skills/macos-app-ui-check/SKILL.md",
            "__MODULE_NAME__.xcodeproj/project.pbxproj",
        ]

        for relativePath in requiredPaths {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(relativePath).path),
                "Missing required file at \(relativePath)"
            )
        }
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
