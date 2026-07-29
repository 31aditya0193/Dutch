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

**Raising the deployment target is not a size lever.** Measured 2026-07-29 by
archiving twice against SDK 27.0, `minos` verified with `vtool`: iOS 17 gives a
2128 KB bundle, iOS 26 gives 2112 KB, and `Assets.car` is byte-identical at
1076 KB. Sixteen kilobytes, all of it back-deployment thunks in `__text`. Nor is
it a speed lever — SwiftUI and Core Data ship with the OS and run the same code
either way — and Liquid Glass is already active regardless, because adoption
keys off the *linked SDK* rather than `minos`. Raise the floor only to reach a
named API, and say which: today the only two that would matter are
`IndexedEntity` (18.0) and `FoundationModels` (26.0).

---

## Shipped

**The base:**

- Groups, members, expenses, equal splits
- Settlement (balances + a short list of payments that clears them)
- iCloud sync and group sharing by QR code
- Expenses entered in a foreign currency, converted once at entry

**Added since:** the eight below. The first four were built together because two
of them shared a single Core Data version bump and doing that migration twice
would have been worse than doing it once; only the group's symbol and colour
have needed a model change since. The reasoning is kept here because each one
had a non-obvious decision behind it.

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

### App Intents and Shortcuts

Every one of the five seconds this app exists to save was being spent inside it:
unlock, find the icon, tap the group, tap Add Expense. Three actions now reach
past all of that — from Siri, the Action button, Spotlight, the Shortcuts app,
and a long press on the icon.

**New Expense** opens the form on a group. **Add Expense** records one without
launching at all. **Check Balance** answers the only question anybody opens a
bill-splitting app to ask. All three default to the group you last opened, which
is what makes them worth having: "add an expense", said mid-trip, means *this*
trip, and having to name the group every time turns a five-second entry into a
conversation. With exactly one group on the phone it doesn't even need that.

Two decisions carried real weight.

**Who paid is the device's identity**, not a parameter. A payer picker that
could not be narrowed to the members of the chosen group would offer everybody
from every group, and recording an expense against someone who isn't in it is a
wrong balance that nothing on screen would flag. Asking the user to say who they
are once is the cheaper mistake. Without an identity the intent refuses and
names the gesture that fixes it.

*Correction, checked against the iOS 27 SDK on 2026-07-29:* this was written
here as "iOS 17 has no `@IntentParameterDependency`", which is wrong — it is
annotated `@available(iOS 17.0)`, and only its `Hashable` conformance is 18.0.
So the narrowed picker may in fact be reachable at the current floor. Nobody has
tried it; the identity decision stands on its own merits either way, but the
stated blocker was not real.

**Amounts are in the group's own currency.** A foreign receipt needs a rate,
rates are frozen at entry on purpose, and there is no way to ask "at what rate?"
in a voice flow without guessing — which is precisely the failure that decision
exists to prevent. Foreign receipts go through the form, and so do uneven splits.

`AddExpenseIntent` gets no confirmation step, deliberately: confirming would
spend the time this exists to save. Instead the reply states the figure and the
group it landed in, phrased through the same `Standing` type the screens use, so
a mishearing is audible immediately — and a wrong entry is one swipe to delete.

The word sequence became useful here for the first time since it was printed
next to the QR code: `EntityStringQuery` resolves "green moon tea" as readily as
"Berlin Trip". It still grants nothing — it searches groups the device already
has, and access comes only from the CloudKit share.

**The stores moved into an app group** as part of this, along with
`ExpenseDefaults`. Nothing here needed it; the widget below does, and a widget
is a separate process that cannot open the app's own container. Doing it once
the app has users would mean abandoning every local store, so it was done while
that costs nothing.

*Cost: a few KB of intent definitions. `AppIntents` ships with the OS. No model
change; `GroupStore.addExpense` already took every field this needed.*

### Spotlight indexing

The App Intents above put three *actions* in Spotlight; they left the groups
themselves unfindable. Typing "Berlin" on the home screen now lands in the trip.

**Groups only, not expenses.** An expense has nowhere of its own to open — there
is no expense screen, so every hit could only land on its group anyway — and
titles like "Dinner" or "Taxi" repeat across every trip anybody has ever taken,
which turns one useful result into forty indistinguishable ones. Groups are few,
individually named, and each one is already a destination.

**The whole set is rewritten on every change rather than diffed.** That sounds
wasteful and isn't: a device holds a handful of groups. The alternative is
remembering which identifiers were written last time in order to know which to
delete, which is bookkeeping living outside Core Data that would drift from it
the first time a save failed halfway. Clearing by domain identifier means the
index cannot hold a group that no longer exists, whatever happened.

Reindexing is triggered by **both** `NSManagedObjectContextDidSave` and
`NSPersistentStoreRemoteChange`, because neither is a superset of the other: a
group created here never produces a remote change, and one deleted on another
device never produces a save here. Watching only saves would be the same mistake
`@FetchRequest` exists to prevent — the index would quietly stop tracking
anything that arrived over CloudKit. A sync arrives as a run of notifications
rather than one, so they coalesce over 500 ms.

Two things that would have failed silently: items **expire after a month** by
default, so a trip nobody opened would fall out of Spotlight — which is exactly
the group somebody would go looking for this way; and indexing is skipped under
`-uitesting-reset`, since test fixtures reaching the device's real index would
outlive the run that created them.

The word sequence is indexed whole and never split. "green" would otherwise
match every trip that happened to draw that word. It remains a label and not a
credential — searching finds only groups the device already has.

*Cost: zero bytes. `CoreSpotlight` ships with the OS. No model change.*

---

## Next

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

The awkward part is already done: both the Core Data stores and `ExpenseDefaults`
live in `group.net.smigi.Dutch`, so the extension can open them. That was the one
piece of this that would have been expensive to retrofit — moving a store after
people have data in it abandons whatever hadn't synced.

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
