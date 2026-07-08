[h1]AutoTato Guide[/h1]

[h2]What is this?[/h2]
AutoTato is an automation mod. It auto-buys shop items, auto-rerolls, and auto-picks upgrades, so you can focus on combat.

[h2]Basic Controls[/h2]

[b]Shop AutoTato Button[/b]
An "AutoTato & Reroll" button appears in the shop title bar.
[list]
[*]Click: run one shop decision (buy/lock/skip), then reroll once.
[*]Gamepad B / keyboard R: open the rule popup on an item card. Works in shop and chest screens.
[/list]

[b]Upgrade AutoTato Button[/b]
On the upgrade screen (pick 1 of 4), an "AutoTato" button sits below the reroll button.
[list]
[*]Click: run one upgrade decision (pick the best option per your strategy).
[*]Gamepad X / keyboard E: same effect. Shares the shortcut with the chest AutoTato button.
[*]With "Upgrade Automation" on, entering the screen auto-starts the decision.
[/list]

[b]Reroll Button[/b]
The vanilla reroll button only rerolls. Use the AutoTato button to trigger automation.

[b]Settings Panel[/b]
Found in the pause menu:
[list]
[*]Shop Automation: master toggle. Off = no auto-handle on entry, but the button still works.
[*]Upgrade Automation: master toggle. Off = no auto-select on entry, but the button (or E) still works.
[*]Turbo Mode: complete all actions instantly, no animation delay.
[*]Minimum Gold Balance: gold to keep after buying (prevents spending it all).
[*]Item Price Limit: skip auto-buy above this price. 0 = no limit.
[*]Reroll Budget: skip auto-reroll above this single-reroll price. 0 = no limit.
[*]Auto Start Next Wave: click "Next Wave" automatically when rerolling is no longer possible.
[/list]

[b]Upgrade Strategy[/b]
[list]
[*]Respect Thresholds: filter an option when ALL its relevant stats hit your threshold limits.
[*]Minimum Tier: skip options below this tier (Common/Rare/Epic/Legendary).
[*]Quality First: prioritize higher-tier options.
[*]Forbidden Stats: filter options containing these stats.
[*]Ignore Forbid When Stuck: when all filtered, fall back to unfiltered sort (pick highest quality).
[*]Stat Priority: among the highest tier, pick by your stat order.
[/list]

[b]Item Rules[/b]
Press gamepad B / keyboard R on an item card to open the rule popup:
[list]
[*]Shop Behavior: Buy / Reject / Cursed Only / Lock Until Cursed / Manual.
[*]Chest Behavior: Take / Reject / Cursed Only / Manual.
[/list]
Shop options: Buy (auto-buy), Reject (never buy), Cursed Only (only cursed version), Lock Until Cursed (lock non-cursed, buy when cursed - fishhook meta), Manual (leave to you, default).
Chest options: Take (auto-take), Reject (auto-discard), Cursed Only (only cursed, discard rest), Manual (default).

[b]Weapon Rules[/b]
Same as items, plus:
[list]
[*]Follow Set Rule: follow the weapon's category rule (e.g. "Firearms"). If any category is Manual, the weapon is Manual.
[*]Minimum Weapon Tier: skip weapons below this tier.
[/list]

[h2]Special Behaviors[/h2]

[b]Manual Lock vs Automation[/b]
A manually locked item whose rule is "Manual" is treated as "Skip" - it does not stop automation. Automation continues; the locked item is kept for the next wave.

[b]No Rule = Left Alone[/b]
Items and weapons with no rule default to "Manual" - automation will not touch them.

[b]All Locked = No Reroll[/b]
If all 4 shop items are locked, automation skips rerolling (it has no effect).

[b]Banned Items[/b]
Vanilla ban is unavailable: gamepad B / keyboard R opens the rule popup. Use the "Reject" option for a similar effect in ban challenge modes.

[b]Closing the Rule Popup[/b]
[list]
[*]ESC / gamepad B: close (does not open the pause menu).
[*]Click the dimmed overlay outside: close.
[*]Save / Cancel button: close (Save applies, Cancel discards).
[/list]
Note: a popup opened with B needs a second B press to close (prevents open/close jitter).

[b]Buttons Work When Automation Is Off[/b]
Clicking the AutoTato button always runs one round, even with the toggle off.

[b]Upgrade Off: One Press, One Step[/b]
With "Upgrade Automation" off, each press runs one round: pick an eligible option if any; otherwise reroll once and stop. No continuous auto-reroll - each step needs a manual trigger.

[b]Upgrade On: Reroll Loop[/b]
With "Upgrade Automation" on, entering the screen auto-starts:
[olist]
[*]Decide on the 4 candidates (filter + sort).
[*]Pick an eligible one -> done.
[*]None eligible -> reroll once, repeat.
[*]Stop when picked, gold insufficient, or reroll price exceeds the limit.
[/olist]

[b]Stuck Fallback[/b]
If gold runs out with no eligible candidate and "Ignore Forbid When Stuck" is on, auto-pick the highest-tier visible option. Otherwise, hand control back to you.

[b]Auto-Reroll Stops On Its Own[/b]
Stops when any of these occurs:
[olist]
[*]A "Manual" item appears (needs your decision).
[*]All items unaffordable.
[*]Gold insufficient for the reroll fee.
[*]Reroll price exceeds your limit.
[/olist]
It will not drain your gold.

[b]Reroll Budget = Per-Reroll[/b]
"Reroll Budget" caps a single reroll's price, not the cumulative total. 0 = no limit.

[hr]
Issues or suggestions? Visit the [url=https://github.com/feng-yifan/brotato-mod]GitHub repository[/url].
