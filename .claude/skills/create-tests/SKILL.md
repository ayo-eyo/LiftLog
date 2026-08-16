---
name: create-tests
description: How and when to write tests in the LiftLog project. Use whenever you add or change functionality, fix a bug, or refactor — to decide whether a test is required, which target and suite it belongs in, how to write it with the existing helpers, and how to run it. Also use when asked "нужен ли тест", "покрой тестами", "напиши тест", or before finishing any change to models, sync, or app flows.
---

# Писать ли тест и какой

Проект: SwiftUI + SwiftData (iOS) + тонкое watchOS-приложение поверх WatchConnectivity.
Тестовая инфраструктура уже готова — цели `LiftLogTests` / `LiftLogUITests`, тест-планы
`TestPlans/Unit.xctestplan` и `TestPlans/All.xctestplan`, хелперы в `*/Support/`.
Фреймворк — **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`), XCTest
только в UI-тестах.

## 1. Решение: нужен ли тест

Сначала классифицируй изменение — от этого зависит всё остальное.

| Что меняешь | Тест | Куда |
|---|---|---|
| Логика в `@Model`-классах (`Workout`, `Exercise`, `WorkoutTemplate`, `TemplateItem`, `WorkoutSet`) | **обязателен** | `LiftLogTests` |
| Предзаполнение из шаблона (`templateItem`/`defaultWeight`/`defaultReps`) | **обязателен**, включая граничные позиции | `LiftLogTests` |
| Синхронизация с часами: `WatchSessionManager`, `PhoneSessionManager`, DTO в `WorkoutSyncModels.swift` | **обязателен** + `Scripts/check-watch-sync-parity.sh` | `LiftLogTests` |
| Чистые функции и парсеры: `SVGPath`, `MuscleAtlas`, `RestTimer`, `TimeInterval.clockString` | **обязателен** | `LiftLogTests` |
| Работа с каталогом (`ExerciseCatalog`) и его данными | **обязателен** | `LiftLogTests` |
| Исправление бага в любом из перечисленного | **обязателен, сначала красный тест** | `LiftLogTests` |
| Новый пользовательский сценарий целиком (новый экран с потоком действий) | UI-тест на «счастливый путь» + юниты на логику под ним | `LiftLogUITests` + `LiftLogTests` |
| Изменение уже покрытого UI-потока | обнови существующий UI-тест | `LiftLogUITests` |
| Только верстка/цвета/шрифты/отступы, без изменения поведения | не нужен | — |
| Строки интерфейса, иконки | не нужен (но не ломай существующие UI-тесты — см. §6) | — |
| Рефакторинг без смены поведения | новых не пиши, **существующие должны пройти без правок** | — |

Если правишь поведение, у которого теста ещё нет, — сначала напиши тест на текущее
поведение, убедись, что он зелёный, потом меняй код. Так видно, что именно изменилось.

Полный каталог того, что стоит покрыть, лежит в `plan/test-suites.md`, а известные дефекты
с указанием строк — в `plan/review.md` (папка `plan/` локальная, в git её нет; если её нет
на машине — просто игнорируй эти ссылки).

## 2. Куда положить файл

- Юниты: `LiftLogTests/<Тема>Tests.swift` (например `WorkoutModelTests.swift`,
  `TemplateDefaultsTests.swift`, `WatchWireFormatTests.swift`).
- UI: `LiftLogUITests/<Поток>UITests.swift` (например `WorkoutFlowUITests.swift`).
- Общие хелперы — только в `*/Support/`, не в файлах с тестами.

Цели используют file-system-synchronized группы: **новый файл подхватывается сам**,
`project.pbxproj` править не нужно и нельзя (лишний диф).

## 3. Как писать юнит-тест

Используй готовые хелперы, не изобретай свои:

- `TestStore.open()` → `TestStoreHandle` с `context`, `container`, `fetch`, `count`,
  `reload()` (сохранить и перечитать новым контекстом);
- `Fixtures` — `exercise`, `catalogBackedExercise`, `workout`, `template`, `log`,
  детерминированные даты `Fixtures.epoch` / `Fixtures.date(offset:)`;
- `WatchSyncFixtures` — DTO и `[String: Any]`-сообщения ровно в том виде, в каком их шлют
  часы, `roundTrip`, `applicationContext`, `SourcePaths` для проверки паритета копий.

Шаблон:

```swift
import Testing
import SwiftData
@testable import LiftLog

@Suite("Workout.setsFor")
struct WorkoutSetsForTests {
    @Test("возвращает подходы только этого упражнения, по возрастанию времени")
    func filtersByExerciseAndSorts() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(exercises: [bench, squat], in: store.context)

        Fixtures.log([(60, 8), (65, 6)], for: bench, in: workout, context: store.context)
        Fixtures.log([(100, 5)], for: squat, in: workout, context: store.context)

        let sets = workout.setsFor(bench)
        #expect(sets.map(\.weight) == [60, 65])
        #expect(try store.count(WorkoutSet.self) == 3)
    }
}
```

Правила:

1. **Строй данные через продакшн-пути** (`Workout.logSet`, `WorkoutTemplate.addExercise`,
   `applyTemplate`), а не присваиванием связей вручную — иначе тест проверяет не тот код,
   который выполняется в приложении. Для этого и существуют `Fixtures`.
2. **Никакого `.now`** в данных теста: только `Fixtures.epoch` и смещения от него.
   Проверки времени (`RestTimer`) делай через явный `at:`-параметр, а не через ожидание.
3. **Свой стор на каждый тест.** `TestStore.open()` внутри теста, не в `static let` и не в
   свойстве сьюта, которое переиспользуется: планы гоняют тесты в случайном порядке и
   параллельно.
4. Проверяешь persistence — обязательно `store.reload()`, иначе проверяешь только
   изменения в памяти контекста.
5. **Один смысл на тест.** Несколько `#expect` про одно поведение — нормально; три разных
   сценария в одном тесте — нет. Для наборов входов используй параметризацию:
   `@Test(arguments: [...])`.
6. Имя теста — по-русски, в описании `@Test("…")`, формулируй как утверждение о поведении
   («не дублирует упражнение при повторном добавлении»), а не как «тест метода X».
7. `@MainActor` дописывать не нужно: у тестовых целей `SWIFT_DEFAULT_ACTOR_ISOLATION =
   MainActor`, всё и так на главном акторе. Аннотируй, только если сознательно уводишь
   код с главного актора.
8. Ожидаешь ошибку — `#expect(throws:)`, не `do/catch` с `Issue.record`.

## 4. Если код нельзя протестировать — добавь шов, а не пропускай тест

Единственная законная причина не покрыть логику — она намертво прибита к системному
синглтону. В этом случае сначала вводится шов (протокол + дефолтная реализация), потом
пишется тест. Прибитые места, известные на сегодня:

| Что | Шов |
|---|---|
| `WCSession.default` в `WatchSessionManager` / `PhoneSessionManager` | протокол с `isReachable`, `updateApplicationContext`, `sendMessage`, `transferUserInfo` |
| `UNUserNotificationCenter` в `NotificationManager` / `RestNotificationManager` | протокол `NotificationScheduling` |
| `HKHealthStore` в `HealthKitManager` | протокол с `save(_:)` |
| `Date()` внутри `RestTimer.start` | параметр `now: Date = .now` |
| `private` методы `WatchSessionManager` (`apply`, `logSet`, `exerciseInfo`) | сделать `internal`, доступ через `@testable` |

Шов вводится минимальным: протокол, дефолтное значение параметра или свойства — реальная
реализация, тест подставляет фейк. Никаких DI-контейнеров.

Тест **никогда** не должен ходить в реальные `WCSession`, `UNUserNotificationCenter`,
`HKHealthStore`, сеть или на диск.

## 5. Тест на баг

Порядок жёсткий:

1. Воспроизведи дефект тестом. Запусти — он должен **упасть**, и упасть по той причине,
   которая описана в баге (посмотри текст фейла, а не только красный статус).
2. Почини код.
3. Прогони снова — зелёный.
4. В описании `@Test` укажи суть дефекта: `@Test("повторная доставка команды не создаёт
   второй подход")`.

Если тест зелёный до фикса — ты воспроизвёл не то.

## 6. UI-тесты

- Запуск только через `AppLauncher.launch()` — он передаёт `-uiTestInMemoryStore`, и
  приложение стартует с пустой базы. Без этого предыдущий прогон оставит активную
  тренировку, и тест будет падать через раз.
- Ожидание — `waitUntilVisible()` из `Support/AppLauncher.swift`, не `sleep`.
- Ищи элементы по `accessibilityIdentifier`. Если у элемента его нет — **добавь в код
  приложения** (`.accessibilityIdentifier("workout.addExercise")`), а не цепляйся за
  русскую подпись: подписи меняются, тесты рассыпаются.
- UI-тест проверяет сценарий целиком (начать → добавить упражнение → записать подход →
  завершить), а не отдельные состояния — для состояний есть юниты.
- Один UI-тест на «счастливый путь» потока лучше, чем пять на его ветки.

## 7. Прогон и проверка результата

```bash
Scripts/test.sh                 # план Unit — при любой правке логики
Scripts/test.sh All             # план All (юниты + UI) — при правке потоков и перед сдачей задачи
Scripts/check-watch-sync-parity.sh   # после любой правки WorkoutSyncModels.swift
```

`xcodebuild` печатает мало из-за `-quiet`, поэтому **всегда** смотри итог:

```bash
xcrun xcresulttool get test-results summary --path build/TestResults.xcresult
```

Проверяй `result`, `passedTests`, `failedTests` и, при падении, `testFailures`.
Пустой бандл тоже даёт код 0 — «сборка прошла» не значит «тесты были».

Сдавать задачу можно только после зелёного прогона. Если тест падает не по твоей вине —
скажи об этом явно и покажи вывод, не выключай и не удаляй тест.

## 8. Чего не делать

- Не тестировать `body` SwiftUI-вью напрямую и не тащить снапшот-тесты без явной просьбы.
- Не писать тесты на `Theme`/`Fonts` (константы) и на плейсхолдеры вроде
  `AnalyticsPlaceholderView`.
- Не проверять в юнитах русские строки интерфейса — это забота UI-тестов.
- Не добавлять зависимости и тестовые фреймворки из сети: только Swift Testing и XCTest.
- Не менять `project.pbxproj`, `TestPlans/*.xctestplan` и схему ради нового файла с тестами.
- Не смягчать проверку, чтобы она позеленела (`#expect(x >= 0)` вместо точного значения).

## 9. Чек-лист перед завершением задачи

- [ ] Изменение классифицировано по таблице §1, решение про тесты осознанное.
- [ ] Для бага есть тест, который падал до фикса.
- [ ] Тесты используют `TestStore` / `Fixtures` / `WatchSyncFixtures`, без `.now` и без
      общего состояния.
- [ ] Если трогал `WorkoutSyncModels.swift` — обе копии синхронны, скрипт паритета зелёный.
- [ ] `Scripts/test.sh` (или `All`, если трогал потоки) прогнан, сводка из `xcresulttool`
      посмотрена, всё зелёное.
- [ ] Новых файлов в `project.pbxproj` не появилось.
