# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LiftLog is a SwiftUI + SwiftData workout-tracking app for iOS with a companion watchOS app. Two Xcode targets in one project (`LiftLog.xcodeproj`):

- **LiftLog** — the iOS app. Owns all persistence (SwiftData) and business logic.
- **LiftLogWatchApp Watch App** — a remote control with no store of the workouts themselves; it mirrors state pushed from the phone over WatchConnectivity and sends commands back. The one thing it does persist is its outgoing command queue, so sets logged (and workouts started) with the phone out of range aren't lost.

UI strings are in Russian.

## Commands

Build the iOS app for the simulator:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project LiftLog.xcodeproj -scheme LiftLog -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
```

Building the `LiftLog` scheme (it embeds the watch app as a dependency) against a
*generic* destination — `-destination 'generic/platform=iOS Simulator'`, or Xcode's "Any
iOS Simulator Device"/"Any iOS Device" placeholders in the destination picker — fails the
whole build with a bogus `WCSessionDelegate` conformance error on `PhoneSessionManager`,
because the embedded watch target gets compiled under the iOS SDK instead of watchOS. Use
a concrete, named simulator or device instead, as above — `Scripts/test.sh` already does
this (`platform=iOS Simulator,name=$DEVICE`). This also bites a real device run in Xcode:
if the destination picker falls back to "Any iOS Device" (e.g. the paired
device/watch dropped its connection), the build fails the same way and nothing installs.

To build/run the watch target on its own, use the `LiftLogWatchApp Watch App` scheme with
a watchOS simulator destination instead.

Run tests:

```bash
Scripts/test.sh                      # Unit plan — run after any change to logic
Scripts/test.sh All                  # Unit + UI plan — after touching a user flow, and before calling a task done
Scripts/check-watch-sync-parity.sh   # after any edit to WorkoutSyncModels.swift
```

`test.sh` runs `xcodebuild -quiet`, and an empty test bundle also exits 0 — so always read
the outcome rather than trusting the exit code:

```bash
xcrun xcresulttool get test-results summary --path build/TestResults.xcresult
```

Check `result`, `passedTests`, `failedTests`, and `testFailures` on failure.

## Testing

**Before writing or changing tests — and before finishing any change to models, watch sync,
or user flows — invoke the `create-tests` skill.** It carries the decision table for when a
test is required, which target it belongs in, the helper APIs to build data with, the seams
to introduce for untestable system singletons, and the checklist to run before handing work
back.

Test setup in the repo:

- **`LiftLogTests`** — Swift Testing (`@Suite`/`@Test`/`#expect`), hosted by `LiftLog.app`
  (`TEST_HOST`), so `Bundle.main` still carries `exercises.json` and `ExerciseCatalog` works.
- **`LiftLogUITests`** — XCUITest.
- Both run from test plans `TestPlans/Unit.xctestplan` (default) and `TestPlans/All.xctestplan`,
  wired into the **shared** scheme `LiftLog` (`xcshareddata/xcschemes`, not `xcuserdata`).
  Both plans force `ru`/`RU` and collect coverage on the app target.
- Helpers, not tests: `LiftLogTests/Support/` — `TestStore` (fresh in-memory `ModelContainer`
  per test), `Fixtures` (model builders that go through production paths, deterministic dates
  from `Fixtures.epoch`), `WatchSyncFixtures` (wire-format DTOs and the exact `[String: Any]`
  messages the watch sends, plus `SourcePaths` for the two-copy parity check).
  `LiftLogUITests/Support/AppLauncher.swift` launches the app with `-uiTestInMemoryStore`,
  which `LiftLogApp` honors in DEBUG to start UI tests from an empty store.
- Both test targets use file-system-synchronized groups: a new file in `LiftLogTests/` or
  `LiftLogUITests/` is picked up automatically — do not edit `project.pbxproj` for it.
- Suites exist and are expected to stay green: domain (`WorkoutModelTests`, `WorkoutOrderTests`,
  `WorkoutCopyTests`, `WorkoutDefaultsTests`, `PersistenceTests`, `DataIntegrityTests`), progress
  (`ExerciseStatsTests`, `TrainingAnalyticsTests`), sync
  (`WatchSessionManagerTests`, `WatchWireFormatTests`, `WatchSyncMergeTests`), and UI (`WorkoutActiveScreenUITests`,
  `WorkoutCopyUITests`, `WorkoutSetEditUITests`, `WorkoutStartAccessoryUITests`, `ExerciseProgressUITests`,
  `WorkoutRecordsUITests`, `AnalyticsUITests`). Extend the
  matching suite rather than starting a parallel one.

Local-only notes, both gitignored — consult them when they exist, don't rely on it:

- `plan/` — `test-suites.md` (catalog of suites and checks worth writing) and `review.md`
  (defects found while reading the code, with file/line references).
- `plans/features/<name>/` — per-feature `requirements.md` + `technical-notes.md`. Code comments
  reference these by path (e.g. `Workout.startedAt` points at `plans/features/delete-fixture`).

## Architecture

### Project layout

The iOS app's sources are grouped by feature, with the shared domain model on its own. All four targets use file-system-synchronized groups, so moving or adding a file is just a filesystem change — never edit `project.pbxproj` for it.

| Folder (under `LiftLog/`) | What goes there |
|---|---|
| `App/` | Entry point and tab shell: `LiftLogApp`, `RootTabView`, `PreviewSupport` |
| `Models/` | SwiftData models and the logic on them: `Workout`, `WorkoutItem`, `WorkoutSet`, `Exercise`, `WorkoutCompletion`, `WorkoutFlow`, `DataIntegrity` |
| `Workouts/` | Workout list, plan/active/completed screens, set logging and editing, shared set inputs, rest timer |
| `Catalog/` | Bundled exercise catalog and its screens, exercise picker, thumbnails |
| `MuscleMap/` | Muscle atlas data, SVG path parsing, `MuscleMapView` |
| `Progress/` | `ExerciseStats`, the exercise progress screen, `TrainingAnalytics` and the Analytics tab |
| `Sync/` | `WatchSessionManager` and the phone's copy of `WorkoutSyncModels.swift` |
| `Services/` | System integrations: `HealthKitManager`, `NotificationManager` |
| `DesignSystem/` | `Theme`, `Fonts`, `RussianPlural` |

`Assets.xcassets`, `Info.plist` and `LiftLog.entitlements` stay at the `LiftLog/` root — the build settings point at those paths. The watch app (`LiftLogWatchApp Watch App/`) and both test targets are flat. `WorkoutSyncModels.swift`'s two paths are hardcoded in `Scripts/check-watch-sync-parity.sh` and `SourcePaths` (`LiftLogTests/Support/WatchSyncFixtures.swift`) — move it and update both.

### Data model (SwiftData, iOS target only)

**`Workout` is the only top-level entity — there are no templates.** (`WorkoutTemplate`/`TemplateItem` were removed; copying a workout is what "repeat this workout" means now. Don't reintroduce a template type.)

`Workout` —(cascade)→ `WorkoutItem` (the *plan*) and —(cascade)→ `WorkoutSet` (what was actually *logged*). A `WorkoutItem` is one planned position: one exercise plus optional planned weight/reps. One exercise can occupy several consecutive positions — that's a plan for several sets. `Exercise` optionally points at a `CatalogExercise.id` (`catalogID`) to link back to the built-in exercise database; when nil, it's a user-defined exercise (this path exists in the model but has no dedicated creation UI — all current UI flows go through `ExerciseCatalog.exercise(for:)`).

A workout lives in three states, derived from two timestamps (`isActive == startedAt != nil && completedAt == nil`):

| State | `startedAt` | `completedAt` |
|---|---|---|
| План — created/copied, not started | nil | nil |
| Идёт — at most one at a time | set | nil |
| Завершена — goes to history and HealthKit | set | set |

`start()` also moves `date` to the actual start time, so a copy that sat around as a plan doesn't carry its creation date into the list/HealthKit.

Matching a logged `WorkoutSet` back to its planned `WorkoutItem` is positional: `Workout.plannedItem(for:)` counts how many sets are already logged for an exercise and indexes into that exercise's planned positions at the same offset. This is how `defaultWeight(for:)`/`defaultReps(for:)` pre-fill the next set's inputs.

Ordering, and the invariants that hold it together:

- `WorkoutItem.order` and `WorkoutSet.order` are assigned as `max(existing) + 1`, never `count` — deletion doesn't renumber, so `count` can collide with a surviving row. Gaps are harmless.
- `Workout.sortIndex` is the manual order in the workout list, left at 0 until the user drags a row; while every row is 0 the list falls back to date order (`WorkoutListView`).
- `moveExercise(from:to:)` moves whole exercise *groups* (all of an exercise's positions travel together) and then renumbers `order` sequentially; it reimplements `move(fromOffsets:toOffset:)` semantics so the model layer doesn't import SwiftUI.
- `deleteExercise(_:context:)` removes from the in-memory `items`/`sets` arrays as well as calling `context.delete` — SwiftData won't prune a deleted object out of an already-loaded relationship array until the next save/fetch.

`Workout.copy(of:sortIndex:now:context:)` builds a plan from an existing workout: same ordered exercises, `Exercise` objects **shared, not duplicated** (so exercise history stays unified), source never mutated, sets and both timestamps never copied. Per exercise, already-logged sets become the copy's plan when there are any (copy "what was actually done"); otherwise the source's own planned positions are copied.

`Workout.version` is a monotonic counter bumped by `bumpVersion()` on every change to the workout's contents — one logged set is exactly +1, and plan edits/start/finish bump it too so the counter never goes backwards. It rides in the watch snapshot and is how the watch decides whether the phone has caught up with what it logged offline. Anything that mutates a workout outside the model layer (currently only `EditSetView`) has to bump it by hand.

`Exercise` and `Workout` both carry a `syncID: UUID` used as the `Identifiable` id in the watch wire format (see below), independent of SwiftData's own `persistentModelID`. **`DataIntegrity.deduplicateSyncIDs`** runs once on every launch (`RootTabView.onAppear`) to repair a historical bug where SwiftData's default-value expression for `syncID` was captured once at the schema level rather than per-insert, causing older records to share one UUID — read the doc comment on `DataIntegrity.swift` before touching `syncID` defaults again.

### Exercise catalog

`exercises.json` (~1MB, bundled resource, from the free-exercise-db dataset) is decoded once into `ExerciseCatalog.all`/`byID`/`groups` as `static let`s (module-load time, not per-view), then `Exercise.catalogExercise` looks up by `catalogID` to get muscle groups, instructions, equipment, etc. Do not reintroduce a per-view/per-call parse of this file.

### Muscle map rendering

`MuscleMapData.swift` holds raw SVG path strings for ~35 body regions (front+back, from a body-highlighter atlas) at a fixed 724×1448 canvas (back paths pre-offset +724 in x so front/back share one coordinate space). `SVGPath.swift` parses those path strings into `Path` once at load (`MuscleMap.frontRegions`/`backRegions`), not per render. `MuscleAtlas` maps the catalog's muscle-name strings (`primaryMuscles`/`secondaryMuscles`, e.g. `"lats"`, `"lower back"`) to the atlas's region slugs, split by which side of the body actually shows them — a muscle can have slugs on only one side. `MuscleMapView` draws one side via `Canvas`, with an optional `zoomToHighlight` mode that frames on the highlighted regions' bounding box (used for thumbnails) instead of the full body, and an `intensities` heat-map mode (slug → 0…1) used by the Analytics tab.

### Watch connectivity (no shared data store)

The watch app has no SwiftData store and no App Group — the two entitlements files only grant HealthKit. All state flows through `WatchConnectivity`, using plain `Codable` DTOs in `WorkoutSyncModels.swift` (duplicated verbatim in both targets — `LiftLog/Sync/WorkoutSyncModels.swift` and `LiftLogWatchApp Watch App/WorkoutSyncModels.swift` — since the targets don't share a framework; keep them in sync by hand when the wire format changes):

- **Phone → watch**: `WatchSessionManager` (iOS target) pushes a `WatchContext { snapshot, plans, appliedCommandIDs }` via `updateApplicationContext`. `snapshot` is the active workout (nil when none) plus rest-timer state; `plans` are the not-yet-started workouts the watch can list and start, capped at 20 and carrying their full `plannedSets` so the watch can advance through a plan with no phone in range; `appliedCommandIDs` is a bounded FIFO of commands the phone has applied, echoed back as acknowledgements. `refresh()` rebuilds the whole thing from the store; `pushSnapshot(for:)` is for the cases where a fetch would lie (a row deleted but not yet saved).
- **Watch → phone**: `PhoneSessionManager` (watch target) sends `["command": WatchCommand]` — `.logSet` / `.start` / `.finish` — via `sendMessage`, plus live-only `["skipRest": true]` and `["requestContext": true]` (the watch's only way to *pull* state — every other delivery is a push the phone decides to make, so without it a lost push leaves the watch on a stale plan list forever; sent on activation, on regained reachability and on foreground). `WatchSessionManager.apply(_:context:reply:)` is the *only* place on the phone that mutates the `ModelContext` on the watch's behalf: it looks up the workout/exercise by `syncID` (falling back to matching by exercise name if the ID is stale), applies the command, and replies with the freshly pushed context. Commands are deduplicated by `commandID`, which is what makes redelivery safe. A `.start` while a *different* workout is running is refused with `["conflict": syncID]` rather than resolved.
- **Offline queue (watch)**: commands are not thrown at the phone when it isn't reachable. They go into a queue persisted by `PendingCommandStore` (JSON in Application Support, survives the app being killed), flushed one at a time in order — order matters, a `.start` has to land before the sets logged into it — on reachability changes, on context arrival, and on foreground. What the watch UI shows is the phone's context with that queue folded in: `WatchSyncMerge` (pure functions living in the shared `WorkoutSyncModels.swift`, so they can be tested from `LiftLogTests` — the watch target has no test target). A command leaves the queue when the phone acknowledges its `commandID`, or, if that ack aged out of the bounded window, when the workout's `version` on the phone has already reached what the command expected to produce. On the way to the background, whatever is still queued is also handed to `transferUserInfo` so the system delivers it while the app isn't running; the double delivery is harmless because of the `commandID` dedup.
- **Health recording**: heart rate and energy only exist when the watch records the workout with a live `HKWorkoutSession` — `WorkoutRecorder` (watch target), which follows the merged snapshot: a workout appearing starts a session, the workout going away ends it and saves. What to do is decided by `WatchHealthRecording.action` in the shared file (tested from `LiftLogTests`); it ignores the context cached from an earlier run (`PhoneSessionManager.isSnapshotTrusted`), or a days-old context would start a bogus recording. Starting a workout on the phone launches the watch app for it (`HealthKitManager.startWatchWorkout` → `WatchAppDelegate.handle(_:)`). Once collection begins the watch queues `.healthRecorded`; the phone sets `Workout.healthRecordedOnWatch` (+1 version, lands by version like `.logSet`), `HealthKitManager.save` then skips its bare start/end fallback, and if the fallback was already saved it's deleted by its `LiftLogWorkoutID` + `LiftLogRecordedOn = phone` metadata. A workout done without the watch still gets the phone's fallback, with no heart rate.
- Rest timer state (`endDate`/`exerciseName`) rides inside the same snapshot. Both sides independently schedule a local notification for the timer's end — `NotificationManager` (phone) and `RestNotificationManager` (watch) — because notification mirroring from phone to watch only works when the phone is locked/idle, not during an active hands-on-watch workout. If you change rest-duration or notification content, update both.

### Theming and assets

`Theme.swift` defines the full color palette as `Color` statics (`.ink`, `.chalk`, `.plateBlue`, etc.) plus a matching `ShapeStyle` extension — use these instead of ad hoc colors. `Fonts.swift` wraps three bundled custom fonts (`Oswald-SemiBold` display, `IBMPlexSans-Regular` body, `IBMPlexMono-Regular` for numeric weight×reps display) behind `Font.display/.sans/.mono`.

### Reusable input/display components

`SetInputViews.swift` holds the shared weight/reps entry controls (`WeightInputRow`, `RepsInputRow`) and the set-row display (`SetRow`), used across `ExerciseDetailView`, `WorkoutDetailView`, `WorkoutExerciseLogView`, `WorkoutItemDefaultsView`, and `EditSetView` — prefer extending these over re-adding another inline copy of the weight/reps UI.

### Progress, records and analytics

Nothing about progress is stored — it's all derived from logged `WorkoutSet`s, so editing or deleting a set re-derives it (decisions and requirements in `plans/features/progress-analytics`). `ExerciseStats` flattens an exercise's sets into `SetSample`s and derives weight records, sessions, chart points and «Прошлый раз»; `TrainingAnalytics` builds the «Аналитика» tab (`AnalyticsView`) from the same samples. **Records are by weight only**: a set is a record when it's strictly heavier than every earlier set of the exercise; the first weighted set and bodyweight sets never are. The rule itself (`WeightRecord`) lives in the shared `WorkoutSyncModels.swift` so the watch can apply it offline. Record marks count the running workout; the Analytics aggregates don't (only finished workouts and sets logged outside a workout).
