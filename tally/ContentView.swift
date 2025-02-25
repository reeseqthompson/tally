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

extension Color {
    static func cardBackground(for scheme: ColorScheme) -> Color {
        // In light mode, the card is “primary” (systemBackground) and in dark mode, it’s “secondary” (a darker gray)
        return scheme == .light ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground)
    }
    
    static func viewBackground(for scheme: ColorScheme) -> Color {
        // In light mode, the overall background is “secondary” (light gray) and in dark mode, it’s “primary” (black)
        return scheme == .light ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemBackground)
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
    
//    var color: Color {
//        get { Color.blue }
//        set { }  // ignore attempts to change the color
//    }

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
    let sign = amount < 0 ? "-" : ""
    let absAmount = abs(amount)
    if absAmount >= 1000 {
        let formatted = (absAmount / 1000).rounded(toPlaces: 1)
        return "$\(sign)\(formatted)k"
    } else {
        let formatted = Int(absAmount.rounded())
        return "$\(sign)\(formatted)"
    }
}

func formatPreciseAmount(_ amount: Double) -> String {
    let sign = amount < 0 ? "-" : ""
    let absAmount = abs(amount)
    return "$\(sign)\(String(format: "%.2f", absAmount))"
}


// Extension to round a Double to a specified number of decimal places.
extension Double {
    /// Rounds the double to decimal places value
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

// MARK: - Row Views

/// Displays a bar comparing "spent" vs. "category.total."
struct CategoryRow: View {
    let category: CategoryBudget
    let spentThisMonth: Double
    let allocatedAmount: Double

    private var fractionUsed: Double {
        guard allocatedAmount > 0 else { return 0 }
        return min(max(spentThisMonth / allocatedAmount, 0), 1)
    }
    private var fractionRemaining: Double {
        1 - fractionUsed
    }
    private var remainingDisplay: Double {
        allocatedAmount - spentThisMonth
    }

    // Fill color based on how much is left
    private var fillColor: Color {
        switch fractionRemaining {
        case 0.5...:       return .green
        case 0.2..<0.5:    return .yellow
        default:           return .red
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Gray background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))

                // The fill bar (just a plain Rectangle)
                Rectangle()
                    .fill(fillColor)
                    .frame(width: geo.size.width * fractionRemaining)

                // Text on top
                HStack {
                    let textColor: Color = (remainingDisplay < 0) ? .red : .white
                    Text(category.name)
                        .foregroundColor(textColor)
                        .padding(.leading, 8)
                    Spacer()
                    Text("\(formatAmount(remainingDisplay)) / \(formatAmount(allocatedAmount))")
                        .foregroundColor(textColor)
                        .padding(.trailing, 8)
                }
            }
            // <— Clip the entire ZStack to a rounded rectangle
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(height: 30)
    }
}


/// An overall bar for all categories combined in a month.
struct OverallBudgetRow: View {
    let totalAllocated: Double
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
                // Gray background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))

                // The fill bar
                Rectangle()
                    .fill(Color.teal)
                    .frame(width: geo.size.width * fractionRemaining)

                // Text on top
                HStack {
                    let textColor: Color = (remaining < 0) ? .red : .white
                    Text("Overall Budget")
                        .foregroundColor(textColor)
                        .padding(.leading, 8)
                    Spacer()
                    Text("\(formatAmount(remaining)) / \(formatAmount(totalAllocated))")
                        .foregroundColor(textColor)
                        .padding(.trailing, 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(height: 30)
    }
}

// MARK: - Goal Card View

struct GoalCardView: View {
    @Environment(\.colorScheme) var colorScheme
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
                .accentColor(.blue)
        }
        .padding()
        // Use the cardBackground for consistency with your other card views.
        .background(Color.cardBackground(for: colorScheme))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

// MARK: - Goals View

struct GoalsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var goals: [SavingsGoal]
    @State private var showAddGoalMenu = false
    @State private var editingGoalIndex: Int? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.viewBackground(for: colorScheme)
                    .ignoresSafeArea()
                
                if goals.isEmpty {
                    Button(action: {
                        showAddGoalMenu = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            Text("No Goals")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .padding()
                    }
                } else {
                    List {
                        ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                            GoalCardView(goal: $goals[index], onDelete: { })
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    // Swap the order: first Edit, then Delete
                                    Button {
                                        editingGoalIndex = index
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                    
                                    if goal.currentAmount == 0 {
                                        Button(role: .destructive) {
                                            goals.remove(at: index)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    // Remove the List's background so the cards fill the width
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
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
            .sheet(isPresented: Binding(
                get: { editingGoalIndex != nil },
                set: { if !$0 { editingGoalIndex = nil } }
            )) {
                if let index = editingGoalIndex {
                    EditGoalView(goal: $goals[index])
                }
            }
            .navigationTitle("Savings Goals")
        }
    }
}


// MARK: - Edit Goal View

/// Presents a sheet allowing the user to edit a savings goal’s title and target amount.
struct EditGoalView: View {
    @Binding var goal: SavingsGoal
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var targetAmountString: String = ""
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Goal Title", text: $title)
                    TextField("Target Amount", text: $targetAmountString)
                        .keyboardType(.decimalPad)
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Edit Goal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                title = goal.title
                targetAmountString = String(goal.targetAmount)
            }
        }
    }
    
    private func save() {
        guard let newTarget = Double(targetAmountString), newTarget > 0 else {
            errorMessage = "Please enter a valid target amount."
            return
        }
        // Ensure new target is not less than the current amount allocated
        if newTarget < goal.currentAmount {
            errorMessage = "Target amount cannot be lower than the current saved amount (\(formatAmount(goal.currentAmount)))."
            return
        }
        goal.title = title
        goal.targetAmount = newTarget
        dismiss()
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
    
    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unknown Category"
    }
    
    var body: some View {
        List {
            ForEach(monthlyTx) { tx in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tx.description)
                            .font(.headline)
                        Text("\(categoryName(for: tx.categoryID)) • \(formatDate(tx.date))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(formatPreciseAmount(tx.amount))
                        .foregroundColor(.red)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("\(monthYearFormatter.string(from: selectedMonth))")
    }
}


struct TransactionLogView: View {
    @Environment(\.dismiss) var dismiss
    let category: CategoryBudget
    let transactions: [Transaction]
    let selectedMonth: Date
    
    var filteredTx: [Transaction] {
        transactionsForMonth(transactions, selectedMonth: selectedMonth)
            .filter { $0.categoryID == category.id }
    }
    
    var body: some View {
        List(filteredTx) { t in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.description)
                        .font(.headline)
                    // Display the transaction date
                    Text(formatDate(t.date))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(formatPreciseAmount(t.amount))
                    .foregroundColor(.red)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(category.name)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width > 50 {
                        dismiss()
                    }
                }
        )
    }
}


struct EditTransactionView: View {
    @Binding var transaction: Transaction
    let monthBudgets: [String: [CategoryBudget]]
    let globalCategories: [CategoryBudget]
    
    @State private var selectedCategoryIndex: Int = 0
    @State private var amountString: String = ""
    @State private var titleString: String = ""
    @State private var date: Date = Date()
    @State private var errorMessage: String = ""
    
    // Compute the list of categories based on the (possibly updated) date.
    var currentMonthCategories: [CategoryBudget] {
        let key = monthKey(for: date)
        return monthBudgets[key] ?? globalCategories
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Choose Category", selection: $selectedCategoryIndex) {
                        ForEach(currentMonthCategories.indices, id: \.self) { idx in
                            Text(currentMonthCategories[idx].name).tag(idx)
                        }
                    }
                }
                
                Section("Details") {
                    TextField("Transaction Title", text: $titleString)
                    TextField("Amount", text: $amountString)
                        .keyboardType(.decimalPad)
                    // Use a standard DatePicker (the range is not restricted here because the user may edit the date)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .onChange(of: date) { newDate in
                            // When the date changes, update the picker’s list.
                            // If the current transaction.categoryID is not in the new list, default to the first category.
                            let cats = currentMonthCategories
                            if !cats.contains(where: { $0.id == transaction.categoryID }) {
                                selectedCategoryIndex = 0
                            } else if let idx = cats.firstIndex(where: { $0.id == transaction.categoryID }) {
                                selectedCategoryIndex = idx
                            }
                        }
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
                // Set the initial selected index based on the transaction's category and its month.
                let cats = currentMonthCategories
                if let idx = cats.firstIndex(where: { $0.id == transaction.categoryID }) {
                    selectedCategoryIndex = idx
                } else {
                    selectedCategoryIndex = 0
                }
            }
        }
    }
    
    @Environment(\.dismiss) private var dismiss
    
    private func saveChanges() {
        guard let newAmt = Double(amountString), newAmt >= 0 else {
            errorMessage = "Please enter a valid amount."
            return
        }
        transaction.amount = newAmt
        transaction.description = titleString
        transaction.date = date
        let cats = currentMonthCategories
        if cats.indices.contains(selectedCategoryIndex) {
            transaction.categoryID = cats[selectedCategoryIndex].id
        }
        dismiss()
    }
}


// MARK: - Settings
struct SettingsView: View {
    // Bind the entire monthlyBudgets dictionary, the global categories,
    // and also the transactions and allocations for the selected month.
    @Binding var monthlyBudgets: [String: [CategoryBudget]]
    @Binding var globalCategories: [CategoryBudget]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation]
    
    // The month for which we are editing the budget.
    let selectedMonth: Date
    
    // Local state copy for editing the monthly budget.
    @State private var editedBudget: [CategoryBudget] = []
    @State private var errorMessage: String = ""
    @Environment(\.dismiss) private var dismiss
    
    // Computed property: true if there is any transaction or allocation in this month.
    private var hasBudgetData: Bool {
        let tx = transactionsForMonth(transactions, selectedMonth: selectedMonth)
        let alloc = allocations.filter { sameMonth($0.month, selectedMonth) }
        return !tx.isEmpty || !alloc.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Edit Budget Categories for \(monthYearFormatter.string(from: selectedMonth))")) {
                    ForEach(editedBudget.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            TextField("Category Name", text: $editedBudget[index].name)
                            HStack {
                                Text("Allocation:")
                                TextField("Amount", value: $editedBudget[index].total, format: .number)
                                    .keyboardType(.decimalPad)
                            }
                        }
                    }
                    .onDelete(perform: deleteCategory)
                }
                
                Section {
                    Button("Add Category") {
                        addCategory()
                    }
                }
                
                // NEW: Section for deleting the entire monthly budget.
                if !hasBudgetData {
                    Section {
                        Button(role: .destructive) {
                            // Delete this month’s budget by removing the key from the dictionary
                            let key = monthKey(for: selectedMonth)
                            monthlyBudgets.removeValue(forKey: key)
                            dismiss()
                        } label: {
                            Text("Delete Budget")
                        }
                    }
                } else {
                    Section {
                        Text("Budget cannot be deleted because there are transactions or allocations for this month.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Budget Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                let key = monthKey(for: selectedMonth)
                if let currentBudget = monthlyBudgets[key] {
                    editedBudget = currentBudget
                } else {
                    editedBudget = globalCategories
                }
            }
        }
    }
    
    private func addCategory() {
        let newCategory = CategoryBudget(name: "New Category", total: 0, color: .gray)
        editedBudget.append(newCategory)
    }
    
    private func deleteCategory(at offsets: IndexSet) {
        // Before deleting, check if any category being removed has data.
        for index in offsets {
            let cat = editedBudget[index]
            if hasDataForCategory(categoryID: cat.id) {
                errorMessage = "Cannot remove category \"\(cat.name)\" because it has transactions or allocations for this month."
                return
            }
        }
        editedBudget.remove(atOffsets: offsets)
    }
    
    private func saveChanges() {
        let key = monthKey(for: selectedMonth)
        // Compare original budget (if any) with the edited one.
        let originalBudget = monthlyBudgets[key] ?? []
        let originalIDs = Set(originalBudget.map { $0.id })
        let editedIDs = Set(editedBudget.map { $0.id })
        let removedIDs = originalIDs.subtracting(editedIDs)
        // If any removed category has data, do not allow saving.
        for removedID in removedIDs {
            if hasDataForCategory(categoryID: removedID) {
                errorMessage = "Cannot remove a category that has transactions or allocations for this month."
                return
            }
        }
        monthlyBudgets[key] = editedBudget
        dismiss()
    }
    
    private func hasDataForCategory(categoryID: UUID) -> Bool {
        let txForCat = transactionsForMonth(transactions, selectedMonth: selectedMonth).filter { $0.categoryID == categoryID }
        let allocForCat = allocations.filter { sameMonth($0.month, selectedMonth) && $0.categoryID == categoryID }
        return !txForCat.isEmpty || !allocForCat.isEmpty
    }
}


// MARK: - Record Transaction
struct RecordTransactionView: View {
    let monthCategories: [CategoryBudget]    // The categories for this month
    @Binding var transactions: [Transaction] // Binding so you can append transactions
    let selectedMonth: Date
    let refreshRollover: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryIndex: Int = 0
    @State private var amountString: String = ""
    @State private var titleString: String = ""
    @State private var date = Date()
    @State private var errorMessage = ""
    
    // NEW: Computed property that returns the date range for the selected month.
    var selectedMonthRange: ClosedRange<Date> {
        let calendar = Calendar.current
        // Get the first day of the selected month.
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        // Get the range of days in the month.
        let range = calendar.range(of: .day, in: .month, for: selectedMonth)!
        // The last day is start plus (count - 1) days.
        let endOfMonth = calendar.date(byAdding: .day, value: range.count - 1, to: startOfMonth)!
        return startOfMonth...endOfMonth
    }
    
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
                    // Use the computed date range to restrict selection.
                    DatePicker("Date", selection: $date, in: selectedMonthRange, displayedComponents: .date)

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
            .onAppear {
                // If the selected month is the current month, default to today.
                // Otherwise, default to the first day of the selected month.
                if sameMonth(selectedMonth, Date()) {
                    date = Date()
                } else {
                    let calendar = Calendar.current
                    if let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) {
                        date = firstDay
                    }
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

        let chosenCategory = monthCategories[selectedCategoryIndex]
        let newTx = Transaction(
            categoryID: chosenCategory.id,
            date: date,
            amount: amt,
            description: titleString
        )
        transactions.append(newTx)
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
    @Environment(\.colorScheme) var colorScheme  // Moved here

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
        .background(Color.cardBackground(for: colorScheme))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}


struct RolloverBalanceCard: View {
    @Environment(\.colorScheme) var colorScheme
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
//        .background(Color(.systemBackground))
//        .background(Color(UIColor.secondarySystemBackground))
        .background(Color.cardBackground(for: colorScheme))

        .cornerRadius(10)
        // .shadow(radius: 4)
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
//        // .shadow(radius: 4)
//        .padding(.horizontal)
//    }
//}
struct CategoriesCard: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var monthlyBudgets: [String: [CategoryBudget]]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation] // <-- Add this line so we can see allocations
    @Binding var categories: [CategoryBudget]
    @State private var showNewBudgetSheet = false

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
//            .background(Color(.systemBackground))
//            .background(Color(UIColor.secondarySystemBackground))
            .background(Color.cardBackground(for: colorScheme))

            .cornerRadius(10)
            // .shadow(radius: 4)
            .padding(.horizontal)
            
        } else {
            // Show the "blank" state with two icons
            VStack(spacing: 20) {
                Text("No Budget for \(monthYearFormatter.string(from: selectedMonth))")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 50) {
                    // Copy Previous Button remains unchanged.
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
                    
                    // New Budget Button now presents the sheet.
                    Button {
                        showNewBudgetSheet = true
                    } label: {
                        VStack {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 36))
                            Text("New Budget")
                                .font(.subheadline)
                        }
                    }
                    .sheet(isPresented: $showNewBudgetSheet) {
                        NewBudgetView(monthlyBudgets: $monthlyBudgets, globalCategories: $categories, selectedMonth: selectedMonth)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
//            .background(Color(.systemBackground))
//            .background(Color(UIColor.secondarySystemBackground))
            .background(Color.cardBackground(for: colorScheme))

            .cornerRadius(10)
            // .shadow(radius: 4)
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
//            let newSet = prevCategories.map { oldCat in
//                CategoryBudget(
//                    id: UUID(),
//                    name: oldCat.name,
//                    total: oldCat.total,
//                    color: oldCat.color
//                )
//            }
            // After: reusing the same IDs
            let newSet = prevCategories.map { oldCat in
                CategoryBudget(
                    id: oldCat.id,
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
    @Environment(\.colorScheme) var colorScheme
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
//        .background(Color(.systemBackground))
//        .background(Color(UIColor.secondarySystemBackground))
        .background(Color.cardBackground(for: colorScheme))

        .cornerRadius(10)
        // .shadow(radius: 4)
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
        // .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2) // Added shadow for consistency
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    
    @State private var rolloverSpentByMonth: [String: Double] = [:]
    
    @State private var categories: [CategoryBudget] = [
        CategoryBudget(name: "Housing", total: 2400, color: .yellow),
        CategoryBudget(name: "Transportation", total: 700, color: .green),
        CategoryBudget(name: "Groceries", total: 900, color: .orange),
        CategoryBudget(name: "Healthcare", total: 200, color: .red),
        CategoryBudget(name: "Entertainment", total: 700, color: .purple),
        CategoryBudget(name: "Misc", total: 500, color: .brown)
//        CategoryBudget(name: "🏠 Housing", total: 2400, color: .yellow),
//        CategoryBudget(name: "🚗 Transportation", total: 700, color: .green),
//        CategoryBudget(name: "🛒 Groceries", total: 900, color: .orange),
//        CategoryBudget(name: "🏥 Healthcare", total: 200, color: .red),
//        CategoryBudget(name: "🎉 Entertainment", total: 700, color: .purple),
//        CategoryBudget(name: "🏷️ Misc", total: 500, color: .brown)
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
        saveData(goals, filename: "savingsGoals.json")
        saveData(rolloverSpentByMonth, filename: "rolloverSpentByMonth.json")
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
                            allocations: $allocations,
                            categories: $categories,
                            selectedMonth: selectedMonth
                        )

                        CalendarCard(
                            transactions: transactions,
                            selectedMonth: selectedMonth,
                            categories: monthlyBudgets[monthKey(for: selectedMonth)] ?? categories
                        )

                    }
                    .padding(.top, 8) // Reduced top padding from default to 8 points
                }
                // just removed this REESE
//                VStack {
//                    Spacer()
//                    RecordTransactionButton(showRecordTransaction: $showRecordTransaction)
//                }
            }
            .background(Color.viewBackground(for: colorScheme))
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
                        NavigationLink(destination: TransactionsAndAllocationsView(
                            transactions: $transactions,
                            allocations: $allocations,
                            savingsRecords: $savingsRecords,
                            goals: $goals,
                            categories: $categories,
                            monthlyBudgets: $monthlyBudgets,
                            rolloverLeftover: $rolloverLeftover,                // NEW
                            rolloverSpentByMonth: $rolloverSpentByMonth,        // NEW
                            selectedMonth: selectedMonth
                        )) {
                            Image(systemName: "list.bullet")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }




                        // In ContentView toolbar (where you have NavigationLink to SettingsView):
                        NavigationLink(destination: SettingsView(
                            monthlyBudgets: $monthlyBudgets,
                            globalCategories: $categories,
                            transactions: $transactions,
                            allocations: $allocations,
                            selectedMonth: selectedMonth
                        )) {
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
            
            loadGoals()
            
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
            
            if let loadedRolloverSpent = loadData(filename: "rolloverSpentByMonth.json", as: [String: Double].self) {
                rolloverSpentByMonth = loadedRolloverSpent
            }

            
            rolloverLeftover = storedRollover

            // Ensure December 2024 has a default budget.
            let dec2024Key = "2024-12"
            if monthlyBudgets[dec2024Key] == nil {
                monthlyBudgets[dec2024Key] = categories
            }

            // Initialize January 2025 with December 2024's budget if it doesn't exist.
            let jan2025Key = "2025-01"
            if monthlyBudgets[jan2025Key] == nil {
                if let decBudget = monthlyBudgets[dec2024Key] {
                    let newBudget = decBudget.map { oldCat in
                        CategoryBudget(
                            id: oldCat.id,  // Assign a new unique ID
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
//                        CategoryBudget(name: "🏠 Housing", total: 2400, color: .yellow),
//                        CategoryBudget(name: "🚗 Transportation", total: 700, color: .green),
//                        CategoryBudget(name: "🛒 Groceries", total: 900, color: .orange),
//                        CategoryBudget(name: "🏥 Healthcare", total: 200, color: .red),
//                        CategoryBudget(name: "🎉 Entertainment", total: 700, color: .purple),
//                        CategoryBudget(name: "🏷️ Misc", total: 500, color: .brown)
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
                    selectedMonth: prev,
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
        
        // NEW: Also subtract any savings transfers made in the current month.
        let currentSavings = rolloverSpentByMonth[monthKey(for: selectedMonth)] ?? 0
        rolloverLeftover -= currentSavings
    }


//    @AppStorage("savingsGoals") private var goalsData: Data = Data()
//    @State private var goals: [SavingsGoal] = [] {
//        didSet {
//            saveGoals()
//        }
//    }
    @State private var goals: [SavingsGoal] = []

//    private func saveGoals() {
//        do {
//            let data = try JSONEncoder().encode(goals)
//            goalsData = data
//        } catch {
//            print("Error saving goals: \(error)")
//        }
//    }
//
//    private func loadGoals() {
//        guard !goalsData.isEmpty else { return }
//        do {
//            goals = try JSONDecoder().decode([SavingsGoal].self, from: goalsData)
//        } catch {
//            print("Error loading goals: \(error)")
//        }
//    }
    
    private func saveGoals() {
        saveData(goals, filename: "savingsGoals.json")
    }

    private func loadGoals() {
        if let loadedGoals = loadData(filename: "savingsGoals.json", as: [SavingsGoal].self) {
            goals = loadedGoals
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
        // Check for duplicate goal names (case-insensitive)
        if goals.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
            errorMessage = "A goal with that name already exists."
            return
        }
        
        guard !title.isEmpty else {
            errorMessage = "Please enter a title."
            return
        }
        
        guard let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Please enter a valid amount."
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


// MARK: - New Budget View

//struct NewBudgetView: View {
//    @Binding var monthlyBudgets: [String: [CategoryBudget]]
//    @Binding var globalCategories: [CategoryBudget]
//    let selectedMonth: Date
//    @Environment(\.dismiss) private var dismiss
//
//    // Local editable copy of the categories for this new budget
//    @State private var customBudgets: [CategoryBudget] = []
//
//    // A computed property to sum the allocations
//    var totalAllocation: Double {
//        customBudgets.reduce(0) { $0 + $1.total }
//    }
//
//    var body: some View {
//        NavigationStack {
//            List {
//                Section(header:
//                    Text("Budget for \(monthYearFormatter.string(from: selectedMonth))")
//                        .font(.headline)
//                ) {
//                    ForEach(customBudgets.indices, id: \.self) { index in
//                        VStack(alignment: .leading, spacing: 8) {
//                            TextField("Category Name", text: $customBudgets[index].name)
//                                .textFieldStyle(RoundedBorderTextFieldStyle())
//                            HStack {
//                                Text("Allocation:")
//                                Spacer()
//                                TextField("Amount", value: $customBudgets[index].total, format: .number)
//                                    .keyboardType(.decimalPad)
//                                    .multilineTextAlignment(.trailing)
//                                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                            }
//                        }
//                        .padding(.vertical, 4)
//                    }
//                    .onDelete(perform: deleteCategory)
//                }
//
//                Section(header:
//                    Text("Total Allocation: \(formatAmount(totalAllocation))")
//                        .font(.subheadline)
//                        .foregroundColor(.secondary)
//                ) {
//                    EmptyView()
//                }
//            }
//            .listStyle(InsetGroupedListStyle())
//            .navigationTitle("New Budget")
//            .toolbar {
//                ToolbarItem(placement: .navigationBarLeading) {
//                    Button("Cancel") { dismiss() }
//                }
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button("Save") {
//                        monthlyBudgets[monthKey(for: selectedMonth)] = customBudgets
//                        dismiss()
//                    }
//                    .disabled(customBudgets.isEmpty)
//                }
//                ToolbarItem(placement: .bottomBar) {
//                    Button(action: addCategory) {
//                        Label("Add Category", systemImage: "plus")
//                    }
//                    .buttonStyle(BorderedProminentButtonStyle())
//                }
//            }
//            .onAppear {
//                // Initialize with a copy of the global categories
//                customBudgets = globalCategories.map { cat in
//                    CategoryBudget(id: cat.id, name: cat.name, total: cat.total, color: cat.color)
//                }
//            }
//        }
//    }
//
//    private func addCategory() {
//        let newCategory = CategoryBudget(name: "New Category", total: 0, color: .gray)
//        customBudgets.append(newCategory)
//    }
//
//    private func deleteCategory(at offsets: IndexSet) {
//        customBudgets.remove(atOffsets: offsets)
//    }
//}



struct NewBudgetView: View {
    @Binding var monthlyBudgets: [String: [CategoryBudget]]
    @Binding var globalCategories: [CategoryBudget]
    let selectedMonth: Date
    @Environment(\.dismiss) private var dismiss

    // Use a local state copy so the user can edit without immediately affecting stored data.
    @State private var customBudgets: [CategoryBudget] = []

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Edit Budget Categories")) {
                    ForEach(customBudgets.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            TextField("Category Name", text: $customBudgets[index].name)
                            HStack {
                                Text("Allocation:")
                                TextField("Amount", value: $customBudgets[index].total, format: .number)
                                    .keyboardType(.decimalPad)
                            }
                        }
                    }
                    .onDelete(perform: deleteCategory)
                }
                
                Section {
                    Button("Add Category") {
                        addCategory()
                    }
                }
            }
            .navigationTitle("New Budget for \(monthYearFormatter.string(from: selectedMonth))")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        monthlyBudgets[monthKey(for: selectedMonth)] = customBudgets
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Initialize with a copy of the global categories.
                customBudgets = globalCategories.map { cat in
                    // Make a copy so that changes here don't affect globalCategories.
                    CategoryBudget(id: cat.id, name: cat.name, total: cat.total, color: cat.color)
                }
            }
        }
    }
    
    private func addCategory() {
        // Append a new category with default name and zero allocation.
        let newCategory = CategoryBudget(name: "New Category", total: 0, color: .gray)
        customBudgets.append(newCategory)
    }
    
    private func deleteCategory(at offsets: IndexSet) {
        customBudgets.remove(atOffsets: offsets)
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
//                            Text(tx.date, style: .time)
//                                .font(.subheadline)
//                                .foregroundColor(.secondary)
                            Text(categoryName(for: tx.categoryID))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(formatPreciseAmount(tx.amount))
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
    
    let refreshRollover: () -> Void
    
    @State private var showTransfer = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Current Rollover Balance") {
                    // Use precise formatting here
                    Text(formatPreciseAmount(rolloverLeftover))
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
                    Text("Rollover Balance: \(formatPreciseAmount(rolloverLeftover))")
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
            let selectedGoal = goals[selectedGoalIndex]
            // Check if the goal is already reached
            if selectedGoal.currentAmount >= selectedGoal.targetAmount {
                errorMessage = "This goal has already reached its target."
                return
            }
            // Check if the transfer would exceed the goal's target
            if selectedGoal.currentAmount + amount > selectedGoal.targetAmount {
                errorMessage = "Transfer amount exceeds the goal's target."
                return
            }
            // Proceed with the transfer if validations pass
            goals[selectedGoalIndex].currentAmount += amount
            // Add a savings record for this transfer.
            let newRecord = SavingsRecord(goalID: selectedGoal.id, date: Date(), amount: amount, description: "Transfer from rollover")
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
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation]
    @Binding var savingsRecords: [SavingsRecord]
    @Binding var goals: [SavingsGoal]
    @Binding var categories: [CategoryBudget]
    @Binding var monthlyBudgets: [String: [CategoryBudget]]
    
    // NEW bindings:
    @Binding var rolloverLeftover: Double
    @Binding var rolloverSpentByMonth: [String: Double]
    
    let selectedMonth: Date
    
    @State private var selectedSegment = 0
    // NEW: This holds the index in the original transactions array for the transaction being edited.
    @State private var editingTransactionIndex: Int? = nil
    
    var sortedTransactions: [Transaction] {
        transactions.sorted { $0.date < $1.date }
    }
    
    var sortedAllocations: [CategoryAllocation] {
        allocations.sorted { $0.month < $1.month }
    }
    
    var sortedSavings: [SavingsRecord] {
        savingsRecords.sorted { $0.date < $1.date }
    }
    
    // Helper to get a category name from its id.
    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unknown Category"
    }
    
    // Helper to format a Date as a medium‑style string.
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func deleteTransaction(at offsets: IndexSet) {
        for index in offsets {
            let txToDelete = sortedTransactions[index]
            if let originalIndex = transactions.firstIndex(where: { $0.id == txToDelete.id }) {
                transactions.remove(at: originalIndex)
            }
        }
    }
    
    private func deleteAllocation(at offsets: IndexSet) {
        for index in offsets {
            let allocToDelete = sortedAllocations[index]
            if let originalIndex = allocations.firstIndex(where: { $0.id == allocToDelete.id }) {
                allocations.remove(at: originalIndex)
            }
        }
    }
    
    private func deleteSavingsRecord(at offsets: IndexSet) {
        for index in offsets {
            let recordToDelete = sortedSavings[index]
            if let originalIndex = savingsRecords.firstIndex(where: { $0.id == recordToDelete.id }) {
                savingsRecords.remove(at: originalIndex)
            }
            if let goalIndex = goals.firstIndex(where: { $0.id == recordToDelete.goalID }) {
                goals[goalIndex].currentAmount -= recordToDelete.amount
                if goals[goalIndex].currentAmount < 0 {
                    goals[goalIndex].currentAmount = 0
                }
            }
            // Use the record’s date (or you could use selectedMonth if that’s always correct)
            let key = monthKey(for: recordToDelete.date)
            rolloverSpentByMonth[key, default: 0] -= recordToDelete.amount
            rolloverLeftover += recordToDelete.amount
        }
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
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tx.description)
                                        .font(.headline)
                                    Text("\(formatDate(tx.date))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatPreciseAmount(tx.amount))
                                    .foregroundColor(.red)
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                                        transactions.remove(at: index)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    // Set editingTransactionIndex to the index of tx in the original transactions array.
                                    if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                                        editingTransactionIndex = index
                                    }
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        // We no longer add .onDelete here because swipe actions handle deletion.
                    }
                } else if selectedSegment == 1 {
                    Section(header: Text("Allocations").font(.headline)) {
                        ForEach(sortedAllocations) { alloc in
                            let allocKey = monthKey(for: alloc.month)
                            let catName = (monthlyBudgets[allocKey]?.first(where: { $0.id == alloc.categoryID })?.name)
                                ?? (categories.first(where: { $0.id == alloc.categoryID })?.name)
                                ?? "Unknown Category"
                            let monthString = monthYearFormatter.string(from: alloc.month)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(monthString)")
                                        .font(.headline)
                                    Text("\(catName)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatPreciseAmount(alloc.allocatedAmount))
                                    .foregroundColor(.red)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteAllocation)
                    }
                } else if selectedSegment == 2 {
                    Section(header: Text("Savings").font(.headline)) {
                        ForEach(sortedSavings) { record in
                            let goalName = goals.first(where: { $0.id == record.goalID })?.title ?? "Unknown Savings Goal"
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Savings Goal: \(goalName)")
                                        .font(.headline)
                                    Text(formatDate(record.date))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatPreciseAmount(record.amount))
                                    .foregroundColor(.red)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteSavingsRecord)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
        .navigationTitle("All Data")
            .sheet(isPresented: Binding(get: { editingTransactionIndex != nil },
                                        set: { if !$0 { editingTransactionIndex = nil } })) {
                if let index = editingTransactionIndex {
                    EditTransactionView(
                        transaction: $transactions[index],
                        monthBudgets: monthlyBudgets,
                        globalCategories: categories
                    )
                }
            }

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
