//
//  ContentView.swift
//  tally
//
//  Created by Reese Thompson on 1/22/25.
//

import SwiftUI

// MARK: - Data Models

struct Transaction: Identifiable {
    let id = UUID()
    var categoryID: UUID
    var date: Date
    var amount: Double
    var description: String
}

struct CategoryBudget: Identifiable {
    let id: UUID
    var name: String
    var total: Double
    var color: Color
    
    init(
        id: UUID = UUID(),
        name: String,
        total: Double,
        color: Color
    ) {
        self.id = id
        self.name = name
        self.total = total
        self.color = color
    }
}

// MARK: - Global Helpers

/// Check if two dates share the same month & year.
func sameMonth(_ d1: Date, _ d2: Date) -> Bool {
    let cal = Calendar.current
    let c1 = cal.dateComponents([.year, .month], from: d1)
    let c2 = cal.dateComponents([.year, .month], from: d2)
    return c1.year == c2.year && c1.month == c2.month
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

/// leftover = (sum of all categories' totals) - (sum of amounts in month)
func leftoverForMonth(allCategories: [CategoryBudget], monthTransactions: [Transaction]) -> Double {
    let totalBudget = allCategories.reduce(0) { $0 + $1.total }
    let spent = monthTransactions.map { $0.amount }.reduce(0, +)
    return totalBudget - spent
}

/// A user-friendly Month+Year (e.g. "January 2025").
fileprivate let monthYearFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "LLLL yyyy"
    return df
}()

// MARK: - Row Views

/// Displays a bar comparing "spent" vs. "category.total."
struct CategoryRow: View {
    let category: CategoryBudget
    let spentThisMonth: Double
    
    private var fractionUsed: Double {
        guard category.total > 0 else { return 0 }
        let rawFrac = spentThisMonth / category.total
        return min(max(rawFrac, 0), 1)
    }
    private var fractionRemaining: Double {
        1 - fractionUsed
    }
    private var remainingDisplay: Double {
        category.total - spentThisMonth
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
                    
                    Text("\(Int(remainingDisplay)) / \(Int(category.total))")
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
    let categories: [CategoryBudget]
    let monthlySpentByCategory: [UUID: Double]
    
    private var totalBudget: Double {
        categories.reduce(0) { $0 + $1.total }
    }
    private var totalSpent: Double {
        monthlySpentByCategory.values.reduce(0, +)
    }
    private var fractionRemaining: Double {
        guard totalBudget > 0 else { return 1 }
        let usedFrac = totalSpent / totalBudget
        return max(0, 1 - usedFrac)
    }
    private var remaining: Double {
        totalBudget - totalSpent
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
                    
                    Text("\(Int(remaining)) / \(Int(totalBudget))")
                        .foregroundColor(.white)
                        .padding(.trailing, 8)
                }
            }
        }
        .frame(height: 30)
    }
}

// MARK: - Calendar

struct MonthlyCalendarView: View {
    let month: Date
    let transactions: [Transaction]
    
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
        transactions.filter { calendar.isDate($0.date, inSameDayAs: date) }
                    .map { $0.amount }
                    .reduce(0, +)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"], id: \.self) { wd in
                    Text(wd)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                ForEach(daysArray.indices, id: \.self) { i in
                    if let day = daysArray[i] {
                        let dNum = calendar.component(.day, from: day)
                        let spent = spendingOnDay(day)
                        VStack(spacing: 4) {
                            Text("\(dNum)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if spent > 0 {
                                Text(spent, format: .currency(code: "USD"))
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            } else {
                                Text("$0")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                    } else {
                        // placeholder
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
                            Text(tx.amount, format: .currency(code: "USD"))
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
        .navigationTitle("\(monthYearFormatter.string(from: selectedMonth)) Budget")
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
                Text(t.amount, format: .currency(code: "USD"))
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
    @Binding var categories: [CategoryBudget]
    @Binding var transactions: [Transaction]
    let refreshRollover: () -> Void // Add this line

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
                        ForEach(categories.indices, id: \.self) { i in
                            Text(categories[i].name).tag(i)
                        }
                    }
                }
                Section("Details") {
                    TextField("Transaction Title", text: $titleString)
                    TextField("Amount", text: $amountString).keyboardType(.decimalPad)
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
        
        let catID = categories[selectedCategoryIndex].id
        let newTx = Transaction(categoryID: catID, date: date, amount: amt, description: titleString)
        transactions.append(newTx)
        
        // Refresh rollover balance
        refreshRollover() // Call the passed-in closure

        dismiss()
    }
}


// MARK: - Month Picker

struct MonthPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMonth: Date
    
    private let years = Array(2020...2030)
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

// MARK: - Main ContentView

struct ContentView: View {
    
    // Categories & transactions
    @State private var categories: [CategoryBudget] = [
        CategoryBudget(name: "Housing",        total: 2400, color: .yellow),
        CategoryBudget(name: "Transportation", total:  700, color: .green),
        CategoryBudget(name: "Groceries",      total:  900, color: .orange),
        CategoryBudget(name: "Healthcare",     total:  200, color: .red),
        CategoryBudget(name: "Entertainment",  total:  700, color: .purple),
        CategoryBudget(name: "Misc",           total:  500, color: .brown)
    ]
    @State private var transactions: [Transaction] = []
    
    // Various sheets
    @State private var showSettings = false
    @State private var showRecordTransaction = false
    @State private var showMonthPicker = false
    
    // The currently chosen month, defaults to "today"
    @State private var selectedMonth = Date()
    
    // The leftover from prior months
    @State private var rolloverLeftover: Double = 0
    
    // The overall budget is the sum of all categories
    private var overallBudget: Double {
        categories.reduce(0) { $0 + $1.total }
    }
    
    private func updateRolloverLeftover() {
        // Reset rollover to zero initially
        rolloverLeftover = 0

        // Define the starting point for the rollover balance (January 2024)
        let startingPointDate = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!

        // Check if the selected month is before the starting point
        guard selectedMonth >= startingPointDate else {
            return // No rollover before the starting point
        }

        // If the selected month is January 2024, start with zero rollover
        if selectedMonth == startingPointDate {
            rolloverLeftover = 0
            return
        }

        // Iterate backward from the selected month to calculate rollover
        var currentMonth = selectedMonth
        rolloverLeftover = 0 // Start at zero

        while currentMonth > startingPointDate {
            guard let prevMonthDate = previousMonth(of: currentMonth) else { break }
            currentMonth = prevMonthDate

            // Get transactions for the previous month
            let prevTx = transactionsForMonth(transactions, selectedMonth: prevMonthDate)

            // Calculate leftover budget for the previous month
            let leftoverFromPrev = leftoverForMonth(allCategories: categories, monthTransactions: prevTx)

            // Add the leftover from the previous month to the rollover
            rolloverLeftover += leftoverFromPrev
        }

    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // Month Selector Card
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
                        
                        // Rollover Balance Card
                        VStack {
                            NavigationLink {
                                RolloverDetailView(
                                    rolloverLeftover: $rolloverLeftover,
                                    categories: $categories,
                                    overallBudget: overallBudget
                                )
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
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 4)
                        .padding(.horizontal)
                        
//                        // Overall Budget Card
//                        VStack {
//                            NavigationLink {
//                                AllTransactionsView(
//                                    transactions: $transactions,
//                                    categories: $categories,
//                                    selectedMonth: selectedMonth
//                                )
//                            } label: {
//                                OverallBudgetRow(
//                                    categories: categories,
//                                    monthlySpentByCategory: monthlySpentByCategory(
//                                        categories: categories,
//                                        transactions: transactionsForMonth(transactions, selectedMonth: selectedMonth)
//                                    )
//                                )
//                                .frame(height: 40)
//                                .padding()
//                            }
//                        }
//                        .background(Color(.systemBackground))
//                        .cornerRadius(10)
//                        .shadow(radius: 4)
//                        .padding(.horizontal)
                        
                        // Categories Card (including Overall Budget and Rollover Balance)
                        VStack(spacing: 8) {
                            // Overall Budget Row
                            NavigationLink {
                                AllTransactionsView(
                                    transactions: $transactions,
                                    categories: $categories,
                                    selectedMonth: selectedMonth
                                )
                            } label: {
                                HStack {
                                    OverallBudgetRow(
                                        categories: categories,
                                        monthlySpentByCategory: monthlySpentByCategory(
                                            categories: categories,
                                            transactions: transactionsForMonth(transactions, selectedMonth: selectedMonth)
                                        )
                                    )
//                                    .frame(height: 40)
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
//                                .padding(.vertical) // Consistent padding
                            }
                            
//                            // Rollover Balance Row (Bar)
//                            NavigationLink {
//                                RolloverDetailView(
//                                    rolloverLeftover: $rolloverLeftover,
//                                    categories: $categories,
//                                    overallBudget: overallBudget
//                                )
//                            } label: {
//                                HStack {
//                                    let spent = max(0, overallBudget - rolloverLeftover)
//                                    let rolloverCategory = CategoryBudget(
//                                        name: "Rollover Balance",
//                                        total: overallBudget,
//                                        color: .green
//                                    )
//                                    CategoryRow(category: rolloverCategory, spentThisMonth: spent)
////                                        .frame(height: 40)
//
//                                    Image(systemName: "chevron.right")
//                                        .foregroundColor(.secondary)
//                                }
//                                .padding(.horizontal)
////                                .padding(.vertical, 4) // Consistent padding
//                            }
                            
                            // Individual Categories Rows
                            let spentDict = monthlySpentByCategory(categories: categories, transactions: transactionsForMonth(transactions, selectedMonth: selectedMonth))
                            ForEach(categories) { cat in
                                NavigationLink {
                                    TransactionLogView(
                                        category: cat,
                                        transactions: transactions,
                                        selectedMonth: selectedMonth
                                    )
                                } label: {
                                    HStack {
                                        CategoryRow(category: cat, spentThisMonth: spentDict[cat.id] ?? 0)
//                                            .frame(height: 40) // Fixed height
                                        
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal)
//                                    .padding(.vertical, 4) // space between bars
                                }
                            }
                        }
                        .padding(.vertical)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 4)
                        .padding(.horizontal)


                        
                        // Calendar Card
                        VStack(spacing: 16) { // Added spacing above the calendar
                            MonthlyCalendarView(
                                month: selectedMonth,
                                transactions: transactionsForMonth(transactions, selectedMonth: selectedMonth)
                            )
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 4)
                        .padding(.horizontal)
                    }
                    .padding(.top)
                }


                .listStyle(.plain)
                
                // Big pinned "Record Transaction" button
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        Button("Record Transaction") {
                            showRecordTransaction = true
                        }
                        .font(.title3)
                        .frame(width: geo.size.width - 32, height: 40)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 40)
                    .padding(.bottom, 16)
                }
            }
            // Large month text on the left
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: GoalsView()) {
                        Text("Goals")
                            .font(.headline)
                            .bold()
                    }
                }

            }
            .navigationBarTitleDisplayMode(.large)
        }
        // Recompute rollover whenever the month changes
        .onChange(of: selectedMonth) { _ in
            rolloverLeftover = 0 // reset, then recalc
            updateRolloverLeftover()
        }
        .onAppear {
            rolloverLeftover = 0
            updateRolloverLeftover()
        }
        // Settings
        .sheet(isPresented: $showSettings) {
            SettingsView(categories: $categories)
        }
        // Record Transaction
        .sheet(isPresented: $showRecordTransaction) {
            RecordTransactionView(categories: $categories, transactions: $transactions, refreshRollover: updateRolloverLeftover)
        }

        // Month Picker
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerView(selectedMonth: $selectedMonth)
        }
    }
}

// MARK: - Goals View

struct GoalsView: View {
    @State private var goals: [SavingsGoal] = []
    @State private var showAddGoalMenu = false

    var body: some View {
        NavigationStack {
            VStack {
                // Display list of goals
                if goals.isEmpty {
                    Spacer()
                    Button(action: {
                        showAddGoalMenu = true
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(goals) { goal in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(goal.title)
                                        .font(.headline)
                                    Text("$\(goal.amount, specifier: "%.2f")")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            Button(action: {
                                showAddGoalMenu = true
                            }) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 50))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                    }
                }
            }
            .sheet(isPresented: $showAddGoalMenu) {
                AddGoalView(goals: $goals)
            }
            .navigationTitle("Goals")
        }
    }
}

struct AddGoalView: View {
    @Binding var goals: [SavingsGoal]
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Title", text: $title)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Goal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        addGoal()
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

    private func addGoal() {
        guard let amountValue = Double(amount), !title.isEmpty else { return }
        let newGoal = SavingsGoal(title: title, amount: amountValue)
        goals.append(newGoal)
        dismiss()
    }
}


// Data model for savings goals
struct SavingsGoal: Identifiable {
    let id = UUID()
    let title: String
    let amount: Double
}


// MARK: - Rollover Detail Screen

/// Shows the current rollover leftover plus a short explanation of how it’s calculated.
/// Also has a button to transfer funds from/to the rollover.
struct RolloverDetailView: View {
    @Binding var rolloverLeftover: Double
    @Binding var categories: [CategoryBudget]
    let overallBudget: Double
    
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
                    Button("Reallocate Funds") {
                        showTransfer = true
                    }
                }
            }
            .navigationTitle("Rollover Balance")
            .sheet(isPresented: $showTransfer) {
                // The same unified transfer screen
                TransferFundsView(
                    rolloverLeftover: $rolloverLeftover,
                    categories: $categories
                )
            }
        }
    }
}

// MARK: - TransferFundsView

/// A single screen to transfer from Rollover or a category to Rollover or another category.
struct TransferFundsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var rolloverLeftover: Double
    @Binding var categories: [CategoryBudget]
    
    // default from=0 => Rollover, to=1 => first category
    @State private var fromIndex: Int = 0
    @State private var toIndex: Int = 1
    @State private var amountString: String = ""
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    Picker("From Source", selection: $fromIndex) {
                        Text("Rollover").tag(0)
                        ForEach(categories.indices, id: \.self) { i in
                            Text(categories[i].name).tag(i+1)
                        }
                    }
                }
                Section("To") {
                    Picker("Destination", selection: $toIndex) {
                        Text("Rollover").tag(0)
                        ForEach(categories.indices, id: \.self) { i in
                            Text(categories[i].name).tag(i+1)
                        }
                    }
                }
                Section("Amount") {
                    TextField("Amount to Transfer", text: $amountString)
                        .keyboardType(.decimalPad)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("Transfer Funds")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") {
                        performTransfer()
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
    
    private func performTransfer() {
        guard let amt = Double(amountString), amt > 0 else {
            errorMessage = "Please enter a positive amount."
            return
        }
        if fromIndex == toIndex {
            errorMessage = "Cannot transfer to the same source."
            return
        }
        
        // Deduct from "from"
        if fromIndex == 0 {
            // from rollover
            if amt > rolloverLeftover {
                errorMessage = "Insufficient rollover leftover."
                return
            }
            rolloverLeftover -= amt
        } else {
            let realFrom = fromIndex - 1
            if amt > categories[realFrom].total {
                errorMessage = "Not enough funds in \(categories[realFrom].name)."
                return
            }
            categories[realFrom].total -= amt
        }
        
        // Add to "to"
        if toIndex == 0 {
            rolloverLeftover += amt
        } else {
            let realTo = toIndex - 1
            categories[realTo].total += amt
        }
        
        dismiss()
    }
}

#Preview {
    ContentView()
}




