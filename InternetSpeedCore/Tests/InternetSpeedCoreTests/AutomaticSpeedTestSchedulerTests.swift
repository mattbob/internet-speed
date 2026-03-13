import XCTest
@testable import InternetSpeedCore

@MainActor
final class AutomaticSpeedTestSchedulerTests: XCTestCase {
    func testNextRunDateUsesAnchorAndInterval() {
        let nowBox = MutableNow(Date(timeIntervalSince1970: 1_710_000_000))
        let scheduler = AutomaticSpeedTestScheduler(
            now: { nowBox.value },
            sleep: neverEndingSleep
        )

        scheduler.updateSchedule(
            anchorDate: nowBox.value.addingTimeInterval(-300),
            interval: AutoTestInterval.hourly
        )

        XCTAssertEqual(
            scheduler.nextRunDate,
            nowBox.value.addingTimeInterval(55 * 60)
        )
        scheduler.stop()
    }

    func testSchedulerRunsImmediatelyAfterWakeWhenDue() async {
        let nowBox = MutableNow(Date(timeIntervalSince1970: 1_710_000_000))
        let counter = RunCounter()
        let scheduler = AutomaticSpeedTestScheduler(
            now: { nowBox.value },
            sleep: neverEndingSleep
        )

        scheduler.updateSchedule(anchorDate: nowBox.value, interval: AutoTestInterval.hourly)
        scheduler.start {
            counter.count += 1
        }

        nowBox.value = nowBox.value.addingTimeInterval(3_700)
        scheduler.handleWakeOrClockChange()

        for _ in 0..<20 where counter.count == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(counter.count, 1)
        scheduler.stop()
    }

    func testOffIntervalClearsNextRunDate() {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let scheduler = AutomaticSpeedTestScheduler(
            now: { now },
            sleep: neverEndingSleep
        )

        scheduler.updateSchedule(anchorDate: now, interval: AutoTestInterval.never)

        XCTAssertNil(scheduler.nextRunDate)
        scheduler.stop()
    }
}

@MainActor
private final class RunCounter {
    var count = 0
}

private final class MutableNow: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

private func neverEndingSleep(_ duration: Duration) async throws {
    try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
}
