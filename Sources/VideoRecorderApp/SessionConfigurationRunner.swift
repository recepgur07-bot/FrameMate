@preconcurrency import AVFoundation
import Foundation

protocol SessionLifecycleControlling: AnyObject {
    var isRunning: Bool { get }

    func beginConfiguration()
    func commitConfiguration()
    func startRunning()
}

extension AVCaptureSession: SessionLifecycleControlling {}

enum SessionConfigurationRunner {
    static func configureAndStartIfNeeded(
        session: any SessionLifecycleControlling,
        _ configure: () throws -> Void
    ) throws {
        session.beginConfiguration()
        do {
            try configure()
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }

        if !session.isRunning {
            session.startRunning()
        }
    }
}
