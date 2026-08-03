# Trademark and Brand Policy

Dutch's **source code** is open under the [Mozilla Public License 2.0](LICENSE).
Its **name and brand** are not.

This isn't an extra restriction bolted onto the licence — it's how the MPL already
works. Section 2.3 of the licence text says so directly:

> This License does not grant any rights in the trademarks, service marks, or logos
> of any Contributor (except as may be necessary to comply with the notice
> requirements in Section 3.4).

This document simply makes that explicit, so nobody has to guess where the line is.

## What is reserved

The following are **not** covered by the MPL-2.0 grant and remain the property of the
Dutch authors:

- The name **Dutch** *as the name of this app*, and names confusingly similar to it.
  Nothing here claims the ordinary English word, the phrase "going Dutch", or the
  nationality — describing your own app as one that helps people go Dutch is fair and
  needs no permission.
- The Dutch app icon and its source layers — everything in
  `Dutch/Design/AppIcon.icon/`, the renderer `Dutch/Design/RenderIcon.swift`, the
  PNGs in `Dutch/Dutch/Assets.xcassets/AppIcon.appiconset/`, and
  `website/assets/icon.png`.
- The product imagery in `website/assets/` (the App Store screenshots) and the
  `dutch.smigi.net` site design.
- The identifiers `net.smigi.Dutch` and anything derived from it, the App Group
  `group.net.smigi.Dutch`, the iCloud container `iCloud.app.dutch.Dutch`, and the
  in-app purchase product `net.smigi.Dutch.unlimitedgroups`. Apple enforces these as
  globally unique in any case — no one else can register them.

Everything else in this repository is MPL-2.0, as marked in each file's header.

## What you may do

Everything the MPL-2.0 allows, including commercially. To be specific, you may:

- Fork the repository, read it, learn from it and modify it.
- Build and run it for yourself, on your own devices, for free, forever — with no
  group limit, because the limit is a build of the App Store product, not a licence
  term.
- Distribute your own modified version — under **your own name and your own icon**.
- Say truthfully that your work is "based on Dutch" or "a fork of Dutch", so long as
  you don't imply that it *is* Dutch or that the Dutch authors endorse it.
- Use the name in ordinary descriptive ways that need no permission at all: writing
  about the app, reviewing it, linking to it, filing a bug, packaging it for a
  distribution index.

## What to do when you distribute a fork

If you publish a build anywhere — the App Store, TestFlight, a website, a package
manager — please:

1. **Change the display name.** Set `INFOPLIST_KEY_CFBundleDisplayName` in the app
   target's build settings to something of your own.
2. **Change the bundle identifier**, App Group and iCloud container to your own
   reverse-DNS prefix. You will have to do this anyway to sign and ship, and the
   iCloud container is what keeps your users' data separate from ours.
3. **Replace the app icon** with your own artwork — the appiconset PNGs, and the
   `Design/` sources if you keep the renderer.
4. **Use your own in-app purchase product ID**, if you ship one. The identifier in
   `Dutch.storekit` is tied to our App Store Connect record and will not work for you.
5. **Keep the MPL headers** on the files you carried over, and publish your changes
   to those files — that part is the licence, not this policy.

## Asking

If you'd like to use the Dutch name or icon for something not covered above — an
article, a review, a port, a compatible accessory — just ask: `dutch@smigi.net`.
The answer is usually yes.
