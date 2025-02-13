
# todo

this document records todo & status comments on the progress of this project and should be updated before taking any substantial development break. This includes updates for git commits, but also intermediate updates to note issues & updates.

## Status
- I think all the allocations and transactions and savings are working correctly (except for the stuff noted below) but i didn't look super close at anything or really test much.

## Known Bugs
- nothing saves when I close the app at all (need to restructure to use classes & SwiftData)

- currently you can over-allocate to savings goals
- transactions appear editable in overall budget but are not
- category is not displated correctly on calendar view transaction log
- on the logs page:
    - category is dispalyed as ID, make it "Month YYYY CategoryName"
    - savingsgoal is displayed as GoalID, make it "SavingsGoalName"
    - savingsgoal also says transfer from rollover but that is implied (always true) so remove it
    
- the settings menu does nothing, need to completely rethink prob

## Desired Features
- make it so savings goal text is editable
- make it so savings goals are deletable?
- implement budget changes per month
