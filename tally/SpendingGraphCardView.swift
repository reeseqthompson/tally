import SwiftUI
import Charts

/// A simple model representing cumulative spending for a given day.
struct DailySpending: Identifiable {
    let id = UUID()
    let date: Date
    let total: Double
}

private let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    return df
}()

/// A card view that displays a cumulative spending graph for the current month.
struct SpendingGraphCardView: View {
    @Environment(\.colorScheme) var colorScheme
    let transactions: [Transaction]
    let selectedMonth: Date
    let overallBudget: Double
    
    @State private var currentDragLocation: CGPoint? = nil
    @State private var longPressActive: Bool = false

    // Track the data point under the drag and the x position of the vertical line.
    @State private var dragDataPoint: DailySpending? = nil
    @State private var lineXPosition: CGFloat? = nil

    /// Computes the cumulative spending for each day in the selected month.
    private var dailySpending: [DailySpending] {
        let calendar = Calendar.current
        guard
            let monthRange = calendar.range(of: .day, in: .month, for: selectedMonth),
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))
        else {
            return []
        }
        
        var cumulative = 0.0
        var result: [DailySpending] = []
        
        // Insert initial point for "0th" day with $0 spent.
        result.append(DailySpending(date: monthStart, total: 0))
        
        for day in monthRange {
            guard let currentDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            if currentDate > Date() { continue }  // Skip future dates.
            let dailyTotal = transactions
                .filter { calendar.isDate($0.date, inSameDayAs: currentDate) }
                .reduce(0) { $0 + $1.amount }
            cumulative += dailyTotal
            result.append(DailySpending(date: currentDate, total: cumulative))
        }

        // Add these lines before "return result"
        if result.count > 1, Calendar.current.isDate(result[0].date, inSameDayAs: result[1].date) {
            result.remove(at: 0)
        }

        return result
    }
    
    /// The chart portion of the view.
    private var chartContent: some View {
        VStack(alignment: .leading) {
            Chart {
                // Draw the cumulative line and points.
                ForEach(dailySpending) { dataPoint in
                    LineMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Cumulative Spent", dataPoint.total)
                    )
                    PointMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Cumulative Spent", dataPoint.total)
                    )
                }
                // Draw a horizontal rule at the overall budget.
                RuleMark(y: .value("Overall Budget", overallBudget))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXScale(domain: {
                let calendar = Calendar.current
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
                let monthRange = calendar.range(of: .day, in: .month, for: selectedMonth)!
                let monthEnd = calendar.date(byAdding: .day, value: monthRange.count - 1, to: monthStart)!
                return monthStart...monthEnd
            }())

            // Set the y-axis range to 0 to 120% of the overall budget.
//            .chartYScale(domain: 0...(overallBudget * 1.2))
            .chartYScale(domain: 0...(overallBudget * 1.5))
            .frame(height: 200)
            .padding(.horizontal)
        }
    }
    
    /// The overlay view that handles the drag gesture and draws the vertical line and label.
    private var dragOverlayView: some View {
        Group {
            if let dataPoint = dragDataPoint, let lineX = lineXPosition {
                GeometryReader { geo in
                    // Draw the vertical line.
                    Path { path in
                        path.move(to: CGPoint(x: lineX, y: 0))
                        path.addLine(to: CGPoint(x: lineX, y: geo.size.height))
                    }
                    .stroke(Color.gray, lineWidth: 1)
                    
                    // Compute a clamped x position for the label.
                    // Assume a label width of about 120; this centers it while keeping it within [60, geo.size.width - 60].
                    let clampedX = min(max(lineX, 60), geo.size.width - 60)
                    
                    VStack(spacing: 4) {
                        Text("\(dataPoint.date, formatter: dateFormatter)")
                        Text(formatPreciseAmount(dataPoint.total))
                    }
                    .font(.caption)
                    .padding(6)
                    .background(Color(.systemBackground).opacity(0.8))
                    .cornerRadius(6)
//                    .position(x: clampedX, y: -28)
                    .position(x: clampedX, y: 12)
                }
                .allowsHitTesting(false)
            }

        }
    }
    
    private func updateLabel(location: CGPoint, proxy: ChartProxy, plotFrame: CGRect) {
        let xInPlot = location.x - plotFrame.minX
        guard xInPlot >= 0 && xInPlot <= plotFrame.width,
              let date: Date = proxy.value(atX: xInPlot),
              let nearest = dailySpending.min(by: {
                  abs($0.date.timeIntervalSince1970 - date.timeIntervalSince1970) <
                  abs($1.date.timeIntervalSince1970 - date.timeIntervalSince1970)
              })
        else { return }
        
        dragDataPoint = nearest
        
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        let monthRange = calendar.range(of: .day, in: .month, for: selectedMonth)!
        let monthEnd = calendar.date(byAdding: .day, value: monthRange.count - 1, to: monthStart)!
        let totalInterval = monthEnd.timeIntervalSince(monthStart)
        let interval = nearest.date.timeIntervalSince(monthStart)
        let ratio = totalInterval > 0 ? interval / totalInterval : 0
        lineXPosition = plotFrame.minX + (plotFrame.width * CGFloat(ratio))
    }

    
    var body: some View {
        ZStack {
            chartContent
                // Add a chart overlay for the drag gesture.
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        let plotFrame = geometry[proxy.plotAreaFrame]
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            // Use a highPriorityGesture for the long press.
                            .highPriorityGesture(
                                LongPressGesture(minimumDuration: 0.3)
                                    .onEnded { _ in
                                        longPressActive = true
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        // Immediately update the label if we already have a drag location.
                                        if let location = currentDragLocation {
                                            updateLabel(location: location, proxy: proxy, plotFrame: plotFrame)
                                        }
                                    }
                            )
                            // Attach a simultaneous drag gesture.
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        // Only update if the horizontal movement is dominant.
                                        if abs(value.translation.width) < abs(value.translation.height) {
                                            // Let vertical drags pass through for scrolling.
                                            return
                                        }
                                        currentDragLocation = value.location
                                        if longPressActive {
                                            updateLabel(location: value.location, proxy: proxy, plotFrame: plotFrame)
                                        }
                                    }
                                    .onEnded { _ in
                                        dragDataPoint = nil
                                        lineXPosition = nil
                                        longPressActive = false
                                        currentDragLocation = nil
                                    }
                            )
                    }
                }
            dragOverlayView
        }
        .padding(.vertical)
//        .padding(.top, 40)
        .background(Color.cardBackground(for: colorScheme))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

#if DEBUG
struct SpendingGraphCardView_Previews: PreviewProvider {
    static var previews: some View {
        let calendar = Calendar.current
        let today = Date()
        guard
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
            let dayRange = calendar.range(of: .day, in: .month, for: today)
        else {
            return AnyView(Text("Error"))
        }
        
        var sampleTransactions = [Transaction]()
        // Create sample transactions for each day.
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                let amount = Double.random(in: 10...100)
                sampleTransactions.append(
                    Transaction(categoryID: UUID(), date: date, amount: amount, description: "Sample")
                )
            }
        }
        
        // Let's assume an overall budget for the month (for preview purposes) of $1500.
        return AnyView(
            SpendingGraphCardView(
                transactions: sampleTransactions,
                selectedMonth: today,
                overallBudget: 1500
            )
        )
    }
}
#endif

