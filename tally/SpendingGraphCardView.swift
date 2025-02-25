import SwiftUI
import Charts

/// A simple model representing cumulative spending for a given day.
struct DailySpending: Identifiable {
    let id = UUID()
    let date: Date
    let total: Double
}

/// A card view that displays a cumulative spending graph for the current month.
struct SpendingGraphCardView: View {
    @Environment(\.colorScheme) var colorScheme
    let transactions: [Transaction]
    let selectedMonth: Date
    let overallBudget: Double

    /// Computes the cumulative spending for each day in the selected month.
    private var dailySpending: [DailySpending] {
        let calendar = Calendar.current
        guard let monthRange = calendar.range(of: .day, in: .month, for: selectedMonth),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))
        else { return [] }
        
        var cumulative = 0.0
        return monthRange.compactMap { day in
            guard let currentDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return nil }
            let dailyTotal = transactions.filter { calendar.isDate($0.date, inSameDayAs: currentDate) }
                                         .reduce(0) { $0 + $1.amount }
            cumulative += dailyTotal
            return DailySpending(date: currentDate, total: cumulative)
        }
    }
    
    var body: some View {
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
            // Set the y-axis range to 0 to 120% of the overall budget.
            .chartYScale(domain: 0...(overallBudget * 1.2))
            .frame(height: 200)
            .padding(.horizontal)
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
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
              let dayRange = calendar.range(of: .day, in: .month, for: today)
        else {
            return AnyView(Text("Error"))
        }
        var sampleTransactions = [Transaction]()
        // Create sample transactions for each day.
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                let amount = Double.random(in: 10...100)
                sampleTransactions.append(Transaction(categoryID: UUID(), date: date, amount: amount, description: "Sample"))
            }
        }
        // Let's assume an overall budget for the month (for preview purposes) of $1500.
        return AnyView(
            SpendingGraphCardView(transactions: sampleTransactions, selectedMonth: today, overallBudget: 1500)
        )
    }
}
#endif

