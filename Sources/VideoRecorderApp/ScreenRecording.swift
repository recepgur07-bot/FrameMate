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

    var localizedName: String {
        DeviceDisplayNameLocalizer.localizedDisplayName(name)
    }

    var localizedSummaryName: String {
        DeviceDisplayNameLocalizer.localizedDisplaySummaryName(name)
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

enum DeviceDisplayNameLocalizer {
    static func localizedDisplayName(_ name: String) -> String {
        if let displayNumber = displayNumber(in: name) {
            return String(format: String(localized: "Ekran %@"), String(displayNumber))
        }
        return name
    }

    static func localizedDisplaySummaryName(_ name: String) -> String {
        if let displayNumber = displayNumber(in: name) {
            return String(displayNumber)
        }
        return localizedDisplayName(name)
    }

    static func localizedCaptureDeviceName(_ name: String) -> String {
        switch name {
        case "Harici Mikrofon":
            return String(localized: "Harici Mikrofon")
        case "MacBook Mikrofonu":
            return String(localized: "MacBook Mikrofonu")
        default:
            return name
        }
    }

    private static func displayNumber(in name: String) -> Substring? {
        name.wholeMatch(of: /(?:Ekran|Screen)\s+(\d+)/)?.1
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
            return String(localized: "Seçilen ekran bulunamadı.")
        case .windowNotFound:
            return String(localized: "Seçilen pencere bulunamadı.")
        case .microphoneNotFound:
            return String(localized: "Seçilen mikrofon bulunamadı.")
        case .cannotCreateWriter:
            return String(localized: "Ekran kaydı dosyası hazırlanamadı.")
        case .cannotStartStream:
            return String(localized: "Ekran kaydı başlatılamadı.")
        case .emptyRecording:
            return String(localized: "Ekran kaydında yeterli görüntü alınamadı.")
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
    private let preflightAccess: @Sendable () -> Bool
    private let requestAccessHandler: @Sendable () -> Bool

    init(
        preflightAccess: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestAccessHandler: @escaping @Sendable () -> Bool = { CGRequestScreenCaptureAccess() }
    ) {
        self.preflightAccess = preflightAccess
        self.requestAccessHandler = requestAccessHandler
    }

    func authorizationStatus() -> ScreenRecordingAuthorizationStatus {
        preflightAccess() ? .authorized : .denied
    }

    func requestAccess() async -> ScreenRecordingPermissionRequestResult {
        let preflightAccess = self.preflightAccess
        let requestAccessHandler = self.requestAccessHandler
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)

                if preflightAccess() {
                    continuation.resume(returning: ScreenRecordingPermissionRequestResult.granted)
                    return
                }

                let granted = requestAccessHandler()
                if granted {
                    continuation.resume(returning: ScreenRecordingPermissionRequestResult.granted)
                } else if preflightAccess() {
                    continuation.resume(returning: ScreenRecordingPermissionRequestResult.grantedButRequiresRestart)
                } else {
                    continuation.resume(returning: ScreenRecordingPermissionRequestResult.denied)
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
