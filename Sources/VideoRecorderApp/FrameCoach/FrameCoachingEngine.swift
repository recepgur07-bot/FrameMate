import Foundation

final class FrameCoachingEngine {
    private enum DistanceSeverity {
        case severe
        case advisory
    }

    func instruction(
        for analysis: FrameAnalysis,
        mode: RecordingMode,
        profile: FrameCoachingProfile = .singleDeskSpeaker
    ) -> String {
        guard analysis.confidence > 0.3, analysis.faceCount > 0 else {
            return String(localized: "Yüz algılanamıyor, kameraya bak")
        }

        if let clippedMessage = clippedSubjectInstruction(in: analysis) {
            return clippedMessage
        }

        if let overlapMessage = overlapInstruction(in: analysis) {
            return overlapMessage
        }

        if let scaleImbalanceMessage = scaleImbalanceInstruction(in: analysis) {
            return scaleImbalanceMessage
        }

        if let distanceMessage = distanceInstruction(
            in: analysis,
            mode: mode,
            profile: profile,
            severity: .severe
        ) {
            return distanceMessage
        }

        if let spacingMessage = spacingInstruction(in: analysis, profile: profile) {
            return spacingMessage
        }

        if let verticalSubjectMessage = individualVerticalInstruction(in: analysis) {
            return verticalSubjectMessage
        }

        if let topBottomMessage = topBottomSpacingInstruction(in: analysis, mode: mode, profile: profile) {
            return topBottomMessage
        }

        if let groupVerticalMessage = groupVerticalInstruction(in: analysis) {
            return groupVerticalMessage
        }

        if let horizontalMessage = groupHorizontalInstruction(in: analysis) {
            return horizontalMessage
        }

        if let distanceMessage = distanceInstruction(
            in: analysis,
            mode: mode,
            profile: profile,
            severity: .advisory
        ) {
            return distanceMessage
        }

        return balancedInstruction(for: analysis.subjectCount)
    }

    func subjectCountAnnouncement(for count: FrameSubjectCount) -> String {
        switch count {
        case .one:
            return String(localized: "Bir kişi görünüyor")
        case .two:
            return String(localized: "İki kişi görünüyor")
        case .three:
            return String(localized: "Üç kişi görünüyor")
        }
    }

    private func balancedInstruction(for count: FrameSubjectCount) -> String {
        switch count {
        case .one:
            return String(localized: "kadraj uygun")
        case .two, .three:
            return String(localized: "kadraj dengeli")
        }
    }

    private func clippedSubjectInstruction(in analysis: FrameAnalysis) -> String? {
        for subject in analysis.subjects {
            if subject.faceBox.minX < 0.02 {
                if analysis.subjectCount == .one {
                    return String(localized: "Kadraja tam girmiyorsun, biraz sağa gel")
                }
                return String(localized: "\(subject.role.label) kadraja tam girmiyor, biraz sağa gelsin")
            }

            if subject.faceBox.maxX > 0.98 {
                if analysis.subjectCount == .one {
                    return String(localized: "Kadraja tam girmiyorsun, biraz sola gel")
                }
                return String(localized: "\(subject.role.label) kadraja tam girmiyor, biraz sola gelsin")
            }
        }

        return nil
    }

    private func overlapInstruction(in analysis: FrameAnalysis) -> String? {
        guard analysis.subjectCount == .two,
              analysis.overlapRatio >= 0.45,
              let smallestSubject = analysis.subjects.min(by: { $0.faceBox.width < $1.faceBox.width }) else {
            return nil
        }

        return String(localized: "\(smallestSubject.role.label) arkada kalmış, biraz yana açılsın")
    }

    private func scaleImbalanceInstruction(in analysis: FrameAnalysis) -> String? {
        guard analysis.subjectCount == .two,
              let widthRatio = analysis.faceWidthRatio,
              widthRatio >= 1.90,
              let largestSubject = analysis.subjects.max(by: { $0.faceBox.width < $1.faceBox.width }) else {
            return nil
        }

        return String(localized: "\(largestSubject.role.label) kameraya daha yakın, biraz geri gelsin")
    }

    private func distanceInstruction(
        in analysis: FrameAnalysis,
        mode: RecordingMode,
        profile: FrameCoachingProfile,
        severity: DistanceSeverity
    ) -> String? {
        guard let averageFaceWidth = analysis.averageFaceWidth,
              let averageFaceHeight = analysis.averageFaceHeight else { return nil }

        switch analysis.subjectCount {
        case .one:
            let severeWidthThreshold: Double
            let severeHeightThreshold: Double
            let advisoryWidthThreshold: Double?
            let advisoryHeightThreshold: Double?
            let farThreshold: Double

            switch profile {
            case .singleDeskSpeaker:
                severeWidthThreshold = mode == .vertical1080p ? 0.225 : 0.29
                severeHeightThreshold = mode == .vertical1080p ? 0.275 : 0.38
                advisoryWidthThreshold = nil
                advisoryHeightThreshold = nil
                farThreshold = 0.095
            case .verticalSocialVideo:
                severeWidthThreshold = mode == .vertical1080p ? 0.265 : 0.29
                severeHeightThreshold = mode == .vertical1080p ? 0.305 : 0.38
                advisoryWidthThreshold = nil
                advisoryHeightThreshold = nil
                farThreshold = 0.075
            case .twoPersonPodcast, .verticalConversation:
                severeWidthThreshold = mode == .vertical1080p ? 0.245 : 0.29
                severeHeightThreshold = mode == .vertical1080p ? 0.30 : 0.38
                advisoryWidthThreshold = nil
                advisoryHeightThreshold = nil
                farThreshold = 0.075
            case .screenGuide:
                severeWidthThreshold = mode == .vertical1080p ? 0.29 : 0.31
                severeHeightThreshold = mode == .vertical1080p ? 0.355 : 0.40
                advisoryWidthThreshold = nil
                advisoryHeightThreshold = nil
                farThreshold = 0.065
            }

            if severity == .severe,
               (averageFaceWidth > severeWidthThreshold || averageFaceHeight > severeHeightThreshold) {
                return String(localized: "kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün")
            }

            if severity == .advisory,
               let advisoryWidthThreshold,
               let advisoryHeightThreshold,
               (averageFaceWidth > advisoryWidthThreshold || averageFaceHeight > advisoryHeightThreshold) {
                return String(localized: "kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün")
            }

            if severity == .severe, averageFaceWidth < farThreshold {
                return String(localized: "kadraj çok uzak, biraz yaklaş")
            }
        case .two:
            let farThreshold: Double

            switch profile {
            case .twoPersonPodcast:
                farThreshold = 0.060
            case .verticalConversation:
                farThreshold = 0.062
            default:
                farThreshold = 0.065
            }

            if severity == .severe, averageFaceWidth < farThreshold {
                return String(localized: "Çok uzaktasınız, ikiniz de biraz yaklaşın")
            }
        case .three:
            if severity == .severe, averageFaceWidth < 0.055 {
                return String(localized: "Çok uzaktasınız, hepiniz biraz yaklaşın")
            }
        }

        return nil
    }

    private func spacingInstruction(in analysis: FrameAnalysis, profile: FrameCoachingProfile) -> String? {
        if profile == .twoPersonPodcast,
           analysis.subjectCount == .two,
           analysis.spacingMetric >= 0.44,
           abs(analysis.groupCenterX - 0.5) <= 0.06,
           analysis.spacingMetric < 0.75 {
            return String(localized: "aranız biraz açık, birbirinize yaklaşın")
        }

        if profile == .verticalConversation,
           analysis.subjectCount == .two,
           analysis.spacingMetric >= 0.40,
           abs(analysis.groupCenterX - 0.5) <= 0.07,
           analysis.spacingMetric < 0.75 {
            return String(localized: "aranız biraz açık, birbirinize yaklaşın")
        }

        guard analysis.spacingMetric >= 0.75 else { return nil }

        switch analysis.subjectCount {
        case .one:
            return nil
        case .two:
            return String(localized: "aranız çok açık, birbirinize biraz yaklaşın")
        case .three:
            return String(localized: "grup çok açılmış, birbirinize biraz yaklaşın")
        }
    }

    private func individualVerticalInstruction(in analysis: FrameAnalysis) -> String? {
        guard analysis.subjectCount != .one else { return nil }

        let averageCenterY = analysis.subjects
            .map(\.faceBox.centerY)
            .reduce(0, +) / Double(analysis.subjects.count)

        for subject in analysis.subjects {
            let delta = subject.faceBox.centerY - averageCenterY
            if delta > 0.14 {
                return String(localized: "\(subject.role.label) kadrajda çok aşağıda, biraz yukarı otursun")
            }
        }

        for subject in analysis.subjects {
            let delta = subject.faceBox.centerY - averageCenterY
            if delta < -0.14 {
                return String(localized: "\(subject.role.label) kadrajda çok yukarıda, biraz aşağı otursun")
            }
        }

        return nil
    }

    private func topBottomSpacingInstruction(
        in analysis: FrameAnalysis,
        mode: RecordingMode,
        profile: FrameCoachingProfile
    ) -> String? {
        let bottomThreshold: Double
        let topThreshold: Double

        switch profile {
        case .singleDeskSpeaker, .twoPersonPodcast:
            bottomThreshold = mode == .vertical1080p ? 0.62 : 0.45
            topThreshold = mode == .vertical1080p ? 0.56 : 0.42
        case .verticalSocialVideo:
            bottomThreshold = mode == .vertical1080p ? 0.70 : 0.50
            topThreshold = mode == .vertical1080p ? 0.60 : 0.50
        case .verticalConversation:
            bottomThreshold = mode == .vertical1080p ? 0.67 : 0.55
            topThreshold = mode == .vertical1080p ? 0.60 : 0.54
        case .screenGuide:
            bottomThreshold = mode == .vertical1080p ? 0.74 : 0.60
            topThreshold = mode == .vertical1080p ? 0.64 : 0.56
        }

        if analysis.bottomCoverageRatio >= bottomThreshold {
            return String(localized: "kamerayı biraz yukarı al")
        }

        if analysis.headroomRatio >= topThreshold {
            return String(localized: "kamerayı biraz aşağı indir")
        }

        return nil
    }

    private func groupVerticalInstruction(in analysis: FrameAnalysis) -> String? {
        guard let averageY = analysis.averageFaceCenterY else { return nil }

        if averageY > 0.52 {
            return String(localized: "kamerayı biraz yukarı al")
        }

        if averageY < 0.24 {
            return String(localized: "kamerayı biraz aşağı indir")
        }

        return nil
    }

    private func groupHorizontalInstruction(in analysis: FrameAnalysis) -> String? {
        let leftThreshold = analysis.subjectCount == .one ? 0.34 : 0.42
        let rightThreshold = analysis.subjectCount == .one ? 0.66 : 0.58

        if analysis.groupCenterX < leftThreshold {
            switch analysis.subjectCount {
            case .one:
                return String(localized: "biraz sağa geç")
            case .two, .three:
                return String(localized: "grup biraz solda kalmış, biraz sağa kayın")
            }
        }

        if analysis.groupCenterX > rightThreshold {
            switch analysis.subjectCount {
            case .one:
                return String(localized: "biraz sola geç")
            case .two, .three:
                return String(localized: "grup biraz sağda kalmış, biraz sola kayın")
            }
        }

        return nil
    }
}
