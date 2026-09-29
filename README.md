# ENlink

A custom home screen widget for a 2025 Hyundai Elantra N: the car, its odometer,
lock state and fuel level, with lock / unlock / climate buttons — on a dark,
borderless `systemMedium` widget.

ENlink is a personal fork of **[BetterBlue](https://github.com/schmidtwmark/BetterBlue)**
and **[BetterBlueKit](https://github.com/schmidtwmark/BetterBlueKit)** by Mark Schmidt
(MIT). All of the Bluelink API work is theirs. If you want a polished app for your own
Hyundai or Kia, use BetterBlue, not this.

## Status

Built phase by phase from [`workorder.md`](workorder.md), which is the plan of record.

| Phase | What | State |
|---|---|---|
| 0 | Toolchain and car baseline | Done |
| 1 | Fork, strip, sign | Done — runs on the iPhone; App Groups sign on a Personal Team |
| 2 | Live connection to the car | Signed in, status verified; commands not yet run |
| 3 | Odometer | API matches the dashboard (11,071 mi) |
| 4 | Car image | Done — Performance Blue, background removed with Vision |
| 5 | Widget UI | First version: dark glass card, SF Pro, Liquid Glass on Clear home screens |
| 6–9 | Buttons, refresh, daily use, paid account | Buttons already work; the rest not started |

## What was removed from BetterBlue, and why

It is signed with a free Apple **Personal Team**, which cannot sign iCloud, push
notifications, or a Watch app, and whose builds expire every 7 days. So this fork
drops the Watch app, Live Activities and their push backend, and CloudKit sync.
Everything is stored locally on the phone.

## Running it on an iPhone

1. Sign in to Xcode with your Apple ID (Xcode › Settings › Accounts).
2. `./scripts/setup-signing.sh` — writes the gitignored `Config/Local.xcconfig`.
3. `open BetterBlue.xcodeproj`, pick the **BetterBlue** scheme and your iPhone, press ▶.

Optionally drop your own image into `Widget/Assets.xcassets/ElantraNLocal.imageset` (git-ignored)
and the widget uses it instead of the bundled photo — for example a picture of your own car run
through `scripts/cutout-car.swift` and `scripts/make-car-asset.swift`.

To try it without a real car, add an account with the username
`testaccount@betterblue.com` and password `betterblue`. That is BetterBlue's built-in
Fake Vehicle Mode; it never contacts Hyundai.

## Credentials

This repo is public. Real Bluelink credentials must never be committed.
`Secrets.swift` and `Config/Local.xcconfig` are gitignored; `Config/Secrets.example.swift`
is the template.

## Credits

- App and API layer: [BetterBlue](https://github.com/schmidtwmark/BetterBlue) and
  [BetterBlueKit](https://github.com/schmidtwmark/BetterBlueKit) by Mark Schmidt (MIT).
- Car image: [2025 Hyundai Elantra N, front left, 03-29-2026](https://commons.wikimedia.org/wiki/File:2025_Hyundai_Elantra_N,_front_left,_03-29-2026.jpg)
  by **MercurySable99**, licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/),
  via Wikimedia Commons. Changes: background removed with Apple Vision, highlights and
  reflections toned down, cropped, resized (`scripts/cutout-car.swift`,
  `scripts/neutralize-car.swift`, `scripts/make-car-asset.swift`). The adapted image in
  `Widget/Assets.xcassets/ElantraN.imageset` is shared under the same CC BY-SA 4.0 license.

## License

Code: MIT. See [LICENSE](LICENSE), which carries both the upstream copyright and this fork's.
The car image is CC BY-SA 4.0 (see Credits).
