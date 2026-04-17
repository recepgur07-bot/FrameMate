import CoreGraphics
import Foundation
import AVFoundation
import AppKit

struct ScreenDisplayOption: Identifiable, Hashable {
    let id: String
    let name: String
    let frame: CGRect

    init(id: String, name: String, frame: CGRect = .zero) {
        self.id = id
        self.name = name
        self.frame = frame
    }
}

struct ScreenWindowOption: Identifiable, Hashable {
    let id: String
    let name: String
    let frame: CGRect

    init(id: String, name: String, frame: CGRect = .zero) {
        self.id = id
        self.name = name
        self.frame = frame
    }
}

enum ScreenRecordingAuthorizationStatus: Equatable {
    case authorized
    case denied
}

enum ScreenRecordingPermissionRequestResult: Equatable {
    case granted
    case denied
    case grantedButRequiresRestart
}

enum ScreenRecordingTarget: Equatable {
    case display(id: String)
    case window(id: String)
}

enum ScreenRecordingError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case microphoneNotFound
    case cannotCreateWriter
    case cannotStartStream
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Seçilen ekran bulunamadı."
        case .windowNotFound:
            return "Seçilen pencere bulunamadı."
        case .microphoneNotFound:
            return "Seçilen mikrofon bulunamadı."
        case .cannotCreateWriter:
            return "Ekran kaydı dosyası hazırlanamadı."
        case .cannotStartStream:
            return "Ekran kaydı başlatılamadı."
        case .emptyRecording:
            return "Ekran kaydında yeterli görüntü alınamadı."
        }
    }
}

protocol ScreenRecordingProviding: AnyObject {
    func authorizationStatus() -> ScreenRecordingAuthorizationStatus
    func requestAccess() async -> ScreenRecordingPermissionRequestResult
    func availableDisplays() async throws -> [ScreenDisplayOption]
    func availableWindows() async throws -> [ScreenWindowOption]
    func startRecording(
        target: ScreenRecordingTarget,
        microphoneDeviceID: String,
        includeSystemAudio: Bool,
        to url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) async throws
    func stopRecording()
}

final class SystemScreenRecordingProvider: ScreenRecordingProviding {
    func authorizationStatus() -> ScreenRecordingAuthorizationStatus {
        CGPreflightScreenCaptureAccess() ? .authorized : .denied
    }

    func requestAccess() async -> ScreenRecordingPermissionRequestResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: \.canBecomeKey)?.makeKeyAndOrderFront(nil)

                if CGPreflightScreenCaptureAccess() {
                    continuation.resume(returning: .granted)
                    return
                }

                let granted = CGRequestScreenCaptureAccess()
                if granted {
                    continuation.resume(returning: .granted)
                } else if CGPreflightScreenCaptureAccess() {
                    continuation.resume(returning: .granted)
                } else {
                    continuation.resume(returning: .grantedButRequiresRestart)
                }
            }
        }
    }

    func availableDisplays() async throws -> [ScreenDisplayOption] {
        []
    }

    func availableWindows() async throws -> [ScreenWindowOption] {
        []
    }

    func startRecording(
        target: ScreenRecordingTarget,
        microphoneDeviceID: String,
        includeSystemAudio: Bool,
        to url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) async throws {
        throw ScreenRecordingError.cannotStartStream
    }

    func stopRecording() {}
}
