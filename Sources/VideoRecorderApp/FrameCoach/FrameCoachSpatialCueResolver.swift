import Foundation

struct FrameCoachSpatialCueResolver {
    func cue(
        for analysis: FrameAnalysis?,
        guidance: String
    ) -> FrameCoachSpatialCue? {
        cue(for: analysis, guidance: guidance, mode: .horizontal1080p)
    }

    func cue(
        for analysis: FrameAnalysis?,
        guidance: String,
        mode: RecordingMode
    ) -> FrameCoachSpatialCue? {
        let normalized = guidance.lowercased(with: Locale(identifier: "tr_TR"))
        if normalized.contains("algılanamıyor") ||
            normalized.contains("ışık düşük") ||
            normalized.contains("izin") {
            return nil
        }

        if normalized == "kadraj uygun" || normalized == "kadraj dengeli" {
            return FrameCoachSpatialCue(direction: .center, severity: .mild, confirmsCentered: true)
        }

        guard let analysis else {
            return cueFromGuidanceFallback(normalized)
        }

        if let horizontalCue = horizontalCue(for: analysis) {
            return horizontalCue
        }

        if let verticalCue = verticalCue(for: analysis, mode: mode) {
            return verticalCue
        }

        return FrameCoachSpatialCue(direction: .center, severity: .mild, confirmsCentered: true)
    }

    private func horizontalCue(for analysis: FrameAnalysis) -> FrameCoachSpatialCue? {
        let delta = analysis.groupCenterX - 0.5
        let mildThreshold = analysis.subjectCount == .one ? 0.08 : 0.06
        let strongThreshold = analysis.subjectCount == .one ? 0.16 : 0.12

        guard abs(delta) >= mildThreshold else { return nil }

        let severity: FrameCoachSpatialSeverity = abs(delta) >= strongThreshold ? .strong : .mild
        let direction: FrameCoachSpatialDirection = delta < 0 ? .right : .left
        return FrameCoachSpatialCue(direction: direction, severity: severity, confirmsCentered: false)
    }

    private func verticalCue(for analysis: FrameAnalysis, mode: RecordingMode) -> FrameCoachSpatialCue? {
        guard let averageY = analysis.averageFaceCenterY else { return nil }

        let targetCenterY = mode == .vertical1080p ? 0.42 : 0.38
        let centerDelta = averageY - targetCenterY
        let mildCenterThreshold = mode == .vertical1080p ? 0.08 : 0.07
        let strongCenterThreshold = mode == .vertical1080p ? 0.14 : 0.12

        let headroomStrong = mode == .vertical1080p ? 0.60 : 0.46
        let headroomMild = mode == .vertical1080p ? 0.50 : 0.38
        let bottomStrong = mode == .vertical1080p ? 0.66 : 0.50
        let bottomMild = mode == .vertical1080p ? 0.58 : 0.43

        if analysis.bottomCoverageRatio >= bottomMild || centerDelta >= mildCenterThreshold {
            let severity: FrameCoachSpatialSeverity =
                (analysis.bottomCoverageRatio >= bottomStrong || centerDelta >= strongCenterThreshold) ? .strong : .mild
            return FrameCoachSpatialCue(direction: .up, severity: severity, confirmsCentered: false)
        }

        if analysis.headroomRatio >= headroomMild || centerDelta <= -mildCenterThreshold {
            let severity: FrameCoachSpatialSeverity =
                (analysis.headroomRatio >= headroomStrong || centerDelta <= -strongCenterThreshold) ? .strong : .mild
            return FrameCoachSpatialCue(direction: .down, severity: severity, confirmsCentered: false)
        }

        return nil
    }

    private func cueFromGuidanceFallback(_ normalized: String) -> FrameCoachSpatialCue? {
        if normalized.contains("sağa") {
            return FrameCoachSpatialCue(direction: .right, severity: .mild, confirmsCentered: false)
        }

        if normalized.contains("sola") {
            return FrameCoachSpatialCue(direction: .left, severity: .mild, confirmsCentered: false)
        }

        if normalized.contains("yukarı") {
            return FrameCoachSpatialCue(direction: .up, severity: .mild, confirmsCentered: false)
        }

        if normalized.contains("aşağı") || normalized.contains("indir") {
            return FrameCoachSpatialCue(direction: .down, severity: .mild, confirmsCentered: false)
        }

        return nil
    }
}
