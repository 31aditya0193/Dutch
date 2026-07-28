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

**The base:**

- Groups, members, expenses, equal splits
- Settlement (balances + a short list of payments that clears them)
- iCloud sync and group sharing by QR code
- Expenses entered in a foreign currency, converted once at entry

**Added since:** the seven below. The first four were built together because two
of them shared a single Core Data version bump and doing that migration twice
would have been worse than doing it once; nothing after them has needed a model
change at all. The reasoning is kept here because each one had a non-obvious
decision behind it.

### Edit an expense

The only correction used to be swipe-to-delete and re-enter, which on a shared
group means the other person watches an expense vanish and reappear over
CloudKit — with a window in between where the balances are wrong. One form now
adds and edits, rewriting one record in place and leaving its date alone.

*Cost: zero bytes. No model change.*

### Record a settlement

Nothing let someone say "I paid Anna the 40 back", so a long-running group only
ever accumulated.

The useful property: a payment was already expressible in the existing maths. A
pays B is an expense **paid by A, split among B alone** — which nets A up and B
down by exactly the amount, and settles them. `SettlementCalculator` needed no
change at all. The only new state is a flag so the row renders as a payment
rather than an expense, and so it stays out of Total Spent.

*Cost: one optional Bool. Model v3.*

### Uneven splits, by percentage

Equal-only was the ceiling on real use. Two cases from one real trip:

- a train ticket where one of six people has a 51% student discount;
- a hotel for six — two couples in two rooms, two people in singles — where all
  four rooms cost the same and each half of a couple should pay half a room.

Both are the same operation: **what someone pays relative to a full share**. So
the control is a percentage, 100% by default, set per expense from a menu of
100 / 75 / 50 / 25 with a typed value for anything else. The discount is a fact
about *the ticket*, not about the person — a student pays full price for beer —
so this lives on the expense and nowhere else.

Percent rather than a multiplier because reductions are the common case: 50% for
a couple, 49% for a discounted fare. `0.49×` cannot even be typed into a stepper.

The percentages across a split do not add up to 100 and are not meant to — six
people with one discounted fare comes to 549%. Nothing in the UI shows that
total; the rows show amounts in the group's currency, and those do add up.

Stored as an integer weight overlay keyed by person, with `splitAmong` still
authoritative for *who* is in the split. Absent weights mean an even split, so
every existing expense keeps reading exactly as it did.

*Cost: one optional String. Model v3, shared with the settlement flag. Logic
lives in DutchKit and is testable without a simulator.*

### Who am I in this group

There was no notion of which member is the person holding the phone, so every
balance read in the third person. "You owe 120" is a better sentence than "Marek
owes 120", and it is a prerequisite for the widget.

Lives in `ExpenseDefaults` alongside `lastPayer` — same reasoning: it is a fact
about the device, not about the group, and syncing it would tell everyone else in
the group that they are Marek too.

*Cost: a `UserDefaults` key. No model change.*

### Duplicate an expense

Buying rounds was the case. Four people take turns at the bar, and each round is
the same title, the same amount and the same split — everything except who paid.
That was four full trips through the form, and the payer prefill actively worked
against you: `ExpenseDefaults.lastPayer` suggests whoever paid last, which in a
round is precisely the person who is *not* paying now.

Touch and hold an expense → **Duplicate** → the form opens carrying everything
over. Four rounds are one full entry and three pairs of taps. It also catches the
everyday repeat on a trip: the same coffee, the same parking, the same ticket.

Duplication rather than a cleverer prefill, deliberately. Guessing who pays next
is fortune-telling; copying what the user already entered is not.

The payer is the one field deliberately left empty, which also leaves Save
disabled until it is answered. Carrying the original over would mean a whole
round could be logged against the wrong person with a single tap — and the payer
is the only reason this screen is open. Everything else is a copy, including the
currency and the rate it was captured at, so a duplicated foreign receipt
converts exactly as the original did rather than at whatever rate was last used.

Long-press rather than a swipe action or a row button: this is wanted often
enough to exist and read often enough that it shouldn't take up space in the
list. Payments are excluded — settling up is recorded from the section above,
and paying the same debt twice is a mistake rather than a shortcut.

*Cost: zero bytes. No model change; `GroupStore.addExpense` already took every
field this needed.*

### Share a summary

`ShareLink` over a generated text block: who owes whom, the total, the expense
list. Pure string building, zero framework cost, and it matches how people
actually settle — pasted into the group chat.

### Your standing on the group list

The list showed each group's *total spent*, which is a fact about the trip and
not about you — the number you actually came for was one tap away, on every
group. Once the device knows who you are, the row leads with what you owe or are
owed, tinted and captioned exactly as the member rows on the detail screen are.

The total gives up its place rather than sharing the corner with the personal
figure: two amounts side by side make each of them something to decode. Groups
where identity hasn't been set read exactly as they always did.

The word sequence came off the row at the same time. It is a label for pairing a
new phone, printed next to the QR code on the share screen; on the list it was
taking the line the standing now uses.

*Cost: zero bytes. Reads the `ExpenseDefaults` identity the detail screen already
writes, and the standing itself came out of `MemberBalanceRow` into a shared type
so both screens phrase and colour a balance identically.*

---

## Next

### 6. App Intents / Shortcuts

"Add 60 to green-moon-tea" from Siri or the Action button, no app launch. The
highest speed-per-kilobyte item on the list, and a natural fit for an app whose
whole point is entering a number in five seconds. `AppIntents` is system-provided;
only the intent definitions land in the binary.

### 7. Member avatars from SF Symbols

A glyph per member, chosen from a curated set of SF Symbols. Because the symbols
ship with the OS, a full set of avatars costs one optional String on `Person` and
nothing in the bundle — where photo avatars would mean an image pipeline, CloudKit
assets and sync weight.

Two things to get right: the curated list must be pinned to symbols available at
the deployment target (iOS 17), since a name that doesn't resolve renders as
nothing at all; and the symbol has to stay decorative — the accessibility label
is the member's name, not the glyph.

### 8. Home screen widget

"You owe €120 · green-moon-tea". A WidgetKit extension reading the same store.
Depends on knowing who you are, above. A couple hundred KB for the extension binary.

### 10. Categories

An optional String on `Expense` holding an SF Symbol name, same trick as the avatars above.
Groups the expense list and costs nothing in the bundle.

### 11. Archive a group

Trips end; the list never shrinks. One optional Date and a filtered
`@FetchRequest`.

### 12. Exact amounts in a split

Not another way of dividing a bill — the same division, entered differently.
Percentages ask *in what proportion*; this asks *how much exactly*, because
sometimes the receipt already says.

**The one situation it is for:** one person pays the whole bill, and the bill is
itemised. Three people, one card, 127.00 paid:

| | on the receipt |
|---|---|
| Ania — salad | 23.50 |
| Marek — steak | 68.00 |
| Kuba — pasta | 35.50 |

The numbers are already known. Getting there with percentages means computing
18.5% / 53.5% / 28% first, which is exactly the arithmetic this app exists to
delete. Today the workaround is three separate expenses, each paid by the card
holder and split among one person: it works and it is correct, but it is three
trips through the form and the group then reads "3 expenses" for one dinner.

**Where it does *not* apply:** if everybody paid for their own meal, nothing
needs entering at all. One person covering someone else — Marcin paying for
Kasia because she had no cash — is already an ordinary expense paid by Marcin
and split among Kasia alone. Rounds at the bar are one even-split expense each.
None of that needs this feature; the friction rounds actually had is what
**Duplicate an expense** above fixed.

**Mixed is the real shape of it.** "Ania pays her 23.50, the rest of us split
what's left" means some rows are fixed and the remainder divides between the
others by percentage. So a row is either an amount or a percentage, the fixed
ones come off the top, and what remains is divided among the rest.

That is what makes it the hardest control in the app, and why it stays separate
from the percentage menu rather than sharing a field with it — `50` cannot mean
half a share on one row and fifty złoty on the next. It also breaks the one
invariant everything else here relies on, that the parts reconstruct the whole:
this needs a running remainder on screen at all times, and a decided answer for
what happens when the fixed amounts overshoot the total.

### 13. Spotlight indexing

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
