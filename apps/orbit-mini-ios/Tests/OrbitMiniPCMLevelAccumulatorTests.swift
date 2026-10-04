import Foundation

@main
enum OrbitMiniPCMLevelAccumulatorTests {
    static func main() {
        // A. digital silence
        var acc = OrbitMiniPCMLevelAccumulator()
        add(&acc, [Int16](repeating: 0, count: 480))
        var report = acc.takeReport()
        expect(report?.rms == 0 && report?.peak == 0, "digital silence has zero rms and peak")
        expect(report?.activeBlocksPercent == 0, "digital silence has no active blocks")

        // B. constant amplitude
        add(&acc, [Int16](repeating: 16384, count: 480))
        report = acc.takeReport()
        expect(near(report?.rms, 0.5) && near(report?.peak, 0.5), "constant 16384 is 0.5 of full scale")
        expect(report?.activeBlocksPercent == 100, "loud block is active")

        // C. positive and negative values
        add(&acc, [1000, -3000, 2000, -500])
        report = acc.takeReport()
        expect(near(report?.peak, 3000.0 / 32768.0), "peak uses absolute value")
        let mixed: [Double] = [1000, -3000, 2000, -500]
        let expectedRMS: Double = meanSquareRoot(mixed) / 32768.0
        expect(near(report?.rms, expectedRMS), "rms of mixed-sign samples")

        // D. Int16.min does not overflow
        add(&acc, [Int16.min, Int16.max])
        report = acc.takeReport()
        expect(near(report?.peak, 1.0), "Int16.min reports full-scale peak")
        let extremes: [Double] = [32768, 32767]
        expect(near(report?.rms, meanSquareRoot(extremes) / 32768.0), "Int16.min rms")

        // E. accumulation over blocks, with one quiet and one active block
        add(&acc, [Int16](repeating: 10, count: 480))
        add(&acc, [Int16](repeating: 8000, count: 480))
        report = acc.takeReport()
        expect(report?.blocks == 2, "two blocks accumulated")
        expect(near(report?.activeBlocksPercent, 50), "half of the blocks are active")
        expect(near(report?.peak, 8000.0 / 32768.0), "window peak is the maximum block peak")
        let blockLevels: [Double] = [10, 8000]
        let windowRMS: Double = meanSquareRoot(blockLevels) / 32768.0
        expect(near(report?.rms, windowRMS), "window rms spans all samples")

        // F. report resets the window; merge matches direct accumulation
        expect(acc.takeReport() == nil, "taking a report empties the window")
        expect(acc.isEmpty, "window is empty after report")
        var left = OrbitMiniPCMLevelAccumulator()
        var right = OrbitMiniPCMLevelAccumulator()
        var direct = OrbitMiniPCMLevelAccumulator()
        add(&left, [Int16](repeating: 200, count: 480)); add(&direct, [Int16](repeating: 200, count: 480))
        add(&right, [Int16](repeating: -9000, count: 480)); add(&direct, [Int16](repeating: -9000, count: 480))
        left.merge(right)
        expect(left.takeReport() == direct.takeReport(), "merge equals direct accumulation")

        // G. missing or empty data fails safely
        var safe = OrbitMiniPCMLevelAccumulator()
        safe.add(nil, count: 480)
        [Int16](repeating: 5, count: 4).withUnsafeBufferPointer { safe.add($0.baseAddress, count: 0) }
        expect(safe.isEmpty && safe.takeReport() == nil, "nil or zero-length input yields no report")

        // H. only aggregate scalars exist in state and report
        add(&acc, [123, -456, 789])
        let state = Mirror(reflecting: acc).children.map { $0.value }
        expect(state.allSatisfy { $0 is Int || $0 is UInt64 || $0 is UInt32 }, "accumulator keeps scalar counters only")
        let reportValues = Mirror(reflecting: acc.takeReport()!).children.map { $0.value }
        expect(reportValues.allSatisfy { $0 is Int || $0 is Double }, "report carries scalar aggregates only")

        print("OrbitMiniPCMLevelAccumulatorTests: PASS")
    }

    private static func add(_ acc: inout OrbitMiniPCMLevelAccumulator, _ samples: [Int16]) {
        samples.withUnsafeBufferPointer { acc.add($0.baseAddress, count: $0.count) }
    }

    private static func meanSquareRoot(_ values: [Double]) -> Double {
        var total = 0.0
        for value in values { total += value * value }
        return (total / Double(values.count)).squareRoot()
    }

    private static func near(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-6
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
