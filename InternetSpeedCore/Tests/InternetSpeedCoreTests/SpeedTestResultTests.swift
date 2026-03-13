import XCTest
@testable import InternetSpeedCore

final class SpeedTestResultTests: XCTestCase {
    func testDecodeSuccessfulNetworkQualityResponse() throws {
        let data = Data(
            """
            {
              "dl_throughput" : 940500000,
              "ul_throughput" : 412000000,
              "end_date" : "2026-03-13 10:15:04.125"
            }
            """.utf8
        )

        let result = try SpeedTestResult.decode(from: data)

        XCTAssertEqual(result.downloadBitsPerSecond, 940_500_000)
        XCTAssertEqual(result.uploadBitsPerSecond, 412_000_000)

        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(calendar.component(.year, from: result.measuredAt), 2026)
        XCTAssertEqual(calendar.component(.month, from: result.measuredAt), 3)
        XCTAssertEqual(calendar.component(.day, from: result.measuredAt), 13)
    }

    func testDecodeNetworkErrorMapsToRunnerError() {
        let data = Data(
            """
            {
              "error_domain" : "NSURLErrorDomain",
              "error_code" : -1009,
              "end_date" : "2026-03-13 10:15:04.125"
            }
            """.utf8
        )

        XCTAssertThrowsError(try SpeedTestResult.decode(from: data)) { error in
            XCTAssertEqual(error as? SpeedTestRunnerError, .networkQualityFailed(domain: "NSURLErrorDomain", code: -1009))
        }
    }

    func testFormatThroughputAcrossRanges() {
        XCTAssertEqual(SpeedTestResult.formatThroughput(875_000), "875 Kbps")
        XCTAssertEqual(SpeedTestResult.formatThroughput(84_500_000), "84.5 Mbps")
        XCTAssertEqual(SpeedTestResult.formatThroughput(940_500_000), "940 Mbps")
        XCTAssertEqual(SpeedTestResult.formatThroughput(1_530_000_000), "1.53 Gbps")
    }
}
