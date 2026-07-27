# Dutch – Decentralized Bill Splitting for iOS

**Dutch** is a native iOS app built entirely in Swift that allows groups of friends to track shared expenses and automatically calculate who owes whom.

The app runs **without a central server** or user accounts. It leverages Apple's built-in infrastructure (iCloud + CloudKit) for decentralized synchronization, meaning you never have to maintain a backend.

---

## ✨ Key Features

- ✅ **No Accounts Required** – Users don't need to sign up or remember passwords.
- 🔐 **Simple Group Joining** – Each group gets a human-readable random word sequence (e.g., `green-moon-tea`) and a scannable QR code.
- ☁️ **iCloud Synchronization** – Changes are automatically pushed to all members using `NSPersistentCloudKitContainer` and silent push notifications.
- 📊 **Automatic Settlements** – The app calculates balances in real-time and shows exactly who needs to pay whom.
- 📴 **Fully Offline Capable** – All changes are stored locally (Core Data) and sync seamlessly when the device reconnects.
- 📷 **QR Code Scanner** – Built-in camera support to instantly join existing groups.

---

## 🛠 Technology Stack (Pure Apple)

This project uses **zero third-party dependencies** – no CocoaPods, SPM, or Carthage. Everything is built with official Apple frameworks.

| Framework / Tool        | Purpose                                                                 |
| :---------------------- | :---------------------------------------------------------------------- |
| **SwiftUI** / **UIKit** | User interface (choose your preferred paradigm).                        |
| **Core Data**           | Local on-device persistence.                                            |
| **CloudKit**            | Remote storage and sync infrastructure.                                 |
| `NSPersistentCloudKitContainer` | The bridge that automatically mirrors Core Data to CloudKit.        |
| `UICloudSharingController`     | Native system UI for sharing a group with other iCloud users.      |
| `CoreImage`             | Generating QR codes from group identifiers.                             |
| `AVFoundation`          | Scanning QR codes via the device camera.                                |

---

## 🧠 Decentralized Sync Logic (How it works)

Unlike standard client-server apps, **there is no single source of truth** managed by us.

1. **Private Storage** – Every user has their own private CloudKit database container.
2. **Shared Zones** – When User **A** creates a new group, the app creates a dedicated *Custom Zone* inside their private database specifically for that group.
3. **Invitations** – User **A** taps "Share Group", which triggers `UICloudSharingController`. This sends an iCloud invitation (via iMessage, Mail, or a generated link) to User **B**.
4. **Joining** – Once User **B** accepts the invitation, CloudKit grants them read/write access to that specific zone. User **B**'s device downloads a full copy of the group's data.
5. **Continuous Sync** – From that point on, any change (adding an expense, editing a name) made by **A** or **B** is uploaded to CloudKit and pushed to all other participants via background notifications.
6. **Conflict Handling** – If two users edit the same record offline, CloudKit applies a default *"Last Write Wins"* strategy (based on server-side timestamps). You can easily override this with custom logic if needed.

**In short**: The "source of truth" is distributed across the users' iCloud spaces, mediated by Apple's CloudKit infrastructure – giving you a serverless architecture by design.

---

## 📁 Project Structure (Recommended)

```plaintext
Dutch/
├── App/
│   └── Dutch.swift              # Main app entry point
├── Models/
│   ├── CoreData/
│   │   ├── PersistenceController.swift  # NSPersistentCloudKitContainer setup
│   │   └── Dutch.xcdatamodeld      # Data model (Group, Person, Expense)
│   └── DTO/                             # Transient structs for calculations
├── Views/
│   ├── Main/
│   │   ├── GroupListView.swift
│   │   └── GroupDetailView.swift
│   ├── Expenses/
│   │   └── AddExpenseView.swift
│   └── Sharing/
│       ├── QRCodeView.swift             # Display QR and word sequence
│       └── QRScannerView.swift          # Scanner for joining
├── ViewModels/
│   ├── GroupViewModel.swift
│   └── SettlementViewModel.swift        # Business logic for balances
├── Services/
│   ├── CloudKitService.swift            # Wrapper for UICloudSharingController
│   ├── QRCodeGenerator.swift
│   └── WordGenerator.swift              # Generates random mnemonic-like strings
└── Utils/
    └── Extensions/
