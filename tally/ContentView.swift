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
/// leftover = (sum of allocated amounts for all categories in the month) - (sum of amounts in month)
/// leftover = (sum of allocated amounts for all categories in the month) - (sum of amounts in month)
func leftoverForMonth(
    allCategories: [CategoryBudget],
    allocations: [CategoryAllocation],
    selectedMonth: Date,
    monthTransactions: [Transaction]
) -> Double {
    // Filter allocations for the selected month
    let allocatedCategories = allocations.filter { sameMonth($0.month, selectedMonth) }
    
    // Create a dictionary mapping categoryID to allocatedAmount
    let allocatedAmountsByCategory = Dictionary(uniqueKeysWithValues: allocatedCategories.map { ($0.categoryID, $0.allocatedAmount) })
    
    // Calculate totalAllocated by using allocations if available, otherwise use category.total
    let totalAllocated = allCategories.reduce(0) { $0 + (allocatedAmountsByCategory[$1.id] ?? $1.total) }
    
    // Calculate total spent
    let spent = monthTransactions.map { $0.amount }.reduce(0, +)
    
    return totalAllocated - spent
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
                    
                    Text("\(Int(remainingDisplay)) / \(Int(allocatedAmount))")
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
                    
                    Text("\(Int(remaining)) / \(Int(totalAllocated))")
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

// MARK: - Component Cards

struct MonthSelectorCard: View {
    @Binding var selectedMonth: Date
    
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
    @Binding var rolloverLeftover: Double
    @Binding var categories: [CategoryBudget]
    @Binding var goals: [SavingsGoal]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation]
    let overallBudget: Double
    let selectedMonth: Date
    
    var body: some View {
        NavigationLink {
            RolloverDetailView(
                rolloverLeftover: $rolloverLeftover,
                categories: $categories,
                goals: $goals,
                transactions: $transactions,
                allocations: $allocations,
                overallBudget: overallBudget,
                selectedMonth: selectedMonth
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
    @Binding var categories: [CategoryBudget]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation] // Added this line
    let selectedMonth: Date
    
    private var monthlyTransactions: [Transaction] {
        transactionsForMonth(transactions, selectedMonth: selectedMonth)
    }
    
    private var spentByCategory: [UUID: Double] {
        monthlySpentByCategory(categories: categories, transactions: monthlyTransactions)
    }
    
    private var allocatedByCategory: [UUID: Double] {
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedMonth))!
        var result = [UUID: Double]()
        
        for cat in categories {
            if let allocation = allocations.first(where: { $0.categoryID == cat.id && sameMonth($0.month, selectedMonth) }) {
                result[cat.id] = allocation.allocatedAmount
            } else {
                result[cat.id] = cat.total
            }
        }
        
        return result
    }

    private var totalAllocated: Double {
        allocatedByCategory.values.reduce(0, +)
    }
    
    private var totalSpent: Double {
        spentByCategory.values.reduce(0, +)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            NavigationLink {
                AllTransactionsView(
                    transactions: $transactions,
                    categories: $categories,
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
            
            ForEach(categories) { cat in
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
                            allocatedAmount: allocatedByCategory[cat.id] ?? cat.total // Pass allocated amount
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
    }
}

struct CalendarCard: View {
    let transactions: [Transaction]
    let selectedMonth: Date
    
    var body: some View {
        VStack(spacing: 16) {
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
}

struct RecordTransactionButton: View {
    @Binding var showRecordTransaction: Bool
    
    var body: some View {
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

// MARK: - ContentView

struct ContentView: View {
    
    @State private var categories: [CategoryBudget] = [
        CategoryBudget(name: "Housing", total: 2400, color: .yellow),
        CategoryBudget(name: "Transportation", total: 700, color: .green),
        CategoryBudget(name: "Groceries", total: 900, color: .orange),
        CategoryBudget(name: "Healthcare", total: 200, color: .red),
        CategoryBudget(name: "Entertainment", total: 700, color: .purple),
        CategoryBudget(name: "Misc", total: 500, color: .brown)
    ] {
        didSet {
            saveData(categories, to: "categories.json")
        }
    }
    
    @State private var allocations: [CategoryAllocation] = [] {
        didSet {
            saveData(allocations, to: "allocations.json")
        }
    }
    
    @State private var transactions: [Transaction] = [] {
        didSet {
            saveData(transactions, to: "transactions.json")
        }
    }
    @State private var selectedMonth = Date()
    @State private var rolloverLeftover: Double = 0
    @State private var showSettings = false
    @State private var showRecordTransaction = false
    @State private var showMonthPicker = false
    
    private var overallBudget: Double {
        // Filter allocations for the selected month
        let allocatedCategories = allocations.filter { sameMonth($0.month, selectedMonth) }
        
        // Create a dictionary mapping categoryID to allocatedAmount
        let allocatedAmountsByCategory = Dictionary(uniqueKeysWithValues: allocatedCategories.map { ($0.categoryID, $0.allocatedAmount) })
        
        // Calculate totalAllocated by using allocations if available, otherwise use category.total
        return categories.reduce(0) { $0 + (allocatedAmountsByCategory[$1.id] ?? $1.total) }
    }

    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        MonthSelectorCard(selectedMonth: $selectedMonth)
                        RolloverBalanceCard(
                            rolloverLeftover: $rolloverLeftover,
                            categories: $categories,
                            goals: $goals,
                            transactions: $transactions,
                            allocations: $allocations, // Added this line
                            overallBudget: overallBudget,
                            selectedMonth: selectedMonth
                        )
                        CategoriesCard(
                            categories: $categories,
                            transactions: $transactions,
                            allocations: $allocations, // Added this line
                            selectedMonth: selectedMonth
                        )
                        CalendarCard(
                            transactions: transactions,
                            selectedMonth: selectedMonth
                        )
                    }

//                    .padding(.top, 8) // Reduced top padding from default to 8 points
                }

                
                VStack {
                    Spacer()
                    RecordTransactionButton(showRecordTransaction: $showRecordTransaction)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) { // Use a ToolbarItem for NavigationLink
                    NavigationLink(destination: GoalsView(goals: $goals)) {
                        Text("Goals").font(.headline).bold()
                    }
                }
            }

            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: selectedMonth) { _ in updateRolloverLeftover() }
        .onAppear {
            if let savedTransactions: [Transaction] = loadData([Transaction].self, from: "transactions.json") {
                transactions = savedTransactions
            } else {
                transactions = [] // Provide default transactions or keep it empty
            }
            
            if let savedCategories: [CategoryBudget] = loadData([CategoryBudget].self, from: "categories.json") {
                categories = savedCategories
            } else {
                categories = [
                    CategoryBudget(name: "Housing", total: 2400, color: .yellow),
                    CategoryBudget(name: "Transportation", total: 700, color: .green),
                    CategoryBudget(name: "Groceries", total: 900, color: .orange),
                    CategoryBudget(name: "Healthcare", total: 200, color: .red),
                    CategoryBudget(name: "Entertainment", total: 700, color: .purple),
                    CategoryBudget(name: "Misc", total: 500, color: .brown)
                ]
            }
            
            if let savedAllocations: [CategoryAllocation] = loadData([CategoryAllocation].self, from: "allocations.json") {
                allocations = savedAllocations
            } else {
                allocations = [] // Initialize as empty or set default allocations if desired
            }
            
            loadGoals()
            updateRolloverLeftover()
        }



        .sheet(isPresented: $showSettings) {
            SettingsView(categories: $categories)
        }
        .sheet(isPresented: $showRecordTransaction) {
            RecordTransactionView(
                categories: $categories,
                transactions: $transactions,
                refreshRollover: updateRolloverLeftover
            )
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerView(selectedMonth: $selectedMonth)
        }
    }
    
    private func updateRolloverLeftover() {
        // Define the starting point for the rollover balance (January 2024)
        let startingPointDate = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        
        // Reset rollover to zero initially
        rolloverLeftover = 0
        
        // Check if the selected month is before the starting point
        guard selectedMonth >= startingPointDate else {
            return // No rollover before the starting point
        }
        
        // If the selected month is January 2024, start with zero rollover
        if Calendar.current.isDate(selectedMonth, equalTo: startingPointDate, toGranularity: .month) {
            rolloverLeftover = 0
            return
        }
        
        // Iterate backward from the selected month to calculate rollover
        var currentMonth = selectedMonth
        while currentMonth > startingPointDate {
            guard let prevMonth = previousMonth(of: currentMonth) else { break }
            
            // Calculate leftover for the previous month using allocations
            let prevMonthTransactions = transactionsForMonth(transactions, selectedMonth: prevMonth)
            let prevMonthLeftover = leftoverForMonth(
                allCategories: categories,
                allocations: allocations, // Pass allocations
                selectedMonth: prevMonth, // Pass selected month
                monthTransactions: prevMonthTransactions
            )
            
            // Add to rollover balance
            rolloverLeftover += prevMonthLeftover
            
            // Move to previous month
            currentMonth = prevMonth
        }
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
                    ContentUnavailableView("No Goals", systemImage: "plus.circle")
                } else {
                    List {
                        ForEach($goals) { $goal in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(goal.title)
                                        .font(.headline)
                                    Spacer()
                                    Text("$\(goal.currentAmount, specifier: "%.2f") / $\(goal.targetAmount, specifier: "%.2f")")
                                }
                                
                                ProgressView(value: goal.currentAmount, total: goal.targetAmount)
                                    .progressViewStyle(LinearProgressViewStyle())
                            }
                            .padding(.vertical, 8)
                        }
                        .onDelete { indexes in
                            goals.remove(atOffsets: indexes)
                        }
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



// MARK: - Rollover Detail Screen

/// Shows the current rollover leftover plus a short explanation of how it’s calculated.
/// Also has a button to transfer funds from/to the rollover.
struct RolloverDetailView: View {
    @Binding var rolloverLeftover: Double
    @Binding var categories: [CategoryBudget]
    @Binding var goals: [SavingsGoal]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation]
    let overallBudget: Double
    let selectedMonth: Date
    
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
                    categories: $categories,
                    goals: $goals,
                    transactions: $transactions,
                    allocations: $allocations,
                    selectedMonth: selectedMonth
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
    @Binding var goals: [SavingsGoal]
    @Binding var transactions: [Transaction]
    @Binding var allocations: [CategoryAllocation] // Added this line
    let selectedMonth: Date
    
    @State private var amountString = ""
    @State private var errorMessage = ""
    @State private var transferToGoal = false

    @State private var selectedGoalIndex = 0
    @State private var selectedCategoryIndex = 0
    
    // Computed Properties
    private var computedMonthlySpentByCategory: [UUID: Double] { // Renamed to avoid conflict
        monthlySpentByCategory(categories: categories, transactions: transactionsForMonth(transactions, selectedMonth: selectedMonth))
    }

    private var selectedCategoryBalance: Double {
        if categories.indices.contains(selectedCategoryIndex) {
            let selectedCategory = categories[selectedCategoryIndex]
            let spent = computedMonthlySpentByCategory[selectedCategory.id] ?? 0 // Updated reference
            // Get allocated amount for the category in the selected month
            let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedMonth))!
            let allocation = allocations.first(where: { $0.categoryID == selectedCategory.id && sameMonth($0.month, selectedMonth) })
            let allocatedAmount = allocation?.allocatedAmount ?? selectedCategory.total
            return allocatedAmount - spent
        }
        return 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Transfer From") {
                    Text("Rollover Balance")
                }
                
                Section("Transfer To") {
                    Picker("Destination", selection: $transferToGoal) {
                        Text("Category").tag(false)
                        Text("Savings Goal").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if transferToGoal {
                        Picker("Select Goal", selection: $selectedGoalIndex) {
                            ForEach(goals.indices, id: \.self) { index in
                                Text(goals[index].title).tag(index)
                            }
                        }
                        .pickerStyle(.wheel) // Optional: specify picker style
                        
                        // Existing Remaining to Reach Goal Text
                        if goals.indices.contains(selectedGoalIndex) {
                            Text("Remaining to reach goal: \(goals[selectedGoalIndex].targetAmount - goals[selectedGoalIndex].currentAmount, format: .currency(code: "USD"))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Select Category", selection: $selectedCategoryIndex) {
                            ForEach(categories.indices, id: \.self) { index in
                                Text(categories[index].name).tag(index)
                            }
                        }
                        .pickerStyle(.wheel) // Optional: specify picker style
                        
                        // Add Current Balance Text View
                        if categories.indices.contains(selectedCategoryIndex) {
                            Text("Current balance: \(selectedCategoryBalance, format: .currency(code: "USD"))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
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
        guard let amount = Double(amountString), amount > 0 else {
            errorMessage = "Please enter a valid amount"
            return
        }
        
        guard amount <= rolloverLeftover else {
            errorMessage = "Amount exceeds rollover balance"
            return
        }
        
        if transferToGoal {
            // Transfer to goal
            goals[selectedGoalIndex].currentAmount += amount
        } else {
            // Transfer to category
            let selectedCategory = categories[selectedCategoryIndex]
            let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedMonth))!
            
            if let allocationIndex = allocations.firstIndex(where: { $0.categoryID == selectedCategory.id && sameMonth($0.month, selectedMonth) }) {
                allocations[allocationIndex].allocatedAmount += amount
            } else {
                let newAllocation = CategoryAllocation(categoryID: selectedCategory.id, month: monthStart, allocatedAmount: selectedCategory.total + amount)
                allocations.append(newAllocation)
            }
        }
        
        rolloverLeftover -= amount
        dismiss()
    }
}

// MARK: - Data Helpers

private func saveData<T: Encodable>(_ data: T, to filename: String) {
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(filename)
    do {
        let encodedData = try JSONEncoder().encode(data)
        try encodedData.write(to: url)
    } catch {
        print("Error saving \(filename): \(error)")
    }
}

private func loadData<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(filename)
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    } catch {
        print("Error loading \(filename): \(error)")
        return nil
    }
}


#Preview {
    ContentView()
}
