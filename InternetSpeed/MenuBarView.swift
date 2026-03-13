import Charts
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var currentDate = Date()

    private let chartCalendar = Calendar.current
    private let statusTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            automaticTestingSection

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: runSpeedTest) {
                HStack(spacing: 8) {
                    if viewModel.isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Testing...")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text(viewModel.primaryButtonTitle)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRunning)
            .accessibilityLabel(viewModel.isRunning ? "Testing internet speed" : viewModel.primaryButtonTitle)

            automaticTestingStatusLabel
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            currentDate = Date()
        }
        .onReceive(statusTimer) { date in
            currentDate = date
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Internet Speed")
                .font(.headline)

            Text(viewModel.headerStatusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let result = viewModel.lastResult {
            VStack(alignment: .leading, spacing: 10) {
                speedRow(title: "Download", value: result.downloadDisplayString)
                speedRow(title: "Upload", value: result.uploadDisplayString)
            }
        } else {
            Text("Run a test to measure your current download and upload throughput with Apple's networkQuality tool.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func speedRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }

    private var automaticTestingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            if viewModel.hasEnoughChartData {
                speedHistoryChart
            }
        }
    }

    private var automaticTestingStatusLabel: some View {
        Text(viewModel.automaticTestingStatusText(relativeTo: currentDate))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .accessibilityLabel("Automatic testing status")
    }

    private var speedHistoryChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 12) {
                    legendItem(color: .blue, title: "Download")
                    legendItem(color: .green, title: "Upload")
                }
                Spacer()
                Text("Mbps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Chart {
                ForEach(chartSeries) { series in
                    ForEach(series.points) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Speed", point.megabitsPerSecond),
                            series: .value("Series", series.name)
                        )
                        .foregroundStyle(by: .value("Series", series.name))
                        .interpolationMethod(.linear)
                        .lineStyle(series.strokeStyle)

                        PointMark(
                            x: .value("Time", point.time),
                            y: .value("Speed", point.megabitsPerSecond)
                        )
                        .foregroundStyle(by: .value("Series", series.name))
                        .symbolSize(18)
                    }
                }
            }
            .chartXScale(
                domain: chartDomain,
                range: .plotDimension(startPadding: 0, endPadding: 14)
            )
            .chartLegend(.hidden)
            .chartForegroundStyleScale([
                "Download": Color.blue,
                "Upload": Color.green,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let megabitsPerSecond = value.as(Double.self) {
                            Text("\(Int(megabitsPerSecond.rounded()))")
                        }
                    }
                }
            }
            .frame(height: 110)
            .accessibilityLabel("Speed history chart")
            .accessibilityValue(viewModel.chartAccessibilitySummary)
        }
    }

    private var chartDomain: ClosedRange<Date> {
        currentDate.addingTimeInterval(-MenuBarViewModel.historyRetentionInterval)...currentDate
    }

    private var chartSamples: [HourlyChartSample] {
        var latestResultByHour: [Date: SpeedTestResult] = [:]

        for result in viewModel.speedHistory {
            let bucketStart = chartCalendar.dateInterval(of: .hour, for: result.measuredAt)?.start ?? result.measuredAt

            if let existing = latestResultByHour[bucketStart], existing.measuredAt >= result.measuredAt {
                continue
            }

            latestResultByHour[bucketStart] = result
        }

        return latestResultByHour
            .map { bucketStart, result in
                HourlyChartSample(
                    time: bucketStart,
                    downloadMegabitsPerSecond: result.downloadMegabitsPerSecond,
                    uploadMegabitsPerSecond: result.uploadMegabitsPerSecond
                )
            }
            .sorted { $0.time < $1.time }
    }

    private var chartSeries: [ChartSeries] {
        [
            ChartSeries(
                name: "Download",
                strokeStyle: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round),
                points: chartSamples.map {
                    ChartPoint(time: $0.time, megabitsPerSecond: $0.downloadMegabitsPerSecond)
                }
            ),
            ChartSeries(
                name: "Upload",
                strokeStyle: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 4]),
                points: chartSamples.map {
                    ChartPoint(time: $0.time, megabitsPerSecond: $0.uploadMegabitsPerSecond)
                }
            ),
        ]
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func runSpeedTest() {
        Task {
            await viewModel.runSpeedTest()
        }
    }
}

private struct HourlyChartSample: Identifiable {
    let time: Date
    let downloadMegabitsPerSecond: Double
    let uploadMegabitsPerSecond: Double

    var id: Date {
        time
    }
}

private struct ChartSeries: Identifiable {
    let name: String
    let strokeStyle: StrokeStyle
    let points: [ChartPoint]

    var id: String {
        name
    }
}

private struct ChartPoint: Identifiable {
    let time: Date
    let megabitsPerSecond: Double

    var id: Date {
        time
    }
}
