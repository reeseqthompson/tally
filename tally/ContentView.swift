//
//  ContentView.swift
//  tally
//
//  Created by Reese Thompson on 1/22/25.
//

import SwiftUI

extension Color {
    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components else { return "#000000" }
        let r = Int((components[0] * 255.0).rounded())
        let g = Int((components[1] * 255.0).rounded())
        let b = Int((components[2] * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}


// MARK: - Data Models

struct Transaction: Identifiable, Codable {
    let id = UUID()
    var categoryID: UUID
    var date: Date
    var amount: Double
    var description: String
}

struct CategoryBudget: Identifiable, Codable {
    let id: UUID
    var name: String
    var total: Double
    private var colorHex: String // Store color as a hex string
    
    var color: Color {
        get { Color(hex: colorHex) ?? .gray }
        set { colorHex = newValue.toHex() }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        total: Double,
        color: Color
    ) {
        self.id = id
        self.name = name
        self.total = total
        self.colorHex = color.toHex()
    }
}

// Data model for savings goals
struct SavingsGoal: Identifiable, Codable {
    var id = UUID()
    var title: String
    var targetAmount: Double
    var currentAmount: Double
}

// Data model for per-month category allocations
struct CategoryAllocation: Identifiable, Codable {
    let id = UUID()
    var categoryID: UUID
    var month: Date // Should represent the first day of the month
    var allocatedAmount: Double
}

struct SavingsRecord: Identifiable, Codable {
    let id = UUID()
    var goalID: UUID
    var date: Date
    var amount: Double
    var description: String
}


// MARK: - Global Helpers

/// Check if two dates share the same month & year.
func sameMonth(_ d1: Date, _ d2: Date) -> Bool {
    let cal = Calendar.current
    let c1 = cal.dateComponents([.year, .month], from: d1)
    let c2 = cal.dateComponents([.year, .month], from: d2)
    return c1.year == c2.year && c1.month == c2.month
}

/// Return a simple "YYYY-MM" string for the date, ignoring day/time.
func monthKey(for date: Date) -> String {
    let comps = Calendar.current.dateComponents([.year, .month], from: date)
    let y = comps.year ?? 2024
    let m = comps.month ?? 1
    return String(format: "%04d-%02d", y, m)
}


/// Return the Date for the *previous* month of `date` (keeping day=1).
func previousMonth(of date: Date) -> Date? {
    var comps = Calendar.current.dateComponents([.year, .month], from: date)
    if let month = comps.month, let year = comps.year {
        if month == 1 {
            comps.month = 12
            comps.year = year - 1
        } else {
            comps.month = month - 1
        }
        comps.day = 1
        return Calendar.current.date(from: comps)
    }
    return nil
}

/// Returns only those transactions for the selected month/year.
func transactionsForMonth(_ all: [Transaction], selectedMonth: Date) -> [Transaction] {
    all.filter { sameMonth($0.date, selectedMonth) }
}

/// Summarize how much each category spent in these transactions.
func monthlySpentByCategory(categories: [CategoryBudget], transactions: [Transaction]) -> [UUID: Double] {
    var result = [UUID: Double]()
    for cat in categories {
        let sum = transactions
            .filter { $0.categoryID == cat.id }
            .map { $0.amount }
            .reduce(0, +)
        result[cat.id] = sum
    }
    return result
}


func leftoverForMonth(
    monthlyBudgets: [String: [CategoryBudget]],      // Dictionary mapping month keys to arrays of CategoryBudget
    allocations: [CategoryAllocation],               // Array of allocations for various categories and months
    rolloverSpentByMonth: [String: Double],            // Dictionary mapping month keys to rollover spent amounts
    selectedMonth: Date,                             // The month for which we want to calculate the leftover budget
    monthTransactions: [Transaction]                 // Array of transactions for the selected month
) -> Double {
    // Generate a key string for the selected month using a helper function
    let key = monthKey(for: selectedMonth)
    
    // Retrieve the category budgets for the selected month.
    // If no budgets are found for this month, use an empty array.
    let categoriesForMonth = monthlyBudgets[key] ?? []
    
    // 1) Sum Allocated Budget:
    // Filter the allocations to include only those that match the selected month.
    let allocatedCategories = allocations.filter { sameMonth($0.month, selectedMonth) }
    
    // Create a dictionary mapping each category's ID to its allocated amount.
    // This dictionary isn't used later in the function, but might be useful for further processing.
    let allocatedDict = Dictionary(uniqueKeysWithValues: allocatedCategories.map { ($0.categoryID, $0.allocatedAmount) })
    
    // Sum the total allocated amount for the month by adding up the 'total' field from each CategoryBudget.
    let totalAllocated = categoriesForMonth.reduce(0) { $0 + $1.total }
    
    // 2) Sum Spent Amount:
    // Extract the amount from each transaction and sum them up to get the total spent.
    let spent = monthTransactions.map { $0.amount }.reduce(0, +)
    
    // 3) Calculate Preliminary Leftover:
    // Subtract the total spent from the total allocated budget.
    let leftover = totalAllocated - spent
    
    // 4) Adjust for Rollover Spending:
    // Retrieve the rollover spending for the month from the dictionary.
    // If there is no entry for this month, default the rollover spent to 0.
    let rolloverSpent = rolloverSpentByMonth[key] ?? 0
    
    // Return the final leftover budget after subtracting the rollover spent amount.
    return leftover - rolloverSpent
}


/// A user-friendly Month+Year (e.g. "January 2025").
fileprivate let monthYearFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "LLLL yyyy"
    return df
}()

// MARK: - Amount Formatting Helper

/// Formats a given amount:
/// - No decimal places if less than $1,000.
/// - One decimal place followed by 'K' if $1,000 or more.
func formatAmount(_ amount: Double) -> String {
    if amount >= 1000 {
        let formatted = (amount / 1000).rounded(toPlaces: 1)
        return "$\(formatted)k"
    } else {
        let formatted = Int(amount.rounded()) // Changed from Int(amount) to Int(amount.rounded())
        return "$\(formatted)"
    }
}

// Extension to round a Double to a specified number of decimal places.
extension Double {
    /// Rounds the double to decimal places value
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}


// MARK: - Row Views

/// Displays a bar comparing "spent" vs. "category.total."
struct CategoryRow: View {
    let category: CategoryBudget
    let spentThisMonth: Double
    let allocatedAmount: Double // Added this line
    
    private var fractionUsed: Double {
        guard allocatedAmount > 0 else { return 0 }
        let rawFrac = spentThisMonth / allocatedAmount
        return min(max(rawFrac, 0), 1)
    }
    private var fractionRemaining: Double {
        1 - fractionUsed
    }
    private var remainingDisplay: Double {
        allocatedAmount - spentThisMonth
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(category.color)
                    .frame(width: geo.size.width * fractionRemaining)
                
                HStack {
                    Text(category.name)
                        .foregroundColor(.white)
                        .padding(.leading, 8)
                    
                    Spacer()
                    
                    Text("\(formatAmount(remainingDisplay)) / \(formatAmount(allocatedAmount))")
                        .foregroundColor(.white)
                        .padding(.trailing, 8)
                }
            }
        }
        .frame(height: 30)
    }
}


/// An overall bar for all categories combined in a month.
struct OverallBudgetRow: View {
    let totalAllocated: Double // Changed from categories and spent mapping
    let totalSpent: Double
    
    private var fractionRemaining: Double {
        guard totalAllocated > 0 else { return 1 }
        let usedFrac = totalSpent / totalAllocated
        return max(0, 1 - usedFrac)
    }
    private var remaining: Double {
        totalAllocated - totalSpent
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.teal)
                    .frame(width: geo.size.width * fractionRemaining)
                
                HStack {
                    Text("Overall Budget")
                        .foregroundColor(.white)
                        .padding(.leading, 8)
                    
                    Spacer()
                    
                    Text("\(formatAmount(remaining)) / \(formatAmount(totalAllocated))")
                        .foregroundColor(.white)
                        .padding(.trailing, 8)
                }
            }
        }
        .frame(height: 30)
    }
}

// MARK: - Goal Card View

struct GoalCardView: View {
    @Binding var goal: SavingsGoal
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.title)
                    .font(.headline)
                Spacer()
                Text("\(formatAmount(goal.currentAmount)) / \(formatAmount(goal.targetAmount))")
                    .font(.subheadline)
            }

            ProgressView(value: goal.currentAmount, total: goal.targetAmount)
                .progressViewStyle(LinearProgressViewStyle())
                .accentColor(.blue) // Optional: Customize the progress bar color

        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 4)
        .padding(.horizontal)
    }
}



// MARK: - Calendar
struct MonthlyCalendarView: View {
    let month: Date
    let transactions: [Transaction]
    let categories: [CategoryBudget] // New parameter
    
    private let columns = Array(repeating: GridItem(.flexible(), alignment: .top), count: 7)
    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 1 // Sunday-based
        return c
    }
    
    private var daysArray: [Date?] {
        guard
            let range = calendar.range(of: .day, in: .month, for: month),
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        
        let firstWkDay = calendar.component(.weekday, from: firstDay)
        let leading = (firstWkDay - calendar.firstWeekday + 7) % 7
        
        var result = [Date?]()
        for _ in 0..<leading {
            result.append(nil)
        }
        for day in 1...range.count {
            if let actualDate = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                result.append(actualDate)
            }
        }
        return result
    }
    
    private func spendingOnDay(_ date: Date) -> Double {
        transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                    .map { $0.amount }
                    .reduce(0, +)
    }
    
    private func transactionsForDay(_ day: Date) -> [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            LazyVGrid(columns: columns, spacing: 8) {
                // Weekday headers
                ForEach(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"], id: \.self) { wd in
                    Text(wd)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                
                // Day cells
                ForEach(daysArray.indices, id: \.self) { i in
                    if let day = daysArray[i] {
                        let dNum = calendar.component(.day, from: day)
                        let spent = spendingOnDay(day)
                        NavigationLink(destination: DailyTransactionsView(
                            date: day,
                            transactions: transactionsForDay(day),
                            categories: categories
                        )) {
                            VStack(spacing: 4) {
                                Text("\(dNum)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if spent > 0 {
                                    Text(formatAmount(spent))
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                } else {
                                    Text("$0")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }
                    } else {
                        // Placeholder for empty cells
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(minHeight: 40)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Detail Screens

struct AllTransactionsView: View {
    @Binding var transactions: [Transaction]
    @Binding var categories: [CategoryBudget]
    let selectedMonth: Date
    
    var monthlyTx: [Transaction] {
        transactionsForMonth(transactions, selectedMonth: selectedMonth)
    }
    
    var body: some View {
        List {
            ForEach(monthlyTx) { tx in
                if let idx = transactions.firstIndex(where: { $0.id == tx.id }) {
                    NavigationLink {
                        EditTransactionView(
                            transaction: $transactions[idx],
                            categories: $categories
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tx.description)
                            Text(formatAmount(tx.amount))
                                .foregroundColor(.secondary)
                                .font(.footnote)
                            Text(tx.date, style: .date)
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .onDelete(perform: deleteTransaction)
        }
        .navigationTitle("\(monthYearFormatter.string(from: selectedMonth))")
    }
    
    private func deleteTransaction(at offsets: IndexSet) {
        let monthlyList = monthlyTx
        offsets.map { monthlyList[$0] }.forEach { tx in
            if let globalIdx = transactions.firstIndex(where: { $0.id == tx.id }) {
                transactions.remove(at: globalIdx)
            }
        }
    }
}

struct TransactionLogView: View {
    let category: CategoryBudget
    let transactions: [Transaction]
    let selectedMonth: Date
    
    var filteredTx: [Transaction] {
        transactionsForMonth(transactions, selectedMonth: selectedMonth)
            .filter { $0.categoryID == category.id }
    }
    
    var body: some View {
        List(filteredTx) { t in
            VStack(alignment: .leading, spacing: 4) {
                Text(t.description)
                Text(formatAmount(t.amount))
                    .foregroundColor(.secondary)
                    .font(.footnote)

                Text(t.date, style: .date)
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(category.name)
    }
}

struct EditTransactionView: View {
    @Binding var transaction: Transaction
    @Binding var categories: [CategoryBudget]
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCategoryIndex: Int = 0
    @State private var amountString: String = ""
    @State private var titleString: String = ""
    @State private var date = Date()
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Choose Category", selection: $selectedCategoryIndex) {
                        ForEach(categories.indices, id: \.self) { idx in
                            Text(categories[idx].name).tag(idx)
                        }
                    }
                }
                
                Section("Details") {
                    TextField("Transaction Title", text: $titleString)
                    TextField("Amount", text: $amountString)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                amountString = String(transaction.amount)
                titleString = transaction.description
                date = transaction.date
                selectedCategoryIndex = categories.firstIndex(where: { $0.id == transaction.categoryID }) ?? 0
            }
        }
    }
    
    private func saveChanges() {
        guard let newAmt = Double(amountString), newAmt >= 0 else {
            errorMessage = "Please enter a valid amount."
            return
        }
        transaction.amount = newAmt
        transaction.description = titleString
        transaction.date = date
        transaction.categoryID = categories[selectedCategoryIndex].id
        dismiss()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Binding var categories: [CategoryBudget]
    @Environment(\.dismiss) private var dismiss
    
    @State private var newCategoryName: String = ""
    @State private var newCategoryTotal: String = ""
    @State private var errorMessage: String = ""
    
    private let availableColors: [Color] = [
        .red, .green, .blue, .orange, .purple, .brown, .pink, .yellow, .mint, .indigo, .cyan
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Edit Existing Categories") {
                    ForEach($categories) { $category in
                        VStack(alignment: .leading) {
                            TextField("Category Name", text: $category.name)
                            TextField("Category Total", value: $category.total, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .onDelete(perform: deleteCategory)
                }
                
                Section("Add New Category") {
                    TextField("Name", text: $newCategoryName)
                    TextField("Total", text: $newCategoryTotal).keyboardType(.decimalPad)
                    
                    Button("Add Category") {
                        addCategory()
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func deleteCategory(at offsets: IndexSet) {
        categories.remove(atOffsets: offsets)
    }
    
    private func addCategory() {
        errorMessage = ""
        guard !newCategoryName.isEmpty else {
            errorMessage = "Please enter a category name."
            return
        }
        guard let tot = Double(newCategoryTotal) else {
            errorMessage = "Please enter a valid number for total."
            return
        }
        
        let color = nextAvailableColor()
        let newCat = CategoryBudget(name: newCategoryName, total: tot, color: color)
        categories.append(newCat)
        
        newCategoryName = ""
        newCategoryTotal = ""
    }
    
    private func nextAvailableColor() -> Color {
        let usedColors = Set(categories.map { $0.color.description })
        for c in availableColors {
            if !usedColors.contains(c.description) {
                return c
            }
        }
        return .gray
    }
}

// MARK: - Record Transaction
struct RecordTransactionView: View {
    let monthCategories: [CategoryBudget]    // <-- The categories for this month
    @Binding var transactions: [Transaction] // Still binding, so you can append
    let selectedMonth: Date
    let refreshRollover: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryIndex: Int = 0
    @State private var amountString: String = ""
    @State private var titleString: String = ""
    @State private var date = Date()
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    if monthCategories.isEmpty {
                        Text("No categories available for this month.")
                    } else {
                        Picker("Choose Category", selection: $selectedCategoryIndex) {
                            ForEach(monthCategories.indices, id: \.self) { i in
                                Text(monthCategories[i].name).tag(i)
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Transaction Title", text: $titleString)
                    TextField("Amount", text: $amountString)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("Record Transaction")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTransaction() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func saveTransaction() {
        guard !titleString.isEmpty else {
            errorMessage = "Please enter a transaction title."
            return
        }
        guard let amt = Double(amountString), amt > 0 else {
            errorMessage = "Please enter a valid amount."
            return
        }
        guard !monthCategories.isEmpty else {
            errorMessage = "No categories to select from."
            return
        }

        // Grab the user’s chosen category
        let chosenCategory = monthCategories[selectedCategoryIndex]
        
        // Create the transaction with that exact ID
        let newTx = Transaction(
            categoryID: chosenCategory.id,
            date: date,
            amount: amt,
            description: titleString
        )
        transactions.append(newTx)

        // Refresh rollover if needed
        refreshRollover()

        dismiss()
    }
}

// MARK: - Month Picker

struct MonthPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMonth: Date
    
    // Restrict years to 2025 through 2030.
    private let years = Array(2025...2030)
    private let months = Array(1...12)
    
    @State private var tempYear: Int = 2025
    @State private var tempMonth: Int = 1
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Choose Month").font(.title2).padding(.bottom, 8)
                
                HStack(spacing: 24) {
                    VStack {
                        Text("Year").font(.headline)
                        Picker("Year", selection: $tempYear) {
                            ForEach(years, id: \.self) { y in
                                Text("\(y)").tag(y)
                            }
                        }
                        .frame(maxHeight: 150)
                        .clipped()
                        .pickerStyle(.wheel)
                    }
                    VStack {
                        Text("Month").font(.headline)
                        Picker("Month", selection: $tempMonth) {
                            ForEach(months, id: \.self) { m in
                                Text(Calendar.current.monthSymbols[m-1])
                                    .tag(m)
                            }
                        }
                        .frame(maxHeight: 150)
                        .clipped()
                        .pickerStyle(.wheel)
                    }
                }
                .padding(.bottom, 16)
                
                Button("Done") {
                    applySelection()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 16)
            }
            .onAppear {
                let cal = Calendar.current
                let comps = cal.dateComponents([.year, .month], from: selectedMonth)
                tempYear = comps.year ?? 2025
                tempMonth = comps.month ?? 1
            }
        }
        .presentationDetents([.height(340), .medium, .large])
    }
    
    private func applySelection() {
        var comps = DateComponents()
        comps.year = tempYear
        comps.month = tempMonth
        comps.day = 1
        if let newDate = Calendar.current.date(from: comps) {
            selectedMonth = newDate
        }
    }
}


// MARK: - Component Cards

struct MonthSelectorCard: View {
    @Binding var selectedMonth: Date
    
    // Define the minimum allowable date (January 2025)
    var minDate: Date {
        Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1))!
    }
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    if let previous = previousMonth(of: selectedMonth) {
                        selectedMonth = previous
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                .disabled(selectedMonth <= minDate)
                Spacer()
                
                Text(monthYearFormatter.string(from: selectedMonth))
                    .font(.headline)
                    .bold()
                
                Spacer()
                
                Button(action: {
                    if let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) {
                        selectedMonth = next
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 4)
        .padding(.horizontal)
    }
}

struct RolloverBalanceCard: View {
    @Binding var monthlyBudgets: [String: [CategoryBudget]]
    @Binding var rolloverLeftover: Double
    @Binding var categories: [CategoryBudget]
    @Binding var goals: [SavingsGoal]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation]
    @Binding var savingsRecords: [SavingsRecord]
    let overallBudget: Double
    let selectedMonth: Date
    
    @Binding var rolloverSpentByMonth: [String: Double]
    
    let refreshRollover: () -> Void
    
    var body: some View {
        NavigationLink {
            if let monthCategories = monthlyBudgets[monthKey(for: selectedMonth)], !monthCategories.isEmpty {
                RolloverDetailView(
                    rolloverLeftover: $rolloverLeftover,
                    monthCategories: monthCategories,
                    goals: $goals,
                    transactions: $transactions,
                    allocations: $allocations,
                    overallBudget: overallBudget,
                    selectedMonth: selectedMonth,
                    rolloverSpentByMonth: $rolloverSpentByMonth,
                    savingsRecords: $savingsRecords,
                    refreshRollover: refreshRollover
                )

            } else {
                // Show some placeholder if there are no categories for this month:
                Text("No categories found for this month.")
            }
        } label: {
            HStack {
                Text("Rollover Balance")
                    .font(.headline)
                
                Spacer()
                
                Text("$\(Int(rolloverLeftover))")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 4)
        .padding(.horizontal)
    }
}

//struct CategoriesCard: View {
//    @Binding var categories: [CategoryBudget]
//    @Binding var transactions: [Transaction]
//    @Binding var allocations: [CategoryAllocation]
//    let selectedMonth: Date
//
//    private var monthlyTransactions: [Transaction] {
//        transactionsForMonth(transactions, selectedMonth: selectedMonth)
//    }
//
//    private var spentByCategory: [UUID: Double] {
//        monthlySpentByCategory(categories: categories, transactions: monthlyTransactions)
//    }
//
//    var body: some View {
//        VStack(spacing: 8) {
//            NavigationLink {
//                AllTransactionsView(
//                    transactions: $transactions,
//                    categories: $categories,
//                    selectedMonth: selectedMonth
//                )
//            } label: {
//                HStack {
//                    OverallBudgetRow(
//                        categories: categories,
//                        monthlySpentByCategory: spentByCategory
//                    )
//                    Image(systemName: "chevron.right")
//                        .foregroundColor(.secondary)
//                }
//                .padding(.horizontal)
//            }
//
//            ForEach(categories) { cat in
//                NavigationLink {
//                    TransactionLogView(
//                        category: cat,
//                        transactions: transactions,
//                        selectedMonth: selectedMonth
//                    )
//                } label: {
//                    HStack {
//                        CategoryRow(
//                            category: cat,
//                            spentThisMonth: spentByCategory[cat.id] ?? 0
//                        )
//                        Image(systemName: "chevron.right")
//                            .foregroundColor(.secondary)
//                    }
//                    .padding(.horizontal)
//                }
//            }
//        }
//        .padding(.vertical)
//        .background(Color(.systemBackground))
//        .cornerRadius(10)
//        .shadow(radius: 4)
//        .padding(.horizontal)
//    }
//}
struct CategoriesCard: View {
    @Binding var monthlyBudgets: [String: [CategoryBudget]]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation] // <-- Add this line so we can see allocations
    let selectedMonth: Date
    
    var body: some View {
        // We must compute these in `body`, rather than in property initializers
        let key = monthKey(for: selectedMonth)
        
        // Filter all allocations for `selectedMonth`
        let monthAllocs = allocations.filter { sameMonth($0.month, selectedMonth) }
        
        // Build a dictionary: categoryID -> allocatedAmount
        let allocDict: [UUID: Double] = Dictionary(
            uniqueKeysWithValues: monthAllocs.map { ($0.categoryID, $0.allocatedAmount) }
        )
        
        // Check if we have categories for this month
        if let monthCategories = monthlyBudgets[key], !monthCategories.isEmpty {
            
            // Show the standard categories list
            let spentByCategory = monthlySpentByCategory(
                categories: monthCategories,
                transactions: transactionsForMonth(transactions, selectedMonth: selectedMonth)
            )
            
            // Sum total allocated across all categories
            let totalAllocated = monthCategories.reduce(0) { acc, cat in
//                acc + (allocDict[cat.id] ?? cat.total)
                acc + (cat.total + (allocDict[cat.id] ?? 0))
            }
            let totalSpent = spentByCategory.values.reduce(0, +)
            
            VStack(spacing: 8) {
                NavigationLink {
                    AllTransactionsView(
                        transactions: .constant(transactions),
                        categories: .constant(monthCategories),
                        selectedMonth: selectedMonth
                    )
                } label: {
                    HStack {
                        OverallBudgetRow(
                            totalAllocated: totalAllocated,
                            totalSpent: totalSpent
                        )
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                ForEach(monthCategories) { cat in
                    NavigationLink {
                        TransactionLogView(
                            category: cat,
                            transactions: transactions,
                            selectedMonth: selectedMonth
                        )
                    } label: {
                        HStack {
                            CategoryRow(
                                category: cat,
                                spentThisMonth: spentByCategory[cat.id] ?? 0,
                                allocatedAmount: cat.total + (allocDict[cat.id] ?? 0)
                            )
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(radius: 4)
            .padding(.horizontal)
            
        } else {
            // Show the "blank" state with two icons
            VStack(spacing: 20) {
                Text("No Budget for \(monthYearFormatter.string(from: selectedMonth))")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 50) {
                    // 1) Copy previous month’s categories
                    Button {
                        copyPreviousMonth()
                    } label: {
                        VStack {
                            Image(systemName: "arrow.up.doc.on.clipboard")
                                .font(.system(size: 36))
                            Text("Copy Previous")
                                .font(.subheadline)
                        }
                    }
                    
                    // 2) Create a new budget for this month
                    Button {
                        createNewBudget()
                    } label: {
                        VStack {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 36))
                            Text("New Budget")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(radius: 4)
            .padding(.horizontal)
        }
    }
    
    // Helper to copy the categories from the immediately preceding month
    private func copyPreviousMonth() {
        guard let prev = previousMonth(of: selectedMonth) else { return }
        let prevKey = monthKey(for: prev)
        let thisKey = monthKey(for: selectedMonth)
        
        // If the previous month exists, copy them.
        if let prevCategories = monthlyBudgets[prevKey] {
            // Make deep copies with new IDs
            let newSet = prevCategories.map { oldCat in
                CategoryBudget(
                    id: UUID(),
                    name: oldCat.name,
                    total: oldCat.total,
                    color: oldCat.color
                )
            }
            monthlyBudgets[thisKey] = newSet
        } else {
            // If there's truly no data for the previous month, just make it empty
            monthlyBudgets[thisKey] = []
        }
    }
    
    // Helper to create a brand-new budget (show a quick function or pass to a sheet, etc.)
    private func createNewBudget() {
        let thisKey = monthKey(for: selectedMonth)
        // For now, we’ll just set it to an empty array.
        monthlyBudgets[thisKey] = []
    }
}

struct CalendarCard: View {
    let transactions: [Transaction]
    let selectedMonth: Date
    let categories: [CategoryBudget] // New parameter added
    
    var body: some View {
        VStack(spacing: 16) {
            MonthlyCalendarView(
                month: selectedMonth,
                transactions: transactionsForMonth(transactions, selectedMonth: selectedMonth),
                categories: categories // Passing categories
            )
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 4)
        .padding(.horizontal)
    }
}

struct RecordTransactionButton: View {
    @Binding var showRecordTransaction: Bool
    
    var body: some View {
        Button(action: {
            showRecordTransaction = true
        }) {
            Text("Record Transaction")
                .font(.headline) // Match category card's font
                .foregroundColor(.white)
                .padding(.horizontal, 100) // Internal padding for consistent spacing
                .frame(minHeight: 35) // Increased height for prominence
                .background(Color.blue)
                .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2) // Added shadow for consistency
    }
}

// MARK: - ContentView

struct ContentView: View {
    
    @Environment(\.scenePhase) var scenePhase
    
    @State private var rolloverSpentByMonth: [String: Double] = [:]
    
    @State private var categories: [CategoryBudget] = [
        CategoryBudget(name: "Housing", total: 2400, color: .yellow),
        CategoryBudget(name: "Transportation", total: 700, color: .green),
        CategoryBudget(name: "Groceries", total: 900, color: .orange),
        CategoryBudget(name: "Healthcare", total: 200, color: .red),
        CategoryBudget(name: "Entertainment", total: 700, color: .purple),
        CategoryBudget(name: "Misc", total: 500, color: .brown)
    ]
    
    @State private var allocations: [CategoryAllocation] = []
    /// A dictionary of "YYYY-MM" string -> array of CategoryBudget for that month.
    /// Example key: "2024-12"
    @State private var monthlyBudgets: [String: [CategoryBudget]] = [:]
    @State private var transactions: [Transaction] = []
    @State private var savingsRecords: [SavingsRecord] = []

    @State private var selectedMonth = Date()
    @AppStorage("globalRolloverLeftover") private var storedRollover: Double = 0

    @State private var rolloverLeftover: Double = 0 {
        didSet {
            // Each time this changes, save to AppStorage
            storedRollover = rolloverLeftover
        }
    }

    @State private var showRecordTransaction = false
    @State private var showMonthPicker = false

    // Call this function to save all your main data arrays.
    func saveAllData() {
        saveData(categories, filename: "categories.json")
        saveData(allocations, filename: "allocations.json")
        saveData(monthlyBudgets, filename: "monthlyBudgets.json")
        saveData(transactions, filename: "transactions.json")
        saveData(savingsRecords, filename: "savingsRecords.json")
    }

    
    private var overallBudget: Double {
        // Build a dictionary of transfers for the selected month keyed by category.
        let allocDict = Dictionary(
            uniqueKeysWithValues: allocations.filter { sameMonth($0.month, selectedMonth) }
                                             .map { ($0.categoryID, $0.allocatedAmount) }
        )
        // For each category, add its base total plus any transferred funds.
        return categories.reduce(0) { sum, cat in
            sum + (cat.total + (allocDict[cat.id] ?? 0))
        }
    }


    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        MonthSelectorCard(selectedMonth: $selectedMonth)
                        RolloverBalanceCard(
                            monthlyBudgets: $monthlyBudgets,
                            rolloverLeftover: $rolloverLeftover,
                            categories: $categories,
                            goals: $goals,
                            transactions: $transactions,
                            allocations: $allocations,
                            savingsRecords: $savingsRecords,
                            overallBudget: overallBudget,
                            selectedMonth: selectedMonth,
                            rolloverSpentByMonth: $rolloverSpentByMonth,
                            refreshRollover: {
                                updateRolloverLeftover()
                            }
                        )
                        CategoriesCard(
                            monthlyBudgets: $monthlyBudgets,
                            transactions: $transactions,
                            allocations: $allocations, // Add this argument
                            selectedMonth: selectedMonth
                        )

                        CalendarCard(
                            transactions: transactions,
                            selectedMonth: selectedMonth,
                            categories: categories // Passing categories
                        )

                    }

//                    .padding(.top, 8) // Reduced top padding from default to 8 points
                }

                // just removed this REESE
//                VStack {
//                    Spacer()
//                    RecordTransactionButton(showRecordTransaction: $showRecordTransaction)
//                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 40) { // Adjust spacing as needed for even distribution
                        // Goals Icon
                        NavigationLink(destination: GoalsView(goals: $goals)) {
                            Image(systemName: "dollarsign.bank.building.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }

                        // Shared Goals Icon (Non-functional for now)
                        Button(action: {
                            // Future functionality for Shared Goals
                        }) {
                            Image(systemName: "wallet.bifold.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }

                        // Transactions Icon (Navigates to All Data View)
                        NavigationLink(destination: TransactionsAndAllocationsView(transactions: transactions, allocations: allocations, savingsRecords: savingsRecords)) {
                            Image(systemName: "list.bullet")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }

                        // In ContentView toolbar (where you have NavigationLink to SettingsView):
                        NavigationLink(destination: SettingsView(categories: $categories)) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }

                    }
                    .frame(maxWidth: .infinity) // Ensures the HStack takes full width for even spacing
                }
                // New ToolbarItem for the Record Transaction Button in the footer
                    ToolbarItem(placement: .bottomBar) {
                        RecordTransactionButton(showRecordTransaction: $showRecordTransaction)
                    }
            }

            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .inactive || newPhase == .background {
                saveAllData()
            }
        }

        .onChange(of: selectedMonth) { _ in updateRolloverLeftover() }
        .onAppear {
            // Load persisted data or use defaults if not present.
            if let loadedCategories = loadData(filename: "categories.json", as: [CategoryBudget].self) {
                categories = loadedCategories
            }
            
            if let loadedAllocations = loadData(filename: "allocations.json", as: [CategoryAllocation].self) {
                allocations = loadedAllocations
            }
            
            if let loadedMonthlyBudgets = loadData(filename: "monthlyBudgets.json", as: [String: [CategoryBudget]].self) {
                monthlyBudgets = loadedMonthlyBudgets
            }
            
            if let loadedTransactions = loadData(filename: "transactions.json", as: [Transaction].self) {
                transactions = loadedTransactions
            }
            
            if let loadedSavingsRecords = loadData(filename: "savingsRecords.json", as: [SavingsRecord].self) {
                savingsRecords = loadedSavingsRecords
            }
            
            rolloverLeftover = storedRollover

            // Ensure December 2024 has a default budget.
            let dec2024Key = "2024-12"
            if monthlyBudgets[dec2024Key] == nil {
                monthlyBudgets[dec2024Key] = [
                    CategoryBudget(name: "Housing", total: 2400, color: .yellow),
                    CategoryBudget(name: "Transportation", total: 700, color: .green),
                    CategoryBudget(name: "Groceries", total: 900, color: .orange),
                    CategoryBudget(name: "Healthcare", total: 200, color: .red),
                    CategoryBudget(name: "Entertainment", total: 700, color: .purple),
                    CategoryBudget(name: "Misc", total: 500, color: .brown)
                ]
            }

            // Initialize January 2025 with December 2024's budget if it doesn't exist.
            let jan2025Key = "2025-01"
            if monthlyBudgets[jan2025Key] == nil {
                if let decBudget = monthlyBudgets[dec2024Key] {
                    let newBudget = decBudget.map { oldCat in
                        CategoryBudget(
                            id: UUID(),  // Assign a new unique ID
                            name: oldCat.name,
                            total: oldCat.total,
                            color: oldCat.color
                        )
                    }
                    monthlyBudgets[jan2025Key] = newBudget
                } else {
                    // Fallback default if December 2024 budget is missing
                    monthlyBudgets[jan2025Key] = [
                        CategoryBudget(name: "Housing", total: 2400, color: .yellow),
                        CategoryBudget(name: "Transportation", total: 700, color: .green),
                        CategoryBudget(name: "Groceries", total: 900, color: .orange),
                        CategoryBudget(name: "Healthcare", total: 200, color: .red),
                        CategoryBudget(name: "Entertainment", total: 700, color: .purple),
                        CategoryBudget(name: "Misc", total: 500, color: .brown)
                    ]
                }
            }
            
            loadGoals()
            updateRolloverLeftover()
        }
        .sheet(isPresented: $showRecordTransaction) {
            let key = monthKey(for: selectedMonth)
            if let categoriesForThisMonth = monthlyBudgets[key], !categoriesForThisMonth.isEmpty {
                RecordTransactionView(
                    monthCategories: categoriesForThisMonth,
                    transactions: $transactions,
                    selectedMonth: selectedMonth,
                    refreshRollover: updateRolloverLeftover
                )
            } else {
                // If there are NO categories for this month, you could display
                // some placeholder view (or your "Create New Budget" flow):
                Text("No categories for this month.")
                    .padding()
            }
        }

        .sheet(isPresented: $showMonthPicker) {
            MonthPickerView(selectedMonth: $selectedMonth)
        }
    }
    
    func updateRolloverLeftover() {
        // Set the base date to January 2025
        let startDate = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        
        // If the selected month IS January 2025, then no rollover is carried over.
        if selectedMonth == startDate {
            rolloverLeftover = 0
            return
        }
        
        rolloverLeftover = 0
        var loopMonth = selectedMonth
        // Process only months later than January 2025
        while loopMonth > startDate {
            // Use previous month’s transactions only if the previous month is on or after January 2025.
            if let prev = previousMonth(of: loopMonth), prev >= startDate {
                let monthTx = transactionsForMonth(transactions, selectedMonth: prev)
                let leftoverValue = leftoverForMonth(
                    monthlyBudgets: monthlyBudgets,
                    allocations: allocations,
                    rolloverSpentByMonth: rolloverSpentByMonth,
                    selectedMonth: loopMonth,
                    monthTransactions: monthTx
                )
                rolloverLeftover += leftoverValue
            }
            
            // Move one month back; if that goes before January 2025, break out.
            if let newLoop = previousMonth(of: loopMonth), newLoop >= startDate {
                loopMonth = newLoop
            } else {
                break
            }
        }
        // Subtract extra allocations made in the current (selected) month
            let currentExtra = allocations
                .filter { sameMonth($0.month, selectedMonth) }
                .reduce(0) { $0 + $1.allocatedAmount }
            rolloverLeftover -= currentExtra
    }



    @AppStorage("savingsGoals") private var goalsData: Data = Data()
    @State private var goals: [SavingsGoal] = [] {
        didSet {
            saveGoals()
        }
    }
    
    private func saveGoals() {
        do {
            let data = try JSONEncoder().encode(goals)
            goalsData = data
        } catch {
            print("Error saving goals: \(error)")
        }
    }

    private func loadGoals() {
        guard !goalsData.isEmpty else { return }
        do {
            goals = try JSONDecoder().decode([SavingsGoal].self, from: goalsData)
        } catch {
            print("Error loading goals: \(error)")
        }
    }

}

// MARK: - Goals View

struct GoalsView: View {
    @Binding var goals: [SavingsGoal]
    @State private var showAddGoalMenu = false

    var body: some View {
        NavigationStack {
            VStack {
                if goals.isEmpty {
                    // Display a placeholder when there are no goals
                    ContentUnavailableView("No Goals", systemImage: "plus.circle")
                        .padding()
                } else {
                    // Use ScrollView with LazyVStack to display GoalCardViews
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach($goals) { $goal in
                                GoalCardView(goal: $goal, onDelete: {
                                    if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                                        goals.remove(at: index)
                                    }
                                })
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddGoalMenu = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddGoalMenu) {
                AddGoalView(goals: $goals)
            }
            .navigationTitle("Savings Goals")
        }
    }
}



struct AddGoalView: View {
    @Binding var goals: [SavingsGoal]
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amount = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Title", text: $title)
                    TextField("Target Amount", text: $amount)
                        .keyboardType(.decimalPad)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoal()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveGoal() {
        guard !title.isEmpty else {
            errorMessage = "Please enter a title"
            return
        }
        
        guard let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Please enter a valid amount"
            return
        }
        
        let newGoal = SavingsGoal(
            title: title,
            targetAmount: amountValue,
            currentAmount: 0
        )
        
        goals.append(newGoal)
        dismiss()
    }
}


// MARK: - Daily Transactions View

struct DailyTransactionsView: View {
    let date: Date
    let transactions: [Transaction]
    let categories: [CategoryBudget]
    
    // DateFormatter to display the date in a user-friendly format
    fileprivate let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .long
        return df
    }()
    
    var body: some View {
        List {
            if transactions.isEmpty {
                Text("No transactions for this day.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(transactions) { tx in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tx.description)
                                .font(.headline)
                            Text(tx.date, style: .time)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(categoryName(for: tx.categoryID))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(formatAmount(tx.amount))
                            .foregroundColor(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
//        .navigationTitle("Transactions on \(dayFormatter.string(from: date))")
        .navigationTitle("\(dayFormatter.string(from: date))")
    }
    
    /// Helper function to retrieve the category name based on categoryID
    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unknown Category"
    }
}


// MARK: - Rollover Detail Screen

/// Shows the current rollover leftover plus a short explanation of how it’s calculated.
/// Also has a button to transfer funds from/to the rollover.
struct RolloverDetailView: View {
    @Binding var rolloverLeftover: Double
    let monthCategories: [CategoryBudget]
    @Binding var goals: [SavingsGoal]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation]
    let overallBudget: Double
    let selectedMonth: Date
    
    @Binding var rolloverSpentByMonth: [String: Double]
    @Binding var savingsRecords: [SavingsRecord]
    
    // ADD THIS:
    let refreshRollover: () -> Void
    
    @State private var showTransfer = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Current Rollover Balance") {
                    Text("$\(Int(rolloverLeftover))")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Section("How is this calculated?") {
                    Text("""
                    1. We look at the previous month's leftover = (last month's total budget) - (spent last month).
                    2. We add that leftover to any leftover that was already carried forward.
                    """)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                
                Section("Transfer Rollover") {
                    Button("Transfer to Category or Goal") {
                        showTransfer = true
                    }
                }
            }
            .sheet(isPresented: $showTransfer) {
                TransferFundsView(
                    rolloverLeftover: $rolloverLeftover,
                    monthCategories: monthCategories,
                    goals: $goals,
                    transactions: $transactions,
                    allocations: $allocations,
                    rolloverSpentByMonth: $rolloverSpentByMonth,
                    savingsRecords: $savingsRecords,
                    selectedMonth: selectedMonth,
                    refreshRollover: refreshRollover
                )
            }

        }
    }
}

// MARK: - TransferFundsView

struct TransferFundsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var rolloverLeftover: Double
    
    let monthCategories: [CategoryBudget]
    @Binding var goals: [SavingsGoal]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation]
    @Binding var rolloverSpentByMonth: [String: Double]
    @Binding var savingsRecords: [SavingsRecord]  // New binding
    let selectedMonth: Date
    
    @State private var amountString = ""
    @State private var errorMessage = ""
    @State private var transferToGoal = false
    
    @State private var selectedGoalIndex = 0
    @State private var selectedCategoryIndex = 0
    
    let refreshRollover: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Transfer From") {
                    Text("Rollover Balance: $\(Int(rolloverLeftover))")
                }
                
                Section("Transfer To") {
                    Picker("Destination", selection: $transferToGoal) {
                        Text("Category").tag(false)
                        Text("Goal").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    if transferToGoal {
                        Picker("Select Goal", selection: $selectedGoalIndex) {
                            ForEach(goals.indices, id: \.self) { idx in
                                Text(goals[idx].title).tag(idx)
                            }
                        }
                    } else {
                        if monthCategories.isEmpty {
                            Text("No categories for this month.")
                        } else {
                            Picker("Select Category", selection: $selectedCategoryIndex) {
                                ForEach(monthCategories.indices, id: \.self) { idx in
                                    Text(monthCategories[idx].name).tag(idx)
                                }
                            }
                        }
                    }
                }
                
                Section("Amount") {
                    TextField("Amount", text: $amountString)
                        .keyboardType(.decimalPad)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Transfer Funds")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") { performTransfer() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func performTransfer() {
        guard let amount = Double(amountString), amount > 0 else {
            errorMessage = "Please enter a valid amount."
            return
        }
        guard amount <= rolloverLeftover else {
            errorMessage = "Amount exceeds current rollover."
            return
        }
        
        if transferToGoal {
            goals[selectedGoalIndex].currentAmount += amount
            // Add a savings record for this transfer.
            let newRecord = SavingsRecord(goalID: goals[selectedGoalIndex].id, date: Date(), amount: amount, description: "Transfer from rollover")
            savingsRecords.append(newRecord)
        } else {
            guard !monthCategories.isEmpty else {
                errorMessage = "No categories for this month."
                return
            }
            let chosenCat = monthCategories[selectedCategoryIndex]
            if let i = allocations.firstIndex(where: {
                $0.categoryID == chosenCat.id && sameMonth($0.month, selectedMonth)
            }) {
                allocations[i].allocatedAmount += amount
            } else {
                let firstOfThisMonth = Calendar.current.date(
                    from: Calendar.current.dateComponents([.year, .month], from: selectedMonth)
                )!
                allocations.append(CategoryAllocation(
                    categoryID: chosenCat.id,
                    month: firstOfThisMonth,
                    allocatedAmount: amount
                ))
            }
        }
        
        let key = monthKey(for: selectedMonth)
        if transferToGoal {
            rolloverSpentByMonth[key, default: 0] += amount
        }
        rolloverLeftover -= amount
        refreshRollover()
        dismiss()

    }
}


struct TransactionsAndAllocationsView: View {
    let transactions: [Transaction]
    let allocations: [CategoryAllocation]
    let savingsRecords: [SavingsRecord]
    
    @State private var selectedSegment = 0
    
    var sortedTransactions: [Transaction] {
        transactions.sorted { $0.date < $1.date }
    }
    
    var sortedAllocations: [CategoryAllocation] {
        allocations.sorted { $0.month < $1.month }
    }
    
    var sortedSavings: [SavingsRecord] {
        savingsRecords.sorted { $0.date < $1.date }
    }
    
    var body: some View {
        VStack {
            Picker("Select", selection: $selectedSegment) {
                Text("Transactions").tag(0)
                Text("Allocations").tag(1)
                Text("Savings").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            List {
                if selectedSegment == 0 {
                    Section(header: Text("Transactions").font(.headline)) {
                        ForEach(sortedTransactions) { tx in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tx.description)
                                Text("Amount: \(formatAmount(tx.amount))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(tx.date, style: .date)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else if selectedSegment == 1 {
                    Section(header: Text("Allocations").font(.headline)) {
                        ForEach(sortedAllocations) { alloc in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Category ID: \(alloc.categoryID.uuidString.prefix(8))")
                                Text("Allocated: \(formatAmount(alloc.allocatedAmount))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(alloc.month, style: .date)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else if selectedSegment == 2 {
                    Section(header: Text("Savings").font(.headline)) {
                        ForEach(sortedSavings) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Goal ID: \(record.goalID.uuidString.prefix(8))")
                                Text("Amount: \(formatAmount(record.amount))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(record.date, style: .date)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Text(record.description)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
        .navigationTitle("All Data")
    }
}



// MARK: - Helpers

extension Date {
    /// Returns a new Date at midnight on the first of this Date's month.
    func startOfMonth() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: comps) ?? self
    }
}

#Preview {
    ContentView()
}


