# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LiftLog is a SwiftUI + SwiftData workout-tracking app for iOS with a companion watchOS app. Two Xcode targets in one project (`LiftLog.xcodeproj`):

- **LiftLog** — the iOS app. Owns all persistence (SwiftData) and business logic.
- **LiftLogWatchApp Watch App** — a thin remote control with no persistence of its own; it mirrors state pushed from the phone over WatchConnectivity and sends commands back.

UI strings are in Russian.

## Commands

Build the iOS app for the simulator:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project LiftLog.xcodeproj -scheme LiftLog -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

To build/run the watch target, use the `LiftLogWatchApp Watch App` scheme with a watchOS simulator destination instead.

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
- **No test cases are written yet** — only the helpers above. Adding one is the first step of
  any behavioral change, per the skill.
- Both test targets use file-system-synchronized groups: a new file in `LiftLogTests/` or
  `LiftLogUITests/` is picked up automatically — do not edit `project.pbxproj` for it.

`plan/` (gitignored, local only) holds `test-suites.md` — the full catalog of suites and
checks worth writing — and `review.md` — defects found while reading the code, with file and
line references. Consult them when they exist; don't rely on them being there.

## Architecture

### Data model (SwiftData, iOS target only)

`Workout` —(cascade)→ `WorkoutSet`, and separately holds an unmanaged `[Exercise]` array (the exercises added to that workout) plus an optional `template: WorkoutTemplate?`. `WorkoutTemplate` —(cascade)→ `TemplateItem` (ordered list of exercise + default weight/reps). `Exercise` optionally points at a `CatalogExercise.id` (`catalogID`) to link back to the built-in exercise database; when nil, it's a user-defined exercise (this path exists in the model but has no dedicated creation UI — all current UI flows go through `ExerciseCatalog.exercise(for:)`).

Matching a logged `WorkoutSet` back to its planned `TemplateItem` is positional: `Workout.templateItem(for:)` counts how many sets are already logged for an exercise and indexes into `template.sortedItems` at that position. This is how `defaultWeight(for:)`/`defaultReps(for:)` pre-fill the next set's inputs.

`Exercise` and `Workout` both carry a `syncID: UUID` used as the `Identifiable` id in the watch wire format (see below), independent of SwiftData's own `persistentModelID`. **`DataIntegrity.deduplicateSyncIDs`** runs once on every launch (`RootTabView.onAppear`) to repair a historical bug where SwiftData's default-value expression for `syncID` was captured once at the schema level rather than per-insert, causing older records to share one UUID — read the doc comment on `DataIntegrity.swift` before touching `syncID` defaults again.

### Exercise catalog

`exercises.json` (~1MB, bundled resource, from the free-exercise-db dataset) is decoded once into `ExerciseCatalog.all`/`byID`/`groups` as `static let`s (module-load time, not per-view), then `Exercise.catalogExercise` looks up by `catalogID` to get muscle groups, instructions, equipment, etc. Do not reintroduce a per-view/per-call parse of this file.

### Muscle map rendering

`MuscleMapData.swift` holds raw SVG path strings for ~35 body regions (front+back, from a body-highlighter atlas) at a fixed 724×1448 canvas (back paths pre-offset +724 in x so front/back share one coordinate space). `SVGPath.swift` parses those path strings into `Path` once at load (`MuscleMap.frontRegions`/`backRegions`), not per render. `MuscleAtlas` maps the catalog's muscle-name strings (`primaryMuscles`/`secondaryMuscles`, e.g. `"lats"`, `"lower back"`) to the atlas's region slugs, split by which side of the body actually shows them — a muscle can have slugs on only one side. `MuscleMapView` draws one side via `Canvas`, with an optional `zoomToHighlight` mode that frames on the highlighted regions' bounding box (used for thumbnails) instead of the full body.

### Watch connectivity (no shared data store)

The watch app has no SwiftData store and no App Group — the two entitlements files only grant HealthKit. All state flows through `WatchConnectivity`, using plain `Codable` DTOs in `WorkoutSyncModels.swift` (duplicated verbatim in both targets — `LiftLog/WorkoutSyncModels.swift` and `LiftLogWatchApp Watch App/WorkoutSyncModels.swift` — since the targets don't share a framework; keep them in sync by hand when the wire format changes):

- **Phone → watch**: `WatchSessionManager` (iOS target) pushes a `WatchContext { snapshot: WatchWorkoutSnapshot? }` via `updateApplicationContext` whenever the active workout changes. `WatchWorkoutSnapshot` is nil when there's no active workout.
- **Watch → phone**: `PhoneSessionManager` (watch target) sends `["logSet": WatchLogSetCommand]` or `["skipRest": true]` via `sendMessage` (falling back to `transferUserInfo` when unreachable, which queues but gives no reply). `WatchSessionManager.apply(_:context:reply:)` is the *only* place on the phone that mutates the `ModelContext` on the watch's behalf — it looks up the workout/exercise by `syncID` (falling back to matching by exercise name if the ID is stale) and calls `Workout.logSet`.
- Rest timer state (`endDate`/`exerciseName`) rides inside the same snapshot. Both sides independently schedule a local notification for the timer's end — `NotificationManager` (phone) and `RestNotificationManager` (watch) — because notification mirroring from phone to watch only works when the phone is locked/idle, not during an active hands-on-watch workout. If you change rest-duration or notification content, update both.

### Theming and assets

`Theme.swift` defines the full color palette as `Color` statics (`.ink`, `.chalk`, `.plateBlue`, etc.) plus a matching `ShapeStyle` extension — use these instead of ad hoc colors. `Fonts.swift` wraps three bundled custom fonts (`Oswald-SemiBold` display, `IBMPlexSans-Regular` body, `IBMPlexMono-Regular` for numeric weight×reps display) behind `Font.display/.sans/.mono`.

### Reusable input/display components

`SetInputViews.swift` holds the shared weight/reps entry control and set-row display used across `ExerciseDetailView`, `WorkoutExerciseLogView`, `EditSetView`, `TemplateItemDefaultsView`, `WorkoutSummaryView`, and `TemplateDetailView` — prefer extending these over re-adding another inline copy of the weight/reps UI.

### Placeholders

`AnalyticsPlaceholderView` is a stub for a not-yet-built analytics tab (wired into `RootTabView`'s "Аналитика" tab).
