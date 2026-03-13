import Foundation

struct SpeedTestResult: Codable, Equatable, Sendable {
    let downloadBitsPerSecond: Double
    let uploadBitsPerSecond: Double
    let measuredAt: Date

    var downloadMegabitsPerSecond: Double {
        downloadBitsPerSecond / 1_000_000
    }

    var uploadMegabitsPerSecond: Double {
        uploadBitsPerSecond / 1_000_000
    }

    var downloadDisplayString: String {
        Self.formatThroughput(downloadBitsPerSecond)
    }

    var uploadDisplayString: String {
        Self.formatThroughput(uploadBitsPerSecond)
    }

    var measuredAtDisplayString: String {
        measuredAt.formatted(date: .abbreviated, time: .shortened)
    }

    static func decode(from data: Data) throws -> SpeedTestResult {
        let response = try JSONDecoder().decode(NetworkQualityResponse.self, from: data)

        if let errorDomain = response.errorDomain {
            throw SpeedTestRunnerError.networkQualityFailed(
                domain: errorDomain,
                code: response.errorCode ?? 0
            )
        }

        guard
            let downloadBitsPerSecond = response.downloadThroughput,
            let uploadBitsPerSecond = response.uploadThroughput,
            let endDate = response.endDate,
            let measuredAt = parseNetworkQualityDate(endDate)
        else {
            throw SpeedTestRunnerError.invalidResponse
        }

        return SpeedTestResult(
            downloadBitsPerSecond: downloadBitsPerSecond,
            uploadBitsPerSecond: uploadBitsPerSecond,
            measuredAt: measuredAt
        )
    }

    static func formatThroughput(_ bitsPerSecond: Double) -> String {
        guard bitsPerSecond.isFinite, bitsPerSecond > 0 else {
            return "0 Mbps"
        }

        switch bitsPerSecond {
        case 1_000_000_000...:
            return "\(format(bitsPerSecond / 1_000_000_000, decimals: 2)) Gbps"
        case 1_000_000...:
            return "\(format(bitsPerSecond / 1_000_000, decimals: bitsPerSecond >= 100_000_000 ? 0 : 1)) Mbps"
        case 1_000...:
            return "\(format(bitsPerSecond / 1_000, decimals: 0)) Kbps"
        default:
            return "\(format(bitsPerSecond, decimals: 0)) bps"
        }
    }

    private static func parseNetworkQualityDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.date(from: value)
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
            .replacingOccurrences(of: ".00", with: "")
            .replacingOccurrences(of: ".0", with: "")
    }
}

private struct NetworkQualityResponse: Decodable {
    let downloadThroughput: Double?
    let uploadThroughput: Double?
    let endDate: String?
    let errorCode: Int?
    let errorDomain: String?

    enum CodingKeys: String, CodingKey {
        case downloadThroughput = "dl_throughput"
        case uploadThroughput = "ul_throughput"
        case endDate = "end_date"
        case errorCode = "error_code"
        case errorDomain = "error_domain"
    }
}
