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
| 0 | Toolchain and car baseline | Xcode verified; Apple ID and car checks pending |
| 1 | Fork, strip, sign | Code done; waiting on first device signing (Gate G1) |
| 2 | Live connection to the car | Not started |
| 3 | Odometer | Mostly already in upstream — see work order |
| 4–9 | Car render, widget UI, buttons, refresh, daily use | Not started |

## What was removed from BetterBlue, and why

It is signed with a free Apple **Personal Team**, which cannot sign iCloud, push
notifications, or a Watch app, and whose builds expire every 7 days. So this fork
drops the Watch app, Live Activities and their push backend, and CloudKit sync.
Everything is stored locally on the phone.

## Running it on an iPhone

1. Sign in to Xcode with your Apple ID (Xcode › Settings › Accounts).
2. `./scripts/setup-signing.sh` — writes the gitignored `Config/Local.xcconfig`.
3. `open BetterBlue.xcodeproj`, pick the **BetterBlue** scheme and your iPhone, press ▶.

To try it without a real car, add an account with the username
`testaccount@betterblue.com` and password `betterblue`. That is BetterBlue's built-in
Fake Vehicle Mode; it never contacts Hyundai.

## Credentials

This repo is public. Real Bluelink credentials must never be committed.
`Secrets.swift` and `Config/Local.xcconfig` are gitignored; `Config/Secrets.example.swift`
is the template.

## License

MIT. See [LICENSE](LICENSE), which carries both the upstream copyright and this fork's.
