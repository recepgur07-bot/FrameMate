import CoreVideo
import XCTest
@testable import VideoRecorderApp

final class FrameLightingAnalyzerTests: XCTestCase {
    func testDarkBGRAFrameProducesLowAverageLuma() throws {
        let pixelBuffer = try makePixelBuffer(red: 10, green: 10, blue: 10)

        let analysis = FrameLightingAnalyzer().analyze(pixelBuffer: pixelBuffer)

        XCTAssertLessThan(analysis.averageLuma, 0.18)
        XCTAssertTrue(analysis.isLowLight)
    }

    func testBrightBGRAFrameProducesHigherAverageLuma() throws {
        let pixelBuffer = try makePixelBuffer(red: 220, green: 220, blue: 220)

        let analysis = FrameLightingAnalyzer().analyze(pixelBuffer: pixelBuffer)

        XCTAssertGreaterThan(analysis.averageLuma, 0.18)
        XCTAssertFalse(analysis.isLowLight)
    }

    private func makePixelBuffer(red: UInt8, green: UInt8, blue: UInt8) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            4,
            4,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let unwrapped = try XCTUnwrap(pixelBuffer)

        CVPixelBufferLockBaseAddress(unwrapped, [])
        defer { CVPixelBufferUnlockBaseAddress(unwrapped, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(unwrapped)
        let height = CVPixelBufferGetHeight(unwrapped)
        let width = CVPixelBufferGetWidth(unwrapped)
        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(unwrapped))
        let bytes = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = blue
                bytes[offset + 1] = green
                bytes[offset + 2] = red
                bytes[offset + 3] = 255
            }
        }

        return unwrapped
    }
}
