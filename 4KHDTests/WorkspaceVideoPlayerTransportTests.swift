@testable import _KHD
import AVFoundation
import XCTest

final class WorkspaceVideoPlayerTransportTests: XCTestCase {
    func testSkipLabelsCoverSecondAndMinuteSteps() {
        XCTAssertEqual(WorkspaceVideoPlayerTransport.skipLabel(for: 5, direction: -1), "-5s")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.skipLabel(for: 10, direction: 1), "+10s")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.skipLabel(for: 30, direction: -1), "-30s")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.skipLabel(for: 60, direction: 1), "+1m")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.skipLabel(for: 300, direction: -1), "-5m")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.skipSteps, [5, 10, 30, 60, 300])
    }

    func testRateLabelsAndNearestMatch() {
        XCTAssertEqual(WorkspaceVideoPlayerTransport.rateLabel(1), "1×")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.rateLabel(0.75), "0.75×")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.rateLabel(1.5), "1.5×")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.nearestRate(1.2), 1.25)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.nearestRate(0), 0.5)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.nearestRate(1), 1)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.rateIndex(1.22), 3)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.rateIndex(0.5), 0)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.rates, [0.5, 0.75, 1, 1.25, 1.5, 2])
        XCTAssertEqual(WorkspaceVideoPlayerTransport.defaultRate, 1)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.keyboardSkipSeconds, 10)
    }

    func testClampedSeekStopsAtEndsAndAllowsUnknownDuration() {
        XCTAssertEqual(
            WorkspaceVideoPlayerTransport.clampedTime(current: 10, delta: -30, duration: 100),
            0
        )
        XCTAssertEqual(
            WorkspaceVideoPlayerTransport.clampedTime(current: 90, delta: 30, duration: 100),
            100
        )
        XCTAssertEqual(
            WorkspaceVideoPlayerTransport.clampedTime(current: 10, delta: 30, duration: nil),
            40
        )
        XCTAssertEqual(
            WorkspaceVideoPlayerTransport.clampedTime(current: 5, delta: -10, duration: nil),
            0
        )
    }

    func testClockFormattingUsesHoursOnlyWhenNeeded() {
        XCTAssertEqual(WorkspaceVideoPlayerTransport.formatClock(0), "0:00")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.formatClock(65), "1:05")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.formatClock(5382), "1:29:42")
        XCTAssertEqual(WorkspaceVideoPlayerTransport.formatClock(7108), "1:58:28")
    }

    func testDurationIgnoresInvalidAndZeroCMTime() {
        XCTAssertNil(WorkspaceVideoPlayerTransport.durationSeconds(from: .invalid))
        XCTAssertNil(WorkspaceVideoPlayerTransport.durationSeconds(from: .indefinite))
        XCTAssertNil(WorkspaceVideoPlayerTransport.durationSeconds(from: .zero))
        XCTAssertEqual(
            WorkspaceVideoPlayerTransport.durationSeconds(from: CMTime(seconds: 12.5, preferredTimescale: 600)),
            12.5
        )
    }

    func testRateAndVolumeDefaultsRoundTrip() throws {
        let suiteName = "VideoPlayerTransport-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertEqual(WorkspaceVideoPlayerTransport.storedRate(defaults: defaults), 1)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.storedVolume(defaults: defaults), 1)

        WorkspaceVideoPlayerTransport.storeRate(1.22, defaults: defaults)
        WorkspaceVideoPlayerTransport.storeVolume(1.8, defaults: defaults)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.storedRate(defaults: defaults), 1.25)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.storedVolume(defaults: defaults), 1)

        WorkspaceVideoPlayerTransport.storeVolume(-0.2, defaults: defaults)
        XCTAssertEqual(WorkspaceVideoPlayerTransport.storedVolume(defaults: defaults), 0)
    }
}
