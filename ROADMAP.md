# Roadmap

What Dutch might grow into, and what it deliberately won't.

Three constraints decide everything here: the app stays **fast**, stays **native**
(Apple frameworks only, no dependencies), and stays **under 3 MB**. A feature that
can't be built inside those isn't a feature for this app.

On the size budget specifically: pure Swift and SwiftUI with no bundled assets
lands around 1–2 MB, and every framework named below ships with the OS rather
than with the binary — SF Symbols, WidgetKit, AppIntents and CoreSpotlight all
cost approximately nothing. What would actually breach 3 MB is bundled fonts,
image assets, an embedded rate database, or CoreML. None of the work below needs
any of those. Watch the asset catalog, not the code.

---

## Shipped

- Groups, members, expenses, equal splits
- Settlement (balances + a short list of payments that clears them)
- iCloud sync and group sharing by QR code
- Expenses entered in a foreign currency, converted once at entry

## In progress

Items 1–4 below. All four are being built together because 2 and 3 share a single
Core Data version bump, and doing that migration twice would be worse than doing
it once.

### 1. Edit an expense

The only correction available today is swipe-to-delete and re-enter, which on a
shared group means the other person watches an expense vanish and reappear over
CloudKit. The form already holds every field; it needs to accept an existing
expense and update rather than insert.

*Cost: zero bytes. No model change.*

### 2. Record a settlement

Nothing lets someone say "I paid Anna the 40 back", so a long-running group only
ever accumulates.

The useful property: a payment is already expressible in the existing maths. A
pays B is an expense **paid by A, split among B alone** — which nets A up and B
down by exactly the amount, and settles them. `SettlementCalculator` needs no
change at all. The only new state is a flag so the row renders as a payment
rather than an expense, and so it stays out of Total Spent.

*Cost: one optional Bool. Model v3.*

### 3. Unequal splits

Equal-only is the ceiling on real use: the hotel room two people share, the one
who didn't drink. Modelled as **integer shares** (1×, 2×) rather than percentages
or exact amounts, because shares stay exact — `Money.split` already distributes
the remainder rather than dropping it, and weighting it preserves that guarantee.

Stored as a weight overlay keyed by person, with `splitAmong` still authoritative
for *who* is in the split. Absent weights mean an even split, so every existing
expense keeps reading exactly as it did.

*Cost: one optional String. Model v3, shared with item 2. Logic lives in DutchKit
and is testable without a simulator.*

### 4. Who am I in this group

There's no notion of which member is the person holding the phone, so every
balance is third-person. "You owe 120" is a better sentence than "Marek owes 120",
and it's a prerequisite for the widget.

Belongs in `ExpenseDefaults` alongside `lastPayer` — same reasoning: it's a fact
about the device, not about the group, and syncing it would overwrite everyone
else's answer.

*Cost: a `UserDefaults` key. No model change.*

---

## Next

### 5. App Intents / Shortcuts

"Add 60 to green-moon-tea" from Siri or the Action button, no app launch. The
highest speed-per-kilobyte item on the list, and a natural fit for an app whose
whole point is entering a number in five seconds. `AppIntents` is system-provided;
only the intent definitions land in the binary.

### 6. Member avatars from SF Symbols

A glyph per member, chosen from a curated set of SF Symbols. Because the symbols
ship with the OS, a full set of avatars costs one optional String on `Person` and
nothing in the bundle — where photo avatars would mean an image pipeline, CloudKit
assets and sync weight.

Two things to get right: the curated list must be pinned to symbols available at
the deployment target (iOS 17), since a name that doesn't resolve renders as
nothing at all; and the symbol has to stay decorative — the accessibility label
is the member's name, not the glyph.

### 7. Home screen widget

"You owe €120 · green-moon-tea". A WidgetKit extension reading the same store.
Depends on item 4. A couple hundred KB for the extension binary.

### 8. Share a summary

`ShareLink` over a generated text block: who owes whom, the total, the expense
list. Pure string building, zero framework cost, and it matches how people
actually settle — pasted into the group chat.

### 9. Categories

An optional String on `Expense` holding an SF Symbol name, same trick as item 6.
Groups the expense list and costs nothing in the bundle.

### 10. Archive a group

Trips end; the list never shrinks. One optional Date and a filtered
`@FetchRequest`.

### 11. Spotlight indexing

Groups and expenses searchable from the home screen via `CoreSpotlight`. System
framework, small integration, and it makes a five-second app reachable in two.

---

## Not planned

These are the requests to expect, and the reasons they don't fit:

**Receipt photos.** Breaks all three constraints at once — CloudKit assets, sync
weight, storage, and an image pipeline in a codebase that currently rasterises
exactly one QR code.

**Live exchange rates.** Rates are frozen at entry deliberately (see CLAUDE.md);
that decision is what stops a shared trip's balances from drifting and reopening
debts that were already settled. Fetching rates adds a network dependency, a
cache, and a failure mode in order to reintroduce the problem.

**A charts tab.** Swift Charts is system-provided so it's technically free, but
it's a screen nobody opens twice for a group with eleven expenses in it.

**A backend, accounts, or login.** The absence of one is the design.

---

## Rules of thumb

- New logic goes in DutchKit if it can be tested without a simulator and without
  an iCloud account. Keep Core Data, SwiftUI and CloudKit types out of it.
- New model attributes are optional, arrive in a new model version, and mean
  promoting the CloudKit schema to production before shipping.
- Prefer a system framework over a hand-rolled equivalent, and no framework over
  either.
