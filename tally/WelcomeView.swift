//
//  WelcomeView.swift
//  tally
//
//  Created by Reese Thompson on 3/3/25.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismiss) var dismiss
    // Bindings to update the main app’s state.
    @Binding var monthlyBudgets: [String: [CategoryBudget]]
    @Binding var globalCategories: [CategoryBudget]
    @Binding var selectedMonth: Date

    // Use AppStorage to track if this is the first launch.
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false

    // Local state for the welcome flow.
    @State private var overallBudgetText: String = ""
    @State private var step: Int = 1  // 1: enter overall budget, 2: edit category allocations
    @State private var customCategories: [CategoryBudget] = []

    // Convert the overall budget text to a Double.
    var overallBudget: Double? {
        Double(overallBudgetText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            if step == 1 {
                // Step 1: Ask for overall monthly budget.
                Form {
                    Section(header: Text("Enter your overall monthly budget")) {
//                        Text("Enter your overall monthly budget:")
                        TextField("Budget Amount", text: $overallBudgetText)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
                            .onChange(of: overallBudgetText) { newValue in
                                overallBudgetText.validateDecimalInput()
                            }
                    }
                    Button("Next") {
                        if let budget = overallBudget, budget > 0 {
                            // Compute default allocations:
                            // Round each allocation to the nearest dollar.
                            let housing = (budget * 0.3).rounded()
                            let transportation = (budget * 0.3).rounded()
                            let food = (budget * 0.3).rounded()
                            // For "Other", subtract the three above to ensure the total sums to the overall budget.
                            let other = budget - (housing + transportation + food)
                            
                            // Create default categories with appropriate emojis.
                            customCategories = [
                                CategoryBudget(name: "🏠 Housing", total: housing, color: .yellow),
                                CategoryBudget(name: "🚗 Transportation", total: transportation, color: .green),
                                CategoryBudget(name: "🍕 Food", total: food, color: .orange),
                                CategoryBudget(name: "📦 Other", total: other, color: .gray)
                            ]
                            step = 2  // Proceed to the category customization step.
                        }
                    }
                }
                .navigationTitle("Welcome to Tally")
            } else {
                // Step 2: Allow the user to edit categories.
                Form {
                    Section(header: Text("Customize Your Categories")) {
                        ForEach(customCategories.indices, id: \.self) { index in
                            VStack(alignment: .leading) {
                                TextField("Category Name", text: $customCategories[index].name)
                                TextField("Allocation", value: $customCategories[index].total, format: .number)
                                    .keyboardType(.decimalPad)
                                    .onChange(of: customCategories[index].total) { newValue in
                                        // Round to 2 decimal places
                                        customCategories[index].total = (newValue * 100).rounded() / 100
                                    }
                            }
                        }
                        .onDelete { offsets in
                            customCategories.remove(atOffsets: offsets)
                        }
                        Button("Add Category") {
                            // Append a new blank category.
                            customCategories.append(CategoryBudget(name: "New Category", total: 0, color: .gray))
                        }
                    }
                    Section {
                        Button("Finish Setup") {
                            // Save the configured budget for the current month.
                            let key = monthKey(for: selectedMonth)
                            monthlyBudgets[key] = customCategories
                            // Mark that the welcome process has been completed.
                            hasLaunchedBefore = true
                            // Dismiss the welcome view.
                            dismiss()
                        }
                    }
                }
                .navigationTitle("Edit Categories")
            }
        }
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(
            monthlyBudgets: .constant([:]),
            globalCategories: .constant([]),
            selectedMonth: .constant(Date())
        )
    }
}
