import AVFoundation
import CoreGraphics
import XCTest
@testable import VideoRecorderApp

final class FrameCoachingEngineTests: XCTestCase {
    func testScenarioMatrixCoversCoreTalkingHeadCases() {
        let scenarios: [FramingScenario] = [
            .init(
                name: "single-horizontal-ideal",
                analysis: makeAnalysis(
                    faceBoxes: [CGRect(x: 0.42, y: 0.30, width: 0.16, height: 0.20)],
                    subjectCount: .one,
                    headroomRatio: 0.18,
                    bottomCoverageRatio: 0.22,
                    horizontalGroupCenter: 0.50,
                    spacingMetric: 0
                ),
                mode: .horizontal1080p,
                profile: .singleDeskSpeaker,
                expectedInstruction: "kadraj uygun"
            ),
            .init(
                name: "single-vertical-tight",
                analysis: makeAnalysis(
                    faceBoxes: [CGRect(x: 0.39, y: 0.30, width: 0.22, height: 0.28)],
                    subjectCount: .one,
                    headroomRatio: 0.30,
                    bottomCoverageRatio: 0.12,
                    horizontalGroupCenter: 0.50,
                    spacingMetric: 0
                ),
                mode: .vertical1080p,
                profile: .singleDeskSpeaker,
                expectedInstruction: "kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün"
            ),
            .init(
                name: "single-horizontal-low",
                analysis: makeAnalysis(
                    faceBoxes: [CGRect(x: 0.40, y: 0.54, width: 0.18, height: 0.22)],
                    subjectCount: .one,
                    headroomRatio: 0.08,
                    bottomCoverageRatio: 0.30,
                    horizontalGroupCenter: 0.50,
                    spacingMetric: 0
                ),
                mode: .horizontal1080p,
                profile: .singleDeskSpeaker,
                expectedInstruction: "kamerayı biraz yukarı al"
            ),
            .init(
                name: "single-horizontal-left",
                analysis: makeAnalysis(
                    faceBoxes: [CGRect(x: 0.14, y: 0.28, width: 0.18, height: 0.22)],
                    subjectCount: .one,
                    headroomRatio: 0.18,
                    bottomCoverageRatio: 0.22,
                    horizontalGroupCenter: 0.28,
                    spacingMetric: 0
                ),
                mode: .horizontal1080p,
                profile: .singleDeskSpeaker,
                expectedInstruction: "biraz sağa geç"
            ),
            .init(
                name: "single-horizontal-far",
                analysis: makeAnalysis(
                    faceBoxes: [CGRect(x: 0.44, y: 0.32, width: 0.09, height: 0.12)],
                    subjectCount: .one,
                    headroomRatio: 0.32,
                    bottomCoverageRatio: 0.20,
                    horizontalGroupCenter: 0.485,
                    spacingMetric: 0
                ),
                mode: .horizontal1080p,
                profile: .singleDeskSpeaker,
                expectedInstruction: "kadraj çok uzak, biraz yaklaş"
            ),
            .init(
                name: "single-vertical-good",
                analysis: makeAnalysis(
                    faceBoxes: [CGRect(x: 0.41, y: 0.31, width: 0.18, height: 0.23)],
                    subjectCount: .one,
                    headroomRatio: 0.28,
                    bottomCoverageRatio: 0.16,
                    horizontalGroupCenter: 0.50,
                    spacingMetric: 0
                ),
                mode: .vertical1080p,
                profile: .verticalSocialVideo,
                expectedInstruction: "kadraj uygun"
            ),
            .init(
                name: "two-person-balanced",
                analysis: makeAnalysis(
                    faceBoxes: [
                        CGRect(x: 0.24, y: 0.30, width: 0.16, height: 0.20),
                        CGRect(x: 0.56, y: 0.30, width: 0.16, height: 0.20)
                    ],
                    subjectCount: .two,
                    headroomRatio: 0.18,
                    bottomCoverageRatio: 0.22,
                    horizontalGroupCenter: 0.48,
                    spacingMetric: 0.32
                ),
                mode: .horizontal1080p,
                profile: .twoPersonPodcast,
                expectedInstruction: "kadraj dengeli"
            ),
            .init(
                name: "two-person-scale-imbalance",
                analysis: makeAnalysis(
                    faceBoxes: [
                        CGRect(x: 0.20, y: 0.25, width: 0.23, height: 0.30),
                        CGRect(x: 0.60, y: 0.29, width: 0.12, height: 0.18)
                    ],
                    subjectCount: .two,
                    headroomRatio: 0.22,
                    bottomCoverageRatio: 0.34,
                    horizontalGroupCenter: 0.46,
                    spacingMetric: 0.29
                ),
                mode: .horizontal1080p,
                profile: .twoPersonPodcast,
                expectedInstruction: "soldaki kişi kameraya daha yakın, biraz geri gelsin"
            ),
            .init(
                name: "two-person-overlap",
                analysis: makeAnalysis(
                    faceBoxes: [
                        CGRect(x: 0.36, y: 0.25, width: 0.18, height: 0.24),
                        CGRect(x: 0.44, y: 0.27, width: 0.12, height: 0.18)
                    ],
                    subjectCount: .two,
                    headroomRatio: 0.24,
                    bottomCoverageRatio: 0.28,
                    horizontalGroupCenter: 0.46,
                    spacingMetric: 0.08
                ),
                mode: .horizontal1080p,
                profile: .twoPersonPodcast,
                expectedInstruction: "sağdaki kişi arkada kalmış, biraz yana açılsın"
            ),
            .init(
                name: "two-person-right-low",
                analysis: makeAnalysis(
                    faceBoxes: [
                        CGRect(x: 0.24, y: 0.26, width: 0.16, height: 0.20),
                        CGRect(x: 0.56, y: 0.56, width: 0.16, height: 0.20)
                    ],
                    subjectCount: .two,
                    headroomRatio: 0.18,
                    bottomCoverageRatio: 0.24,
                    horizontalGroupCenter: 0.48,
                    spacingMetric: 0.32
                ),
                mode: .horizontal1080p,
                profile: .twoPersonPodcast,
                expectedInstruction: "sağdaki kişi kadrajda çok aşağıda, biraz yukarı otursun"
            ),
            .init(
                name: "two-person-off-center",
                analysis: makeAnalysis(
                    faceBoxes: [
                        CGRect(x: 0.50, y: 0.30, width: 0.14, height: 0.18),
                        CGRect(x: 0.68, y: 0.31, width: 0.14, height: 0.18)
                    ],
                    subjectCount: .two,
                    headroomRatio: 0.16,
                    bottomCoverageRatio: 0.24,
                    horizontalGroupCenter: 0.60,
                    spacingMetric: 0.42
                ),
                mode: .horizontal1080p,
                profile: .twoPersonPodcast,
                expectedInstruction: "grup biraz sağda kalmış, biraz sola kayın"
            ),
            .init(
                name: "two-person-too-wide",
                analysis: makeAnalysis(
                    faceBoxes: [
                        CGRect(x: 0.08, y: 0.29, width: 0.13, height: 0.18),
                        CGRect(x: 0.73, y: 0.30, width: 0.13, height: 0.18)
                    ],
                    subjectCount: .two,
                    headroomRatio: 0.20,
                    bottomCoverageRatio: 0.24,
                    horizontalGroupCenter: 0.47,
                    spacingMetric: 0.78
                ),
                mode: .horizontal1080p,
                profile: .twoPersonPodcast,
                expectedInstruction: "aranız çok açık, birbirinize biraz yaklaşın"
            )
        ]

        let engine = FrameCoachingEngine()

        for scenario in scenarios {
            XCTAssertEqual(
                engine.instruction(for: scenario.analysis, mode: scenario.mode, profile: scenario.profile),
                scenario.expectedInstruction,
                scenario.name
            )
        }
    }

    func testOneCenteredPersonWithGoodFramingKeepsCoachQuiet() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.42, y: 0.30, width: 0.16, height: 0.20))
            ],
            subjectCount: .one,
            headroomRatio: 0.18,
            bottomCoverageRatio: 0.22,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.0,
            confidence: 0.95
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kadraj uygun"
        )
    }

    func testOnePersonSlightlyOffCenterStillCountsAsAcceptable() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.33, y: 0.30, width: 0.17, height: 0.21))
            ],
            subjectCount: .one,
            headroomRatio: 0.18,
            bottomCoverageRatio: 0.22,
            horizontalGroupCenter: 0.415,
            spacingMetric: 0.0,
            confidence: 0.95
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kadraj uygun"
        )
    }

    func testOnePersonTooLowRequestsCameraUp() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.54, width: 0.18, height: 0.22))
            ],
            subjectCount: .one,
            headroomRatio: 0.08,
            bottomCoverageRatio: 0.30,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.0,
            confidence: 0.94
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kamerayı biraz yukarı al"
        )
    }

    func testOnePersonTooHighRequestsCameraDown() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.12, width: 0.18, height: 0.22))
            ],
            subjectCount: .one,
            headroomRatio: 0.34,
            bottomCoverageRatio: 0.08,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.0,
            confidence: 0.94
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kamerayı biraz aşağı indir"
        )
    }

    func testOnePersonLeftOfCenterRequestsMoveRight() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.14, y: 0.28, width: 0.18, height: 0.22))
            ],
            subjectCount: .one,
            headroomRatio: 0.18,
            bottomCoverageRatio: 0.22,
            horizontalGroupCenter: 0.28,
            spacingMetric: 0.0,
            confidence: 0.93
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "biraz sağa geç"
        )
    }

    func testOnePersonWithTooMuchBottomSpaceRequestsCameraUp() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.36, width: 0.18, height: 0.22))
            ],
            subjectCount: .one,
            headroomRatio: 0.10,
            bottomCoverageRatio: 0.46,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.0,
            confidence: 0.93
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kamerayı biraz yukarı al"
        )
    }

    func testOnePersonWithModerateBottomSpaceStillCountsAsAcceptable() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.33, width: 0.18, height: 0.22))
            ],
            subjectCount: .one,
            headroomRatio: 0.12,
            bottomCoverageRatio: 0.43,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.0,
            confidence: 0.93
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kadraj uygun"
        )
    }

    func testOnePersonWithTooMuchTopSpaceRequestsCameraDown() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.10, width: 0.18, height: 0.22))
            ],
            subjectCount: .one,
            headroomRatio: 0.44,
            bottomCoverageRatio: 0.10,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.0,
            confidence: 0.93
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kamerayı biraz aşağı indir"
        )
    }

    func testOnePersonWithModerateTopSpaceStillCountsAsAcceptable() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.19, width: 0.18, height: 0.22))
            ],
            subjectCount: .one,
            headroomRatio: 0.41,
            bottomCoverageRatio: 0.12,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.0,
            confidence: 0.93
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kadraj uygun"
        )
    }

    func testTwoPeopleOffCenterRequestsMoveLeftAsGroup() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.50, y: 0.30, width: 0.14, height: 0.18)),
                NormalizedFaceBox(rect: CGRect(x: 0.68, y: 0.31, width: 0.14, height: 0.18))
            ],
            subjectCount: .two,
            headroomRatio: 0.16,
            bottomCoverageRatio: 0.24,
            horizontalGroupCenter: 0.60,
            spacingMetric: 0.42,
            confidence: 0.92
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "grup biraz sağda kalmış, biraz sola kayın"
        )
    }

    func testTwoPeopleWhenLeftPersonIsCutOffNamesLeftPerson() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: -0.03, y: 0.28, width: 0.18, height: 0.22)),
                NormalizedFaceBox(rect: CGRect(x: 0.42, y: 0.30, width: 0.18, height: 0.22))
            ],
            subjectCount: .two,
            headroomRatio: 0.18,
            bottomCoverageRatio: 0.20,
            horizontalGroupCenter: 0.28,
            spacingMetric: 0.45,
            confidence: 0.95
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "soldaki kişi kadraja tam girmiyor, biraz sağa gelsin"
        )
    }

    func testTwoPeopleWhenRightPersonIsTooLowNamesRightPerson() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.24, y: 0.26, width: 0.16, height: 0.20)),
                NormalizedFaceBox(rect: CGRect(x: 0.56, y: 0.56, width: 0.16, height: 0.20))
            ],
            subjectCount: .two,
            headroomRatio: 0.18,
            bottomCoverageRatio: 0.24,
            horizontalGroupCenter: 0.48,
            spacingMetric: 0.32,
            confidence: 0.94
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "sağdaki kişi kadrajda çok aşağıda, biraz yukarı otursun"
        )
    }

    func testThreePeopleTooWideRequestsTighterGroup() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.10, y: 0.28, width: 0.12, height: 0.16)),
                NormalizedFaceBox(rect: CGRect(x: 0.44, y: 0.27, width: 0.12, height: 0.16)),
                NormalizedFaceBox(rect: CGRect(x: 0.78, y: 0.29, width: 0.12, height: 0.16))
            ],
            subjectCount: .three,
            headroomRatio: 0.17,
            bottomCoverageRatio: 0.20,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.88,
            confidence: 0.91
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "grup çok açılmış, birbirinize biraz yaklaşın"
        )
    }

    func testThreePeopleGoodFramingReportsBalancedGroup() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.16, y: 0.26, width: 0.14, height: 0.18)),
                NormalizedFaceBox(rect: CGRect(x: 0.43, y: 0.25, width: 0.14, height: 0.18)),
                NormalizedFaceBox(rect: CGRect(x: 0.70, y: 0.27, width: 0.14, height: 0.18))
            ],
            subjectCount: .three,
            headroomRatio: 0.17,
            bottomCoverageRatio: 0.23,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.27,
            confidence: 0.96
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "kadraj dengeli"
        )
    }

    func testSameSinglePersonIsAcceptableInHorizontalButTooTightInVertical() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.385, y: 0.28, width: 0.23, height: 0.29))
            ],
            subjectCount: .one,
            headroomRatio: 0.28,
            bottomCoverageRatio: 0.12,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.0,
            confidence: 0.95
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kadraj uygun"
        )
        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .verticalSocialVideo),
            "kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün"
        )
    }

    func testTwoPeopleWithScaleImbalanceAskCloserPersonToMoveBack() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.20, y: 0.25, width: 0.23, height: 0.30)),
                NormalizedFaceBox(rect: CGRect(x: 0.60, y: 0.29, width: 0.12, height: 0.18))
            ],
            subjectCount: .two,
            headroomRatio: 0.22,
            bottomCoverageRatio: 0.34,
            horizontalGroupCenter: 0.46,
            spacingMetric: 0.29,
            confidence: 0.95
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "soldaki kişi kameraya daha yakın, biraz geri gelsin"
        )
    }

    func testTwoPeopleWhenOnePersonIsHiddenBehindTheOtherAskThemToSeparate() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.36, y: 0.25, width: 0.18, height: 0.24)),
                NormalizedFaceBox(rect: CGRect(x: 0.44, y: 0.27, width: 0.12, height: 0.18))
            ],
            subjectCount: .two,
            headroomRatio: 0.24,
            bottomCoverageRatio: 0.28,
            horizontalGroupCenter: 0.46,
            spacingMetric: 0.08,
            confidence: 0.95
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "sağdaki kişi arkada kalmış, biraz yana açılsın"
        )
    }

    func testVerticalSocialVideoAcceptsTighterSinglePersonThanDeskProfile() {
        let analysis = makeAnalysis(
            faceBoxes: [CGRect(x: 0.40, y: 0.30, width: 0.21, height: 0.27)],
            subjectCount: .one,
            headroomRatio: 0.28,
            bottomCoverageRatio: 0.13,
            horizontalGroupCenter: 0.505,
            spacingMetric: 0
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .singleDeskSpeaker),
            "kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün"
        )
        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .verticalSocialVideo),
            "kadraj uygun"
        )
    }

    func testVerticalSocialVideoAllowsABitMoreBottomRoomBeforeWarning() {
        let analysis = makeAnalysis(
            faceBoxes: [CGRect(x: 0.40, y: 0.25, width: 0.20, height: 0.26)],
            subjectCount: .one,
            headroomRatio: 0.30,
            bottomCoverageRatio: 0.63,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .verticalSocialVideo),
            "kadraj uygun"
        )
    }

    func testVerticalSocialVideoKeepsQuietForModeratelyCloseCenteredShot() {
        let analysis = makeAnalysis(
            faceBoxes: [CGRect(x: 0.39, y: 0.24, width: 0.24, height: 0.14)],
            subjectCount: .one,
            headroomRatio: 0.24,
            bottomCoverageRatio: 0.62,
            horizontalGroupCenter: 0.51,
            spacingMetric: 0
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .verticalSocialVideo),
            "kadraj uygun"
        )
    }

    func testVerticalSocialVideoPrefersHorizontalCorrectionBeforeMildDistanceWarning() {
        let analysis = makeAnalysis(
            faceBoxes: [CGRect(x: 0.63, y: 0.24, width: 0.24, height: 0.14)],
            subjectCount: .one,
            headroomRatio: 0.24,
            bottomCoverageRatio: 0.62,
            horizontalGroupCenter: 0.75,
            spacingMetric: 0
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .verticalSocialVideo),
            "biraz sola geç"
        )
    }

    func testVerticalDeskSpeakerAllowsSlightlyTightFramingBeforeWarning() {
        let analysis = makeAnalysis(
            faceBoxes: [CGRect(x: 0.40, y: 0.31, width: 0.21, height: 0.26)],
            subjectCount: .one,
            headroomRatio: 0.29,
            bottomCoverageRatio: 0.14,
            horizontalGroupCenter: 0.505,
            spacingMetric: 0
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .singleDeskSpeaker),
            "kadraj uygun"
        )
    }

    func testTwoPersonPodcastProfileRejectsSpacingThatSingleDeskProfileWouldTolerate() {
        let analysis = makeAnalysis(
            faceBoxes: [
                CGRect(x: 0.18, y: 0.29, width: 0.14, height: 0.18),
                CGRect(x: 0.63, y: 0.30, width: 0.14, height: 0.18)
            ],
            subjectCount: .two,
            headroomRatio: 0.20,
            bottomCoverageRatio: 0.24,
            horizontalGroupCenter: 0.475,
            spacingMetric: 0.45
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kadraj dengeli"
        )
        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "aranız biraz açık, birbirinize yaklaşın"
        )
    }

    func testTwoPersonPodcastAllowsSlightlyFartherBalancedPair() {
        let analysis = makeAnalysis(
            faceBoxes: [
                CGRect(x: 0.29, y: 0.30, width: 0.079, height: 0.11),
                CGRect(x: 0.57, y: 0.30, width: 0.079, height: 0.11)
            ],
            subjectCount: .two,
            headroomRatio: 0.20,
            bottomCoverageRatio: 0.20,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.28
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "kadraj dengeli"
        )
    }

    func testVerticalConversationProfileIsStricterThanHorizontalPodcastForTwoPeople() {
        let analysis = makeAnalysis(
            faceBoxes: [
                CGRect(x: 0.22, y: 0.29, width: 0.14, height: 0.18),
                CGRect(x: 0.62, y: 0.30, width: 0.14, height: 0.18)
            ],
            subjectCount: .two,
            headroomRatio: 0.20,
            bottomCoverageRatio: 0.24,
            horizontalGroupCenter: 0.49,
            spacingMetric: 0.40
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .twoPersonPodcast),
            "kadraj dengeli"
        )
        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .verticalConversation),
            "aranız biraz açık, birbirinize yaklaşın"
        )
    }

    func testVerticalConversationAllowsModerateTopSpaceWhenPairIsBalanced() {
        let analysis = makeAnalysis(
            faceBoxes: [
                CGRect(x: 0.25, y: 0.17, width: 0.15, height: 0.19),
                CGRect(x: 0.60, y: 0.18, width: 0.15, height: 0.19)
            ],
            subjectCount: .two,
            headroomRatio: 0.51,
            bottomCoverageRatio: 0.20,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0.34
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .vertical1080p, profile: .verticalConversation),
            "kadraj dengeli"
        )
    }

    func testScreenGuideProfileAllowsMoreHeadroomThanDeskSpeaker() {
        let analysis = makeAnalysis(
            faceBoxes: [CGRect(x: 0.40, y: 0.17, width: 0.18, height: 0.22)],
            subjectCount: .one,
            headroomRatio: 0.43,
            bottomCoverageRatio: 0.12,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .singleDeskSpeaker),
            "kamerayı biraz aşağı indir"
        )
        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .screenGuide),
            "kadraj uygun"
        )
    }

    func testScreenGuideAcceptsSmallerPresenterWindow() {
        let analysis = makeAnalysis(
            faceBoxes: [CGRect(x: 0.45, y: 0.28, width: 0.085, height: 0.12)],
            subjectCount: .one,
            headroomRatio: 0.26,
            bottomCoverageRatio: 0.16,
            horizontalGroupCenter: 0.492,
            spacingMetric: 0
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .screenGuide),
            "kadraj uygun"
        )
    }

    func testScreenGuidePrefersRecenteringBeforeAskingPresenterToMoveCloser() {
        let analysis = makeAnalysis(
            faceBoxes: [CGRect(x: 0.72, y: 0.28, width: 0.082, height: 0.11)],
            subjectCount: .one,
            headroomRatio: 0.24,
            bottomCoverageRatio: 0.17,
            horizontalGroupCenter: 0.761,
            spacingMetric: 0
        )

        XCTAssertEqual(
            FrameCoachingEngine().instruction(for: analysis, mode: .horizontal1080p, profile: .screenGuide),
            "biraz sola geç"
        )
    }
}

private struct FramingScenario {
    let name: String
    let analysis: FrameAnalysis
    let mode: RecordingMode
    let profile: FrameCoachingProfile
    let expectedInstruction: String
}

private func makeAnalysis(
    faceBoxes: [CGRect],
    subjectCount: FrameSubjectCount,
    headroomRatio: Double,
    bottomCoverageRatio: Double,
    horizontalGroupCenter: Double,
    spacingMetric: Double,
    confidence: Double = 0.95
) -> FrameAnalysis {
    FrameAnalysis(
        faceBoxes: faceBoxes.map(NormalizedFaceBox.init(rect:)),
        subjectCount: subjectCount,
        headroomRatio: headroomRatio,
        bottomCoverageRatio: bottomCoverageRatio,
        horizontalGroupCenter: horizontalGroupCenter,
        spacingMetric: spacingMetric,
        confidence: confidence
    )
}
