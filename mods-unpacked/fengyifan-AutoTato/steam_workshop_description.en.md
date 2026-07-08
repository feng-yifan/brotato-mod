[b][size=6]AutoTato Guide[/size][/b]

[b][size=5]What is this?[/size][/b]
AutoTato is an automation mod. It auto-buys shop items, auto-rerolls the shop, and auto-picks upgrades for you, so you can focus on the combat itself.

[b][size=5]Basic Controls[/size][/b]

[b]Shop AutoTato Button[/b]
After entering the shop, there is an "AutoTato & Reroll" button in the title bar.
- Click the button: runs one shop decision (auto-buy/lock/skip), then attempts to reroll the shop once.
- Press the shortcut (gamepad B / keyboard R): opens the rule config popup on an item card to set how you want each item handled. Supported in both the shop and chest item screens.

[b]Upgrade AutoTato Button[/b]
On the upgrade screen (when choosing 1 of 4 upgrades), there is an "AutoTato" button below the reroll button.
- Click the button: runs one upgrade decision (picks the best option per your upgrade strategy and selects it).
- Press the shortcut (gamepad X / keyboard E): same effect, triggers one upgrade decision. Shares the same shortcut with the AutoTato button on the chest item screen.
- When the "Upgrade Automation" toggle is on, entering the upgrade screen auto-starts the decision — no manual click needed.

[b]Reroll Button[/b]
The game's built-in reroll button rerolls the shop or upgrade options. Trigger automation through the AutoTato button instead.

[b]Settings Panel[/b]
You can find the AutoTato settings panel in the pause menu. Main settings:
- Shop Automation: master toggle. When off, the shop will not be auto-handled on entry, but you can still click the AutoTato button to manually trigger one round.
- Upgrade Automation: master toggle. When off, the upgrade screen will not auto-select on entry, but you can still click the AutoTato button (or press E) to manually trigger one round.
- Turbo Mode: when on, automation completes all actions instantly with no animation delay.
- Minimum Gold Balance: minimum gold to keep after buying items (prevents spending it all).
- Item Price Limit: items above this price will not be auto-bought. Set to 0 for no limit.
- Reroll Budget: if a single reroll costs more than this, it will not auto-reroll. Set to 0 for no limit (only checks whether you have enough gold).
- Auto Start Next Wave: after automation finishes and rerolling is no longer possible, automatically clicks the "Next Wave" button to enter combat.

[b]Upgrade Strategy Settings[/b]
In the Upgrade tab you can adjust how upgrade automation picks:
- Respect Thresholds: when on, an option is filtered out if ALL of its relevant stats have hit your configured threshold limits.
- Minimum Tier: upgrade options below this tier (Common/Rare/Epic/Legendary) are skipped.
- Quality First: when on, prioritizes higher-tier (rarity) upgrade options.
- Forbidden Stats: upgrade options containing these stats are filtered out.
- Ignore Forbid When Stuck: when all candidates are filtered, falls back to the unfiltered sort result (picks the highest-quality option).
- Stat Priority: among the highest-tier candidates, prioritizes options in the stat order you set.

[b]Item Rule Settings[/b]
In the shop or chest item screen, press gamepad B or keyboard R on an item card to open the rule config popup, where you can set both behaviors for that item at once:
- Shop Behavior: how to handle this item when encountered in the shop (Buy / Reject / Cursed Only / Lock Until Cursed / Manual).
- Chest Behavior: how to handle this item when opened from a chest (Take / Reject / Cursed Only / Manual).

Shop Behavior options:
- Buy: auto-buy on sight
- Reject: do not buy this item
- Cursed Only: only buy the cursed version
- Lock Until Cursed: lock the non-cursed version and wait for the cursed one to buy (fishhook meta)
- Manual: do not auto-handle, leave it to you (this is the default)

Chest Behavior options:
- Take: auto-take on sight
- Reject: auto-discard on sight
- Cursed Only: only take the cursed version, auto-discard the non-cursed one
- Manual: do not auto-handle, leave it to you (this is the default)

[b]Weapon Rule Settings[/b]
Weapon rules are similar to item rules, with two extra options:
- Follow Set Rule: follows the rule of the weapon's category (e.g. "Firearms"). If any relevant category is set to Manual, the item is treated as Manual.
- Minimum Weapon Tier: sets the minimum weapon tier; weapons below this tier are auto-skipped.

[b][size=5]Special Behaviors[/size][/b]
The following are behaviors you might not immediately notice.

[b]Manual Item Lock vs Automation[/b]
If you manually lock an item in the shop (to prevent it from being rerolled away) and that item's rule happens to be "Manual", automation treats it as "Skip".
This means: a manually locked item will not trigger "a Manual item appeared, stop automation". Automation continues processing other items, while the locked one is preserved until the next wave.

[b]Items With No Rule Are Left Alone[/b]
If you have never set a rule for an item, it defaults to "Manual" — automation will not touch it, leaving it to you.
Weapons with no rule are the same — default "Manual", will not be auto-bought.

[b]No Reroll When All Items Are Locked[/b]
If you lock every item in the shop (all 4), automation detects that rerolling has no effect and will not reroll.

[b]About Banned Items[/b]
Under AutoTato, the vanilla banned-items feature is unavailable: gamepad B / keyboard R is used to open the item rule config popup, so there is no separate ban-item action. All item handling is configured through the rule popup. If you are playing a ban challenge mode, use the "Reject" option in the rule popup to achieve a similar effect.

[b]Closing the Rule Popup[/b]
Once the rule popup is open, you can close it via:
- Press ESC (keyboard) or gamepad B: closes the popup without triggering the pause menu.
- Click the semi-transparent dimmed overlay outside the popup: closes the popup.
- Click the "Save" or "Cancel" button: closes the popup (Save applies the rule, Cancel does not save).
Note: for a popup opened with gamepad B, the first B release will not close the popup (to prevent press-to-open / release-to-close jitter); you need to press B again to close it.

[b]Buttons Still Work When Automation Is Off[/b]
Even when the "Shop Automation" or "Upgrade Automation" toggles are off, clicking the corresponding AutoTato button still runs one decision round.

[b]Upgrade Automation Off: Each Press Advances One Round[/b]
When the "Upgrade Automation" toggle is off, manually pressing the AutoTato button (or E) once runs one decision round: if any of the current 4 candidates is eligible, it selects it; if none, it rerolls once for new candidates and then stops, letting you take a look before deciding whether to press again. In other words, when the toggle is off, it does not auto-reroll continuously — each advance requires a manual trigger.

[b]Upgrade Automation Reroll Loop[/b]
When the "Upgrade Automation" toggle is on, entering the upgrade screen auto-starts the decision and loops as follows:
1. Decide on the current 4 candidates (filter + sort per upgrade strategy)
2. If an eligible option is found, select it and end this round
3. If no eligible option, reroll once and continue to the next round
4. Repeat until an option is selected, gold is insufficient to reroll, or the reroll price exceeds the limit

[b]Fallback When Upgrade Gets Stuck[/b]
If rerolling exhausts your gold without finding an eligible candidate and the "Ignore Forbid When Stuck" toggle is on, it auto-selects the highest-tier (rarity) option among the currently visible candidates. If that toggle is off, it does not auto-select and hands control back to you.

[b]Auto-Reroll Stops On Its Own[/b]
With automation on, shop or upgrade auto-reroll stops when any of the following occurs:
1. A "Manual" item appears in the shop (needs your decision)
2. All shop items are unaffordable
3. Gold is insufficient to pay the reroll fee
4. A single reroll's price exceeds your configured limit

It will not reroll indefinitely and drain your gold.

[b]Reroll Budget Is Per-Reroll Price[/b]
The "Reroll Budget" setting controls the price of a single reroll, not a cumulative total. Rerolls above this price will not be auto-triggered. Set to 0 for no limit.
