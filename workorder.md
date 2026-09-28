# ENlink — Work Order

**Project:** Custom iOS home screen widget for a 2025 Hyundai Elantra N
**Approach:** Fork of [BetterBlue](https://github.com/schmidtwmark/BetterBlue) (MIT) + [BetterBlueKit](https://github.com/schmidtwmark/BetterBlueKit) (MIT)
**Target platform:** iOS 27 (iOS 17+ APIs), Xcode 27
**Signing:** Free Apple Developer Personal Team, with a decision gate to upgrade to paid
**Status:** Phase 1 complete. Phase 2 ready — waiting on the first real-account session at the car
**Last updated:** 2026-09-28
**Repo:** `git@github.com:mehta-vishad/Nlink.git` (public)

---

## 1. Goal

A `systemMedium` home screen widget, borderless, dark, that shows:

- A pre-rendered 3D view of the car, color-matched to the actual vehicle
- Current odometer reading
- Lock state and fuel level
- Interactive buttons: lock, unlock, climate on/off
- A "last updated" timestamp

Everything runs against Hyundai's private Bluelink endpoints via BetterBlueKit. No public API exists; this rides the same endpoints the MyHyundai app uses.

---

## 2. Inputs still required

These block specific phases. Nothing else is gated on them.

| Input | Needed by | Status |
|---|---|---|
| Exterior paint color of the car | Phase 4 | **Open** |
| Bluelink account email, password, 4-digit PIN | Phase 2 | Held by owner |
| VIN | Phase 2 | Held by owner |
| Mac with Xcode 27 installed | Phase 0 | Confirmed — Xcode 27.0 (27A266a), iOS 27 SDK |
| Decision: pay $99 for Developer Program | Phase 8 | Deferred by design |

---

## 3. Key constraints driving the design

These are not preferences. They are hard limits that shape the architecture, and each one has a phase that deals with it.

1. **Personal Team cannot sign iCloud or Push Notifications.** BetterBlue uses both. They have to come out. (Phase 1)
2. **Personal Team provisioning profiles expire after 7 days.** The app and the widget stop working until rebuilt from Xcode. (Phase 0, Phase 8)
3. **Personal Team is capped at 10 App ID registrations per 7 days.** Every target is a bundle ID. Fewer targets means more headroom to iterate. (Phase 1)
4. **App Groups signing on a Personal Team is unverified.** Reports conflict. There is a fallback path, but it changes how the widget gets its data, so it must be resolved early. (Phase 1, gate G1)
5. **WidgetKit renders a static snapshot.** No SceneKit, no Metal, no live 3D, no continuous animation. The car is a PNG. (Phase 4)
6. **WidgetKit background refresh budget is roughly 40–70 refreshes per day.** Aggressive polling is both impossible and unwise. (Phase 7)
7. **Polling the car drains the 12V battery, and hammering the endpoints risks account suspension.** (Phase 7)
8. ~~**BetterBlueKit does not currently expose odometer.**~~ *Corrected 2026-09-28:* it does, and the app already ignores zero readings. Phase 3 shrinks to verification. (Phase 3)

---

## 4. Phases

### Phase 0 — Environment and baseline

**Objective:** Prove the toolchain and the car both work before writing anything.

**Tasks**

- [x] Confirm Xcode 27 installed, iOS 27 SDK present
- [ ] Sign Apple ID into Xcode → Settings → Accounts, confirm a "(Personal Team)" entry appears
- [ ] Confirm iPhone is on iOS 17 or later and registered as a run destination
- [ ] Enable wireless debugging: Window → Devices and Simulators → select device → Connect via network
- [ ] Confirm the Bluelink **Remote** package subscription is active, not just Guidance
- [ ] Confirm lock, unlock and remote start all work from the official MyHyundai app
- [ ] Record the current dashboard odometer reading (needed as ground truth in Phase 3)

**Testing**

- Build and run Apple's default SwiftUI template on the physical device. This isolates signing problems from project problems. If a blank app will not install, nothing downstream will.

**Exit criteria**

- A trivial app launches on the phone from Xcode over Wi-Fi
- Official app can lock and unlock the car

**Notes**

If the official app cannot control the car, stop. The problem is the subscription or the telematics unit, not the code.

---

### Phase 1 — Fork, strip, and sign

**Objective:** A stripped fork that builds and installs on the device using fake data, with no real credentials anywhere.

**Tasks**

- [x] ~~Fork~~ Cloned `schmidtwmark/BetterBlue` and published it as `mehta-vishad/Nlink`, keeping upstream history so `git merge upstream/main` still works
- [x] Clone with submodules:
      `git clone --recursive https://github.com/YOUR_USER/BetterBlue.git`
- [ ] ~~Point the `BetterBlueKit` submodule at your own fork~~ Not needed: Phase 3 turned out to need no BetterBlueKit patch
- [ ] Run `./scripts/setup-signing.sh` after signing in to Xcode *(corrected: upstream ships `Config/Local.xcconfig.template`; copying `Shared.xcconfig` would have kept upstream's team ID)*
- [ ] `DEVELOPMENT_TEAM`, `BB_BUNDLE_ID_PREFIX` and `BB_APP_GROUP` are written by that script
- [x] Confirm `Config/Local.xcconfig` is gitignored (verified with `git check-ignore`)
- [x] **Delete targets:** `BetterBlueWatch Watch App`, `WatchWidget`, `LiveActivityBackend`, and the Live Activity widget inside `Widget/`
- [x] Remove the `aps-environment` key from all entitlements files
- [x] Remove the iCloud / CloudKit entitlement from all entitlements files
- [x] Convert the SwiftData `ModelContainer` from CloudKit-backed to local-only storage (App Group store, falling back to Application Support)
- [x] Delete `BB_ICLOUD_CONTAINER` usage
- [ ] ~~Run `swiftlint lint`~~ n/a: swiftlint is not installed and upstream removed it from the project. Baseline instead: clean simulator build, zero warnings; BetterBlueKit `swift test` 405/405

**Gate G1 — App Groups probe**

Attempt to build with the existing App Group entitlement intact.

- **If it signs:** keep the shared-container architecture. Container app fetches, widget reads. Set `BB_APP_GROUP` in `Local.xcconfig` and move on.
- **If Xcode refuses:** switch to the fallback. Remove the App Groups entitlement from both targets. Create a gitignored `Secrets.swift` compiled into both the app target and the widget target. The widget performs its own login, fetch and cache inside its own container. Redundant work, acceptable for one user on one phone.

Record which branch was taken. Phases 6 and 7 depend on it.

> **Result (2026-09-28): signs — shared-container branch.** The app installed and ran on the
> iPhone with the App Group entitlement intact (`group.com.mehtavishad.enlink`). On device the
> App Group container exists and the app did *not* create a fallback store in its own
> Application Support, so app and widget share one SwiftData store. No `Secrets.swift` needed.

**Tasks — credential hygiene**

- [x] Add `Secrets.swift` (or equivalent) to `.gitignore` **before the first commit**
- [x] Add a `Secrets.example.swift` template with placeholder values, committed (`Config/Secrets.example.swift`)
- [x] Run `git log -p | grep -i -E 'password|pin|vin'` on your first few commits as a sanity check (only preview fixtures and templates)

**Testing**

| Test | Method | Pass condition |
|---|---|---|
| Signing works with reduced target set | Build and run on device | App installs, launches — **passed 2026-09-28** |
| No push/iCloud entitlement leaks | `codesign -d --entitlements - <app>.app` | Neither key present — **passed**: app and widget carry only `application-groups` |
| Fake Vehicle Mode renders | Enable in-app, open vehicle view | A synthetic vehicle displays with status — **passed on device** (add a car under *Fake Vehicles* first) |
| Widget target installs | Add stock BetterBlue widget to home screen | Widget appears, shows fake vehicle — **passed on device** |
| App ID budget not blown | Count registered identifiers at developer.apple.com | 2 or 3 bundle IDs, not 5+ — **passed**: 2 (`com.mehtavishad.BetterBlue`, `.Widget`) |

**Exit criteria**

- Stripped fork builds, installs, and runs on the phone
- Fake Vehicle Mode works end to end including the widget
- Zero real credentials in the working tree or git history
- Gate G1 resolved and documented

> **Phase 1 complete (2026-09-28).** All exit criteria met and verified on the iPhone.

---

### Phase 2 — Live vehicle connection

**Objective:** Real commands reaching the real car through your own build.

> **Method (added 2026-09-28).** Every HTTP log — already redacted by BetterBlueKit (no
> password, PIN, tokens, GPS, or full VIN) — is also written as JSON lines to
> `Library/Logs/http-*.jsonl` in the App Group container. `./scripts/pull-phone-logs.sh`
> copies those files off the phone into gitignored `.phone-logs/`. That replaces copying
> from Settings → HTTP Logs and the stopwatch: fixtures and latency come from the pulled
> logs. The SwiftData store is never pulled — it holds the password and PIN in plain text.
>
> The Gen5W-vs-CCNC question in the risk note below can be read from `vehicleGeneration`
> in the vehicle-list response, before any climate command is tried.
>
> Hyundai counts wrong PINs ("Invalid PIN, N attempts remaining"). Run the PIN-failure
> test once, not repeatedly — exhausting the attempts locks the PIN until it is reset.

**Tasks**

- [ ] Populate credentials via whichever mechanism Gate G1 selected
- [ ] Configure `APIClientConfiguration(region: .usa, brand: .hyundai, ...)`
- [ ] Verify `client.login()` returns a valid auth token
- [ ] Verify `fetchVehicles(authToken:)` returns the Elantra N with correct VIN
- [ ] Verify `fetchVehicleStatus(for:authToken:)` returns fuel level, gas range, lock state, location
- [ ] Send `VehicleCommand.lock` and confirm the car physically responds
- [ ] Send `VehicleCommand.unlock` and confirm
- [ ] Send `VehicleCommand.startClimate(ClimateOptions(...))` with temperature, defrost, duration and per-seat heat, confirm the car starts
- [ ] Capture the full raw status response from Settings → HTTP Logs and **save it to a fixture file** for Phase 3 and for unit tests

**Testing**

| Test | Method | Pass condition |
|---|---|---|
| Auth success | Correct credentials | Token returned, no error |
| Auth failure | Deliberately wrong password | Clean, typed error; no crash |
| PIN failure | Deliberately wrong PIN | Clean error distinguishable from auth failure |
| Lock round trip | Send lock, observe car | Doors lock; app reflects new state on next fetch |
| Unlock round trip | Send unlock, observe car | Doors unlock |
| Climate with full options | Temperature + defrost + seat heat + duration | Car starts, cabin conditioning matches request |
| Command latency | Stopwatch, 5 runs each | Record median and worst case; these numbers set the widget's pending-state timeout in Phase 6 |
| Car asleep / poor signal | Park in a garage with weak signal, send command | Error surfaces as a timeout, not a hang |
| Token expiry | Idle past token lifetime, then send a command | Silent re-auth, or a clean prompt |

**Exit criteria**

- All six command types verified against the physical car
- A saved fixture of the real status JSON
- Median and worst-case command latency recorded

**Risk**

A 2025 model year should be on the CCNC head unit, which supports the full climate option set. If seat heat or custom duration is rejected by the server, the car is on the older Gen5W generation and the widget's climate preset must fall back to temperature and defrost only. Determine this here, not in Phase 6.

---

### Phase 3 — Odometer support (BetterBlueKit patch)

**Objective:** Get mileage, which the library does not currently provide.

> **Update 2026-09-28 — most of this phase already exists upstream.**
> `Vehicle.odometer` and `VehicleStatus.odometer` exist, and `HyundaiUSAAPIClient+Parsing.swift`
> parses it. For Hyundai USA the value comes from the **vehicle list** endpoint, not the status
> endpoint, so it only refreshes when the vehicle list is re-fetched (at most every 2 hours,
> `BBAccount.vehicleListMaxAge`). The zero-reading guard is already in `BBAccount.updateVehicles()`:
> a reading of 0 never overwrites the stored value.
> What remains: the ground-truth check against the dashboard, and fixture-backed decoder tests.
> The tasks below are kept for reference; most are already satisfied.

BetterBlueKit's status model covers battery, EV range, fuel level, gas range, location, climate state, lock state and charging state. Odometer is absent. The underlying US endpoint does return it; other clients built on the same API parse it out of the status response.

**Tasks**

- [ ] Open the Phase 2 fixture and locate the odometer block in the raw JSON
- [ ] Add an `Odometer` value type to BetterBlueKit (value + unit, mirroring the existing `Distance`/`Temperature` pattern rather than inventing a new one)
- [ ] Add an optional `odometer` field to the vehicle status model
- [ ] Parse it in `HyundaiAPIClientUSA`
- [ ] **Handle the zero-reading bug.** Other clients on this API had to add explicit handling because the endpoint intermittently returns an odometer of 0. Treat 0 as "no reading" and keep the last known good value rather than displaying 0 miles.
- [ ] Add the field to the fake API client so Fake Vehicle Mode exercises it
- [ ] Open an upstream PR against `schmidtwmark/BetterBlueKit`

**Testing**

| Test | Method | Pass condition |
|---|---|---|
| Decode from fixture | Unit test against the saved Phase 2 JSON | Odometer parses with correct value and unit |
| Zero-reading guard | Unit test with a hand-edited fixture where odometer is 0 | Returns nil or last-known, never 0 |
| Missing field | Unit test with the odometer block deleted | Decodes cleanly as nil, no throw |
| Unit conversion | Unit test, km payload | Converts correctly if the API ever reports metric |
| Ground truth | Compare live reading to the dashboard number recorded in Phase 0 | Within normal drift (the API reading lags the dash) |
| Regression | `swift test` on BetterBlueKit | Existing suite still green |

**Exit criteria**

- Odometer available on the status model, covered by tests
- Live value matches the dashboard
- Upstream PR opened

---

### Phase 4 — Car asset pipeline

**Objective:** A transparent PNG of the car, color-matched, that looks right on near-black.

**Blocked on:** paint color.

**Tasks**

- [ ] Choose a source:
      **(a)** 3D model from Sketchfab or CGTrader, paint shader set to match, rendered in Blender. More work, full control over lighting, which matters a lot against a dark background.
      **(b)** Hyundai's configurator renders. Fast, but lit for a white background and will likely look pasted-on.
- [ ] Render a 3/4 front view, transparent background
- [ ] Export at 3x for the intended widget slot, plus 2x
- [ ] Optionally render a second variant for the unlocked state (interior lights on, indicators lit)
- [ ] Compress aggressively. Widget extensions run under a tight memory ceiling, on the order of tens of megabytes, and a large PNG decoded into a widget snapshot is a real way to get the extension killed.
- [ ] Add to the asset catalog in the **widget target**, not the app target

**Testing**

| Test | Method | Pass condition |
|---|---|---|
| Color accuracy | Side-by-side with a photo of the actual car in daylight | Visually matching |
| Contrast on dark | Place on the intended near-black background | Body panels read as distinct from background; no silhouette effect |
| Edge quality | Zoom to 400% | Clean alpha, no white fringing from a white-background render |
| Tinted rendering | Preview under `widgetRenderingMode == .accented` | Still legible as a car |
| Memory | Run widget on device, watch for extension termination | Widget renders repeatedly without being killed |
| Retina sharpness | Physical device, not simulator | No visible softness at 3x |

**Exit criteria**

- Final PNG set in the widget's asset catalog
- Survives all four rendering modes
- No extension memory terminations

---

### Phase 5 — Widget UI

**Objective:** The visual design. Static data at this stage; buttons come next.

**Tasks**

- [ ] New SwiftUI view in `Widget/`, replacing the stock BetterBlue widget view
- [ ] Define a small token set: background, primary text, secondary text, accent, state colors for locked/unlocked
- [ ] Apply `.containerBackground` with your own near-black fill. iOS 17+ requires a container background; "borderless" means supplying your own rather than omitting it.
- [ ] `systemMedium` layout: car render, odometer, fuel, lock state, timestamp, three control slots
- [ ] Handle `widgetRenderingMode` explicitly for `.accented` and `.vibrant`, or the design will be flattened by the system on certain home screen settings
- [ ] Design the empty, loading, stale and error states now, not as an afterthought
- [ ] Build Xcode Previews for every state

**Testing**

| Test | Method | Pass condition |
|---|---|---|
| All rendering modes | Previews + device, `.fullColor` / `.accented` / `.vibrant` | Legible and intentional in each |
| Light and dark system appearance | Toggle system setting | Design holds (it is a dark widget either way, but verify no system-injected contrast) |
| Dynamic Type | Largest accessibility sizes | No truncation of the odometer or clipping of controls |
| Stale data state | Force a timestamp 6 hours old | Clearly communicates staleness |
| Error state | Force an error | Readable, not a blank widget |
| Long values | 6-digit odometer, 3-digit range | No layout break |
| Physical placement | Real home screen, real wallpaper | Reads as borderless; no unintended chrome |

**Exit criteria**

- Widget renders on the home screen with real data from Phase 2 and 3
- Every state has a designed appearance
- Holds up in all four rendering modes

---

### Phase 6 — Interactivity

**Objective:** Working lock, unlock and climate buttons in the widget itself.

Interactive widgets use `Button` with an `AppIntent`, available since iOS 17.

**Tasks**

- [ ] `LockIntent`, `UnlockIntent`, `ClimateToggleIntent`, `RefreshIntent`
- [ ] Wire each to the corresponding `VehicleCommand`
- [ ] Implement optimistic pending state: the button shows in-flight immediately, since the car takes seconds to respond
- [ ] Set the pending-state timeout from the worst-case latency measured in Phase 2
- [ ] Decide the climate preset (temperature, duration, defrost, seat heat) and hard-code it, or expose it via widget configuration
- [ ] Handle the case where a second tap arrives while a command is in flight
- [ ] Surface failures inside the widget without requiring the app to be opened

**Testing**

| Test | Method | Pass condition |
|---|---|---|
| Lock button | Tap from home screen | Car locks; widget reflects it |
| Unlock button | Tap from home screen | Car unlocks |
| Climate button | Tap from home screen | Car starts conditioning with the chosen preset |
| Pending state | Tap and watch | In-flight indicator appears immediately, clears on completion |
| Timeout | Tap with car out of signal | Pending clears into a failure state; does not hang forever |
| Double tap | Tap twice quickly | Second tap ignored or queued, never two commands |
| Offline phone | Airplane mode, tap | Immediate, clear failure |
| Auth expired | Idle past token lifetime, tap | Silent re-auth and command succeeds, or a clean error |
| Wrong PIN | Temporarily set a bad PIN | Clear, specific error |
| Cold start | Reboot phone, tap widget immediately | Works; extension cold-starts without error |

**Exit criteria**

- All three commands work from the home screen without opening the app
- No path where the widget hangs in a pending state indefinitely
- Every failure mode produces a readable message

---

### Phase 7 — Refresh strategy and battery safety

**Objective:** Stay useful without draining the 12V or tripping rate limits.

**Tasks**

- [ ] Implement the `TimelineProvider` around cached status plus an explicit relative timestamp
- [ ] Target well under the WidgetKit budget of roughly 40–70 refreshes per day
- [ ] Prefer cached server-side status over commands that wake the telematics unit
- [ ] Add a client-side rate limiter with a minimum interval between car-waking calls
- [ ] Add a backoff on repeated failures so a broken token does not retry in a loop
- [ ] Decide refresh cadence: infrequent scheduled refresh plus on-demand refresh via the tap intent

**Testing**

| Test | Method | Pass condition |
|---|---|---|
| Refresh count | Instrument timeline requests, run 24h | Comfortably under budget |
| Rate limiter | Tap refresh repeatedly | Calls throttled, not passed through |
| Failure backoff | Invalidate the token, observe | Exponential backoff, no retry storm |
| 12V health | Leave car parked 72h with the widget installed; check battery voltage before and after | No measurable abnormal drain |
| Account health | Run a full week of normal use | No suspension, no lockout |
| Stale display | Let a refresh window lapse | Timestamp updates honestly; no silently stale numbers presented as fresh |

**Exit criteria**

- A 7-day run with no rate limiting, no account issues, no unusual battery drain
- Refresh count measured and documented

---

### Phase 8 — Daily driving and the $99 decision

**Objective:** Live with it for two weeks and decide whether to go paid.

**Tasks**

- [ ] Add an app icon
- [ ] Establish the weekly re-sign ritual over wireless debugging
- [ ] Optional: lock screen widget variant
- [ ] Optional: Control Center widget (iOS 18+)
- [ ] Log every annoyance encountered during the two weeks

**Testing**

- Day 8: confirm the widget stops working as expected when the profile expires. This is a pass, not a bug. Verify the re-sign restores it in under a minute.
- Two-week usability log: does it actually replace opening the MyHyundai app?

**Decision gate G2**

Go paid if: the weekly expiry is genuinely irritating, or you want Live Activities back, or you want it on a Watch, or you want to hand it to anyone else.

---

### Phase 9 — Paid account migration (conditional)

**Objective:** Undo the Phase 1 amputations once the entitlements are available.

**Tasks**

- [ ] Enroll, accept all pending license agreements. A new paid account often reports capabilities as undetermined until the agreements are signed; this is the most common post-upgrade confusion.
- [ ] Re-enable App Groups properly if Gate G1 took the fallback branch
- [ ] Move credentials into Keychain with a proper access group
- [ ] Optionally restore CloudKit sync
- [ ] Optionally restore Live Activities and the push backend
- [ ] Optionally rebuild the Watch app and complication
- [ ] Self-distribute through TestFlight to end the 7-day cycle

**Testing**

- Full regression of Phases 5 through 7 after the entitlement changes. Signing changes break widgets in non-obvious ways.

---

## 5. Consolidated test strategy

### 5.1 Automated

- **Unit tests in BetterBlueKit.** Decoder tests against saved fixture JSON captured from the real car. This is the highest-value automated testing in the project, because the API is undocumented and can change without notice. A fixture-backed decoder test is your early warning system.
- **Fixtures to maintain:** normal status, zero-odometer status, missing-odometer status, locked, unlocked, climate running, low fuel.
- **Run `swift test` and `swiftlint lint` before every commit.**

### 5.2 Fake Vehicle Mode

BetterBlue ships a fake API client and custom test scenarios. Use it for everything that does not strictly require the real car:

- All widget layout states
- All error states
- Dynamic Type and rendering mode testing
- Anything you would otherwise have to walk out to the driveway to verify

This matters practically: every real-car test costs a command against a rate-limited API and a small draw on the 12V. Fake mode costs nothing.

### 5.3 Xcode Previews

One preview per widget state, per size, per rendering mode. Previews are where the visual work gets done; the device is where it gets confirmed.

### 5.4 Manual device testing

The simulator does not enforce code signing and does not reproduce widget memory limits or rendering modes faithfully. Every phase's exit criteria must be verified on the physical phone.

### 5.5 Failure-mode matrix

Every one of these should produce a specific, readable widget state. None should produce a blank widget, a hang, or a crash.

| Condition | Expected widget behavior |
|---|---|
| No phone network | Cached data + clear offline indicator |
| Car out of cell coverage | Cached data + command failure message |
| Auth token expired | Silent re-auth; failure only if re-auth fails |
| Password changed | Clear "sign in again" state |
| Wrong PIN | Specific PIN error, distinct from auth error |
| Rate limited by Hyundai | Backoff state, no retry storm |
| Bluelink subscription lapsed | Clear message naming the subscription |
| Odometer returns 0 | Last known good value, never "0 mi" |
| Provisioning profile expired | Widget goes blank (system behavior, expected) |
| Command times out | Pending state clears into failure within the Phase 2 worst-case + margin |
| Widget extension OOM | Should not occur; if it does, revisit Phase 4 asset size |

### 5.6 Regression checklist (run after every weekly re-sign)

1. Widget appears on home screen with current data
2. Lock button works
3. Unlock button works
4. Climate button works
5. Odometer matches expectation
6. Timestamp is current

Six checks, under two minutes. Catches signing regressions and upstream API breakage early.

---

## 6. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Hyundai changes the private API | Medium over time | High | Fixture-backed decoder tests; stay synced with upstream BetterBlueKit, which is actively maintained |
| App Groups will not sign on Personal Team | Unknown | Medium | Gate G1 fallback defined; resolved in Phase 1, not discovered in Phase 6 |
| Car is Gen5W, not CCNC | Low for a 2025 | Medium | Detected in Phase 2; climate preset degrades to temperature + defrost |
| Credentials committed to a public fork | Low | **Severe** | Gitignore before first commit; grep git history in Phase 1 |
| Account suspended for excessive API calls | Low | High | Rate limiter and backoff in Phase 7; soak test before daily use |
| 12V drain from polling | Low | Medium | Cached-first refresh strategy; 72h parked test in Phase 7 |
| Widget extension memory kill from large PNG | Medium | Low | Compress in Phase 4; test on device |
| Weekly re-sign friction kills the project | Medium | Medium | Wireless debugging; Gate G2 exists precisely for this |

---

## 7. Reference

**Repos**
- App: `https://github.com/schmidtwmark/BetterBlue` (MIT)
- API layer: `https://github.com/schmidtwmark/BetterBlueKit` (MIT)

**Key paths in the fork**
```
BetterBlue/
├── BetterBlue/          # main app — Views, Models, Utility
├── Widget/              # widget target — this is where the work happens
├── BetterBlueKit/       # submodule — patched in Phase 3
├── Config/
│   ├── Shared.xcconfig  # committed defaults
│   └── Local.xcconfig   # gitignored — your team, bundle prefix, app group
└── Troubleshooting.md   # upstream's own debugging notes
```

**Targets to delete in Phase 1**
`BetterBlueWatch Watch App`, `WatchWidget`, `LiveActivityBackend`, Live Activity widget

**Useful in-app tooling**
Settings → HTTP Logs (raw request/response capture)
Fake Vehicle Mode with custom scenarios

**Upstream acknowledgement**
BetterBlue and BetterBlueKit are MIT licensed work by Mark Schmidt. The odometer patch in Phase 3 should go back upstream.
