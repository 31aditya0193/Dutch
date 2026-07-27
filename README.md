# Dutch – Decentralized Bill Splitting for iOS

**Dutch** is a native iOS app built entirely in Swift that lets groups of friends track shared expenses and automatically work out who owes whom.

The app runs **without a central server** and without user accounts. It leans on Apple's own infrastructure (iCloud + CloudKit) for synchronization, so there is no backend to maintain.

---

## ✨ Key Features

- ✅ **No Accounts Required** – no sign-up, no passwords.
- 🔐 **Simple Group Joining** – every group gets a human-readable word sequence (e.g. `green-moon-tea`) and a scannable QR code.
- ☁️ **iCloud Synchronization** – changes propagate to all members via `NSPersistentCloudKitContainer` and silent push notifications.
- 📊 **Automatic Settlements** – balances are recomputed live, and the app shows a short set of payments that squares everyone up.
- ✅ **Settling Up** – mark a suggested payment as made and it is logged; the debt clears and the total spent is left alone, because paying someone back buys nothing.
- ⚖️ **Uneven Splits** – set what anyone pays as a percentage of a full share: 49% for a fare with 51% off, 50% each for a couple sharing one hotel room. Every split still reconciles to the cent.
- ✏️ **Editable Expenses** – correct an expense in place instead of deleting and re-entering it, so the other members see a modification rather than a disappearance.
- 🌍 **Foreign Currencies** – enter what you actually handed over abroad; it is converted once, at the rate you saw, and stored in the group's currency so nobody's balance drifts as rates move.
- 🙋 **Second Person** – tell the app which member you are and it says "you owe" instead of naming you in the third person. Kept on the device, never synced.
- 💰 **Exact to the Cent** – money is held as integer cents, so a three-way split never loses a penny to floating point.
- 📴 **Fully Offline Capable** – everything is written to Core Data locally and syncs when the device reconnects.
- 📷 **QR Code Scanner** – built-in camera support for joining an existing group.

Where the app is going next, and what it deliberately won't do, is in [ROADMAP.md](ROADMAP.md).

---

## 🛠 Technology Stack (Pure Apple)

This project has **zero external dependencies** – no CocoaPods, no Carthage, and no remote Swift packages. Everything is built on official Apple frameworks.

| Framework / Tool                | Purpose                                                        |
| :------------------------------ | :------------------------------------------------------------- |
| **SwiftUI**                     | The entire user interface.                                      |
| **UIKit**                       | Bridged in only where SwiftUI has no equivalent (share sheet, camera). |
| **Core Data**                   | Local on-device persistence.                                    |
| **CloudKit**                    | Remote storage and sync infrastructure.                         |
| `NSPersistentCloudKitContainer` | The bridge that mirrors Core Data into CloudKit.                |
| `UICloudSharingController`      | System UI for sharing a group with other iCloud users.          |
| `CoreImage`                     | Generating QR codes from share URLs.                            |
| `AVFoundation`                  | Scanning QR codes with the device camera.                       |
| **Swift Testing**               | Unit tests (`@Test` / `@Suite`); UI tests use XCTest.           |

There is one Swift package in the repo — **DutchKit** — but it is *local*, living inside this repository rather than being fetched from anywhere. See [Two Modules](#-two-modules) below.

---

## 🧩 Two Modules

The code is split in two, along a single line: **does it need Apple's frameworks to work?**

### `DutchKit` — the rules of the money

A local Swift package with no UI, no persistence, and no CloudKit. Just Foundation.

| File                       | Responsibility                                                                                    |
| :------------------------- | :------------------------------------------------------------------------------------------------ |
| `Money.swift`              | A monetary amount as whole cents (`Int`), with even and weighted splits that always reconcile back to the total. |
| `SettlementCalculator.swift` | Balances per person, how one expense divides between its sharers, and the transfers that settle a group in at most *n − 1* payments. |
| `ForeignAmount.swift`      | An amount as it was paid abroad, plus the rate it was captured at — converted once, never re-read. |
| `WordGenerator.swift`      | Human-readable sequences such as `coral-lotus-pearl`.                                              |

Because it touches nothing platform-specific, its tests run from the command line in milliseconds — no simulator, no iCloud account. That is also why the package declares a macOS platform it never actually ships to.

> **Note on word sequences:** they are *labels, not credentials*. Access to a group is granted solely by the CloudKit share the QR code carries. A matching word sequence is never treated as proof of membership.

### `Dutch` — everything that touches Apple

The app target: SwiftUI views, the Core Data stack, CloudKit sharing, the QR scanner.

The two meet in exactly one file, `Models/DTO/SettlementBridge.swift`, which maps Core Data objects (`ExpenseGroup`, `Person`, `Expense`) onto DutchKit's value types (`Participant`, `ExpenseEntry`) and calls the calculator. Keeping the conversion in one place means the settlement maths never learns that Core Data exists.

---

## 🧠 Decentralized Sync Logic (How it works)

Unlike a standard client–server app, **there is no single source of truth** owned by us.

1. **Private storage** – every user has their own private CloudKit database.
2. **Shared zones** – when user **A** creates a group, the app creates a dedicated custom zone in their private database for it.
3. **Invitations** – **A** taps "Share Group", which presents `UICloudSharingController` and sends an iCloud invitation (iMessage, Mail, or a link). The same URL is also rendered as a QR code.
4. **Joining** – once **B** accepts, CloudKit grants them read/write access to that zone and their device downloads the group's data.
5. **Continuous sync** – from then on, every change by **A** or **B** is uploaded and pushed to the other participants via background notifications.
6. **Conflict handling** – concurrent offline edits are resolved per-property, favouring the incoming change (`NSMergeByPropertyObjectTrumpMergePolicy`).

**In short:** the source of truth is distributed across the users' own iCloud spaces, mediated by CloudKit — serverless by design.

### Why there are two persistent stores

`PersistenceController` loads **two** stores against the same model, and both are required:

- the **private** store mirrors to the user's own CloudKit database and holds groups they created;
- the **shared** store receives groups other people have shared *with* them.

With only the private store, accepting an invitation appears to succeed but the group never appears — Core Data has nowhere to put it.

---

## 📁 Project Structure

```plaintext
Dutch/                              # repository root
└── Dutch/                          # ← open Dutch.xcworkspace from here
    ├── Dutch.xcworkspace           # the workspace (app + package)
    ├── Dutch.xcodeproj
    ├── Dutch/                      # app target
    │   ├── App/
    │   │   └── DutchApp.swift              # @main, plus the scene delegate that accepts shares
    │   ├── Models/
    │   │   ├── CoreData/
    │   │   │   ├── PersistenceController.swift  # private + shared CloudKit stores
    │   │   │   └── Dutch.xcdatamodeld           # ExpenseGroup, Person, Expense (v3)
    │   │   └── DTO/
    │   │       └── SettlementBridge.swift       # Core Data ↔ DutchKit
    │   ├── Views/
    │   │   ├── Main/                       # ContentView, GroupListView, GroupDetailView
    │   │   ├── Expenses/                   # ExpenseFormView (adds and edits)
    │   │   └── Sharing/                    # ShareGroupView, JoinGroupView,
    │   │                                   # QRScannerView, CloudSharingSheet
    │   ├── Services/
    │   │   ├── CloudSharingService.swift   # creating and accepting CKShares
    │   │   ├── GroupStore.swift            # all write operations
    │   │   ├── ExpenseDefaults.swift       # per-group state local to this device
    │   │   └── QRCodeGenerator.swift
    │   └── Utils/Extensions/
    ├── DutchKit/                   # local Swift package (pure logic)
    │   ├── Sources/DutchKit/
    │   └── Tests/DutchKitTests/
    ├── DutchTests/                 # Core Data + bridge tests (Swift Testing)
    └── DutchUITests/               # end-to-end flows (XCTest)
```

There are deliberately **no view models**. Reads go through `@FetchRequest` so that changes synced down from CloudKit reach the UI on their own; writes are funnelled through `GroupStore`.

---

## 🚀 Building & Testing

Requires **Xcode 26 or newer** and an iOS 17+ target. All commands run from the inner `Dutch/` directory.

Build the app:

```bash
xcodebuild -workspace Dutch.xcworkspace -scheme Dutch -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Run the pure logic tests — fast, and no simulator needed:

```bash
swift test --package-path DutchKit
```

Run the full suite, including Core Data and UI tests:

```bash
xcodebuild -workspace Dutch.xcworkspace -scheme Dutch -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Sync itself cannot be tested in the simulator alone: it needs two devices signed in to **different** iCloud accounts, and a paid developer account for the CloudKit container and push entitlements. The tests run against an in-memory store with mirroring switched off, so they exercise the data model and the settlement maths rather than CloudKit.

---

## 📄 License

See [LICENSE](LICENSE).
