import CoreVideo
import Foundation

struct FrameLightingAnalyzer {
    func analyze(pixelBuffer: CVPixelBuffer) -> FrameLightingAnalysis {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return FrameLightingAnalysis(averageLuma: 1)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        let stepX = max(1, width / 24)
        let stepY = max(1, height / 24)
        var sampleCount = 0
        var lumaTotal = 0.0

        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = y * bytesPerRow + x * 4
                let blue = Double(bytes[offset]) / 255
                let green = Double(bytes[offset + 1]) / 255
                let red = Double(bytes[offset + 2]) / 255
                lumaTotal += (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return FrameLightingAnalysis(averageLuma: 1)
        }

        return FrameLightingAnalysis(averageLuma: lumaTotal / Double(sampleCount))
    }
}
