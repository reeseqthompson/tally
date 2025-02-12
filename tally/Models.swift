////
////  Models.swift
////  tally
////
////  Created by Reese Thompson on 2/12/25.
////
//
//import SwiftUI
//import SwiftData
//
//// MARK: – Color Helpers
//
//extension Color {
//    func toHex() -> String {
//        guard let components = UIColor(self).cgColor.components else { return "#000000" }
//        let r = Int((components[0] * 255.0).rounded())
//        let g = Int((components[1] * 255.0).rounded())
//        let b = Int((components[2] * 255.0).rounded())
//        return String(format: "#%02X%02X%02X", r, g, b)
//    }
//
//    init?(hex: String) {
//        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
//        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
//        var rgb: UInt64 = 0
//        Scanner(string: hexSanitized).scanHexInt64(&rgb)
//        let r = Double((rgb >> 16) & 0xFF) / 255.0
//        let g = Double((rgb >> 8) & 0xFF) / 255.0
//        let b = Double(rgb & 0xFF) / 255.0
//        self.init(red: r, green: g, blue: b)
//    }
//}
//
//// MARK: – Data Models (SwiftData @Model types)
//
//// Global categories (editable via settings)
//@Model
//final class TallyCategory: Identifiable {
//    var id: UUID = UUID()
//    var name: String
//    var total: Double
//    var colorHex: String
//
//    // Computed property for UI display only.
//    @Transient var color: Color {
//        get { Color(hex: colorHex) ?? .gray }
//        set { colorHex = newValue.toHex() }
//    }
//
//    init(name: String, total: Double, color: Color) {
//        self.name = name
//        self.total = total
//        self.colorHex = color.toHex()
//    }
//}
//
//// Transactions use the tally fields (note we rename “description” to avoid conflict)
//@Model
//final class TallyTransaction: Identifiable {
//    var id: UUID = UUID()
//    var categoryID: UUID
//    var date: Date
//    var amount: Double
//    var transactionDescription: String
//
//    init(categoryID: UUID, date: Date, amount: Double, transactionDescription: String) {
//        self.categoryID = categoryID
//        self.date = date
//        self.amount = amount
//        self.transactionDescription = transactionDescription
//    }
//}
//
//// Savings goals (for use in the “Goals” views)
//@Model
//final class TallySavingsGoal: Identifiable {
//    var id: UUID = UUID()
//    var title: String
//    var targetAmount: Double
//    var currentAmount: Double
//
//    init(title: String, targetAmount: Double, currentAmount: Double = 0) {
//        self.title = title
//        self.targetAmount = targetAmount
//        self.currentAmount = currentAmount
//    }
//}
//
//// Per‑month transfers (additional funds allocated to a category for a month)
//@Model
//final class TallyCategoryAllocation: Identifiable {
//    var id: UUID = UUID()
//    var categoryID: UUID
//    var month: Date
//    var allocatedAmount: Double
//
//    init(categoryID: UUID, month: Date, allocatedAmount: Double) {
//        self.categoryID = categoryID
//        self.month = month
//        self.allocatedAmount = allocatedAmount
//    }
//}
//
//// The “monthly budget” is stored separately so the user may copy/edit the base budget
//// for a given month. (A new monthly budget is created by copying the global TallyCategory values.)
//@Model
//final class TallyCategoryBudget: Identifiable {
//    var id: UUID = UUID()
//    var name: String
//    var total: Double
//    var colorHex: String
//
//    @Transient var color: Color {
//        get { Color(hex: colorHex) ?? .gray }
//        set { colorHex = newValue.toHex() }
//    }
//
//    init(name: String, total: Double, color: Color) {
//        self.name = name
//        self.total = total
//        self.colorHex = color.toHex()
//    }
//}
//
//@Model
//final class TallyMonthlyBudget: Identifiable {
//    var id: UUID = UUID()
//    var month: Date
//    var categories: [TallyCategoryBudget]
//
//    init(month: Date, categories: [TallyCategoryBudget]) {
//        self.month = month
//        self.categories = categories
//    }
//}
