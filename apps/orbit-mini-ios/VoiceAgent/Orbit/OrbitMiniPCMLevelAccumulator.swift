import Foundation

/// Diagnostic-only level statistics for Int16 PCM. No application behavior
/// depends on it, and only aggregate numbers (never samples) leave this type.
struct OrbitMiniPCMLevelAccumulator: Equatable {
    /// A block counts as "active" when its RMS is at least this many Int16
    /// counts (about 0.003 of full scale, roughly -50 dBFS). Purely a
    /// diagnostic marker for comparing speech and quiet windows.
    static let activeBlockRMSCounts: UInt64 = 100

    struct Report: Equatable {
        let blocks: Int
        let rms: Double
        let peak: Double
        let activeBlocksPercent: Double
    }

    private var blocks = 0
    private var samples: UInt64 = 0
    private var sumSquares: UInt64 = 0
    private var peakMagnitude: UInt32 = 0
    private var activeBlocks = 0

    var isEmpty: Bool { blocks == 0 }

    /// One block is one channel's contiguous Int16 samples from one callback.
    mutating func add(_ data: UnsafePointer<Int16>?, count: Int) {
        guard let data, count > 0 else { return }
        var blockSumSquares: UInt64 = 0
        var blockPeak: UInt32 = 0
        for index in 0..<count {
            let magnitude = UInt32(data[index].magnitude)
            blockPeak = max(blockPeak, magnitude)
            blockSumSquares &+= UInt64(magnitude) &* UInt64(magnitude)
        }
        blocks += 1
        samples &+= UInt64(count)
        sumSquares &+= blockSumSquares
        peakMagnitude = max(peakMagnitude, blockPeak)
        let threshold = Self.activeBlockRMSCounts
        if blockSumSquares >= UInt64(count) &* threshold &* threshold { activeBlocks += 1 }
    }

    mutating func merge(_ other: OrbitMiniPCMLevelAccumulator) {
        blocks += other.blocks
        samples &+= other.samples
        sumSquares &+= other.sumSquares
        peakMagnitude = max(peakMagnitude, other.peakMagnitude)
        activeBlocks += other.activeBlocks
    }

    /// Returns the window statistics and starts a new window.
    mutating func takeReport() -> Report? {
        guard blocks > 0, samples > 0 else { return nil }
        let fullScale = 32768.0
        let report = Report(
            blocks: blocks,
            rms: (Double(sumSquares) / Double(samples)).squareRoot() / fullScale,
            peak: Double(peakMagnitude) / fullScale,
            activeBlocksPercent: 100.0 * Double(activeBlocks) / Double(blocks)
        )
        self = OrbitMiniPCMLevelAccumulator()
        return report
    }
}
