# Tally (Budgeting App) – Design Document

## Table of Contents
1. [Overview](#overview)
2. [Project Goals](#project-goals)
3. [Scope and Features](#scope-and-features)
   - [Core Features](#core-features)
   - [User Flow](#user-flow)
   - [Interface Structure](#interface-structure)
   - [Data Security & Login](#data-security--login)
   - [User Feedback & Updates](#user-feedback--updates)
4. [Stretch Goals](#stretch-goals)
5. [Technical Considerations](#technical-considerations)
   - [Technology Stack](#technology-stack)
   - [Data Model](#data-model)
   - [Third-Party Integration](#third-party-integration)
6. [User Stories](#user-stories)
7. [Roadmap & Milestones](#roadmap--milestones)
8. [Appendix](#appendix)

---

## Overview
**Tally** is an iOS application built with Swift, designed to help users budget and track their financial transactions. The app allows users to create and maintain budgets, record transactions in specific categories, and monitor their spending against set limits each month. Users can also set and track savings goals, allocate rollover budget from previous months, and  integrate with external services to automate their transaction inputs.

---

## Project Goals
1. **Encourage Better Financial Habits**  
   Provide an easy-to-use interface that prompts users to plan monthly budgets and stick to them by actively monitoring their spending.

2. **Flexible and Scalable**  
   Allow the app to evolve over time (e.g., integrating automatic transaction imports, advanced data visualization, and secure data handling).

3. **User-Friendly Onboarding**  
   Offer a simple welcome process that sets up a recommended budget based on user income.

---

## Scope and Features

### Core Features
1. **User Onboarding and Budget Initialization**  
   - **Welcome Screen**: A greeting and a brief explanation of the app.  
   - **Income Prompt**: Users enter their monthly take-home pay.  
   - **Budget Recommendation**: The app suggests a default budget based on a percentage allocation model.

2. **Home Screen**  
   - Displays each spending category’s remaining balance for the month.  
   - Shows “Rollover from the previous month” if any.

3. **Savings Goals**  
   - Users can set specific savings targets.  
   - Users can allocate rollovers to savings goals.  
   - Rewarding visual indicators (e.g., confetti animation) when goals are met.

4. **Transaction Recording**  
   - **Record Button (in bottom toolbar)**: Opens a transaction entry form.  
   - **Transaction Form**:
     - Name/Description of the transaction
     - Dollar value
     - Category (e.g., Groceries, Entertainment)
     - Date (default to current date but user can adjust)
     - Optional Notes

5. **Transaction History**  
   - Separate screen listing all transactions in reverse chronological order (most recent first).  
   - Ability to filter or search (future enhancement).

6. **Settings**  
   - Edit budget categories, amounts, or monthly income.  
   - Update rollover and savings goals.  
   - Basic support email link for troubleshooting.

---

### User Flow
1. **Launch App**  
   - User is greeted by the Welcome Screen.
2. **Input Income & Initial Budget**  
   - User enters monthly net income.
   - App suggests a default budget distribution (with the option to edit).
3. **Home Screen**  
   - Shows category balances, rollover amount, and quick navigation.  
   - Bottom toolbar includes a **Record Transaction** button.
4. **Record Transaction**  
   - Opens a form for inputting transaction details.  
   - Deducts from the budget’s corresponding category.
5. **Savings Goals**  
   - Users can see progress bars and set or modify goals.  
   - Rollover can be allocated to these goals.
6. **Settings & Support**  
   - Manage budgets, categories, user info, and email for support inquiries.

---

### Interface Structure
1. **Top Toolbar (Home Screen)**  
   - **Savings Goals** (leftmost icon)  
   - **Wallet** (for future Plaid integration; initially grayed out)  
   - **Transaction History**  
   - **Settings** (rightmost icon)

2. **Bottom Toolbar (Home Screen)**  
   - **Record Transaction Button** (centered or easily accessible)

3. **Fifth Paid Feature (Data Insights)**  
   - This premium feature (purchasable within the app) unlocks advanced data visualization, subscription tracking, and more detailed spending insights.

---

### Data Security & Login
- **Login Option (Stretch)**: Users can create an account to save data in the cloud.  
- **Local Storage**: MVP may rely on local data storage within the app container.  
- **Future Enhancements**: Encryption, secure cloud storage, biometric login (Face ID/Touch ID), etc.

---

### User Feedback & Updates
- **App Store Feedback**: Users will provide ratings and reviews.  
- **Email Support**: A support email will be listed in the Settings for direct inquiries.  
- **Updates**: Incremental improvements and feature rollouts will be managed through standard App Store updates.

---

## Stretch Goals
1. **Automatic Bank Sync**  
   - Integrate with Plaid or a similar service to import transactions automatically.  
   - Must confirm feasibility of free tiers or alternative low-cost solutions.

2. **Advanced Data Visualization**  
   - Paid upgrade unlocking dynamic charts, trend analysis, and subscription tracking.  
   - Possibly show daily/monthly/quarterly breakdowns.

3. **Enhanced Security**  
   - Cloud-based data with encryption.  
   - Biometric login (Face ID/Touch ID).  
   - Two-factor authentication.

4. **Community/Sharing Features**  
   - (Optional) Allow users to share budget templates or savings tips.  
   - Encourage collaboration and healthy financial habits.

---

## Technical Considerations

### Technology Stack
- **Platform**: iOS (Swift, SwiftUI or UIKit for UI design)
- **Database**: Local data using Core Data or SQLite for MVP  
- **Cloud Services (Future)**: Firebase or a custom backend if implementing user accounts

### Data Model
- **User**  
  - `userID`, `monthlyIncome`, `budgetAllocations`, `rollover`
- **Transaction**  
  - `transactionID`, `name`, `category`, `amount`, `date`, `notes`
- **Category**  
  - `categoryID`, `name`, `budgetedAmount`, `amountSpent`
- **Goal**  
  - `goalID`, `goalName`, `targetAmount`, `currentAmount`

### Third-Party Integration
- **Plaid or Similar**  
  - Syncing bank and credit card transaction data.  
  - Initially grayed out (Wallet icon) until implemented or enabled by user purchase.

---

## User Stories
1. **Onboarding User**  
   - *As a new user, I want to be guided through a setup process where I enter my monthly income, so I can quickly establish a budget.*
2. **Budget Monitoring**  
   - *As a user, I want to see how much money remains in each spending category, so I can avoid overspending.*
3. **Transaction Recording**  
   - *As a user, I want to record each of my expenses easily, so I can keep accurate track of my monthly spending.*
4. **Savings Goal**  
   - *As a user, I want to set a savings target and track my progress, so I can achieve my financial objectives.*
5. **Rollover Allocation**  
   - *As a user, I want to allocate leftover money from the previous month to a savings goal, so I can make progress towards long-term goals.*
6. **Settings Modification**  
   - *As a user, I want to update my budget categories and monthly income if my situation changes, so the app remains accurate.*

---

## Roadmap & Milestones
1. **MVP (Minimum Viable Product)**  
   - Implement core onboarding, budget creation, and transaction tracking.  
   - Basic UI and local data storage.  
   - Simple monthly rollover logic.
2. **Iteration 1**  
   - Add Savings Goals functionality.  
   - Provide basic analytics (e.g., total monthly spending).
3. **Iteration 2**  
   - Introduce optional login feature for data backup and sync.  
   - Paid upgrade for advanced charts and visualizations.
4. **Iteration 3**  
   - Integrate Plaid (or similar) for automatic transaction imports.  
   - Additional security enhancements, such as biometric login.
5. **Ongoing**  
   - Collect user feedback and continue to refine UI/UX.  
   - Expand budget categories and visualization tools.

---

## Appendix
- **App Name**: Tally (budgeting app)
- **Developer**: Reese Thompson
- **Target Release**: iOS App Store
- **Support**: Email link provided in Settings page

---

**End of Tally Design Document**
