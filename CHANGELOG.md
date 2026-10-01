# Changelog -- Wick's Ledger

## 0.2.6 - 2026-10-01

### Fixed

- Loads on the 2.5.6 client without being marked out of date. The addon
  now lists interface 20506 alongside 20505.

## 0.2.5 -- 2026-05-15

- Fix panel not opening. Item rows were created as Frame instead of Button, so mouse events including right-click and tooltip hover were never firing.

## 0.2.4 -- 2026-05-15

- Fix panel becoming unresponsive after right-clicking an item row. The dismiss overlay was blocking all mouse input to the panel.

## 0.2.3 -- 2026-05-15

- Right-click any item row to revert its price to vendor sell value. Useful for AH outliers that inflate the G/hr rate. The row updates immediately and the v suffix confirms vendor pricing is active.

## 0.2.2 -- 2026-05-14

- Fix item rows overlapping when the row pool is reused. Recycled rows now clear their anchor points before being repositioned.

## 0.2.1 -- 2026-05-13

- Grey (Poor quality) items collapse into a single Junk row valued at vendor price. Count shown, no individual entries cluttering the list.
- Hard lock mode: session pauses on instance exit instead of stopping. Re-enter to resume where you left off, gold and loot intact. Toggle via `/wledger lock` or the Options panel.

## 0.2.0 -- 2026-05-13

### Session persistence + history

- Session state survives /reload mid-dungeon. Gold delta, loot, XP, and rep are written to SavedVariablesPerCharacter on every change and restored on login. Sessions older than 8 hours are discarded automatically.
- History tab in the panel shows the last 5 completed sessions (date, zone, total earned). Zero-value sessions are not saved.
- /hr projection now uses total earnings (raw gold + item value), rounded to whole gold.
- Item value shown per-line in the panel; /hr hidden from line items to reduce noise.

## 0.1.0 -- 2026-05-12

Initial release.

- Slim always-visible bar showing session earnings in real time
- Expandable itemized panel with icon, name, quantity, and per-item valuation
- AH price chain: TSM > Auctionator > Auctioneer > vendor sell price
- Raw gold delta tracking via PLAYER_MONEY
- Loot tracking via CHAT_MSG_LOOT with per-item accumulation
- Auto-start/stop on instance entry and exit
- Manual control via /wledger start, stop, reset
- Draggable minimap button
