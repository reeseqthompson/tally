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

        // Remove duplicate initial point if needed.
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
                    .foregroundStyle(Color.blue)
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
            // Set the y-axis range to 0 to 150% of the overall budget.
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
                    // Start the vertical line below the label (e.g. 30 points down).
                    Path { path in
                        path.move(to: CGPoint(x: lineX, y: 35))
                        path.addLine(to: CGPoint(x: lineX, y: geo.size.height))
                    }
                    .stroke(Color.gray, lineWidth: 1)

                    // Compute a clamped x position for the label.
                    let clampedX = min(max(lineX, 60), geo.size.width - 60)

                    VStack(spacing: 4) {
                        Text("\(dataPoint.date, formatter: dateFormatter)")
                        Text(formatPreciseAmount(dataPoint.total))
                    }
                    .font(.caption)
                    .padding(6)
                    .background(Color(.systemBackground).opacity(0.0))
                    .cornerRadius(6)
                    .position(x: clampedX, y: 12)
                }
                .allowsHitTesting(false)
            }
        }
    }

    
    /// The key overlay view that displays a legend for the chart.
    private var keyOverlayView: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                // Dotted line representing total budget.
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: 30, y: 0))
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                .foregroundColor(.red)
                .frame(width: 30, height: 2)

                Text("Budget")
                    .font(.caption)
            }
            HStack(spacing: 4) {
                // Blue dot representing spending.
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                Text("Cumulative Spent")
                    .font(.caption)
            }
        }
        .padding(8)
        .background(Color(.systemBackground).opacity(0.0))
        .cornerRadius(8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: -10)

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
                                        if let location = currentDragLocation {
                                            updateLabel(location: location, proxy: proxy, plotFrame: plotFrame)
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if abs(value.translation.width) < abs(value.translation.height) {
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
            // Center the key overlay; hide it when a label is shown (i.e. dragDataPoint is non-nil).
            keyOverlayView
                .opacity(dragDataPoint == nil ? 1 : 0)
        }
        .padding(.vertical)
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
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                let amount = Double.random(in: 10...100)
                sampleTransactions.append(
                    Transaction(categoryID: UUID(), date: date, amount: amount, description: "Sample")
                )
            }
        }
        
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
