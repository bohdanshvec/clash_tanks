# PROGRESS

## Текущая контрольная точка

Завершены: Stage 1–14, Stage 15.1–15.17, Stage 16 — Players, Stage 17 — Deck UI, Stage 18 — Waiting / Started, Stage 19 — Human vs Human.

Stage 20 — Decision Provider: основная реализация выполнена; требуется завершить итоговую сверку критериев и документации.

AI provider и OpenAI adapter уже реализованы и покрыты тестами с заглушками. Это ещё не означает, что AI полностью подключён к пользовательскому игровому lifecycle: этот вопрос относится к следующему этапу.

### Последний подтверждённый результат тестов

```
bin/rails test
478 runs, 1656 assertions, 0 failures, 0 errors, 0 skips
```

Дополнительно после реализации глубокой неизменяемости `Action`:

```
bin/rails test test/services/game_engine/action_test.rb
6 runs, 11 assertions, 0 failures, 0 errors, 0 skips
```

Это последние подтверждённые результаты. Если после них меняется код, перед фиксацией следующей контрольной точки нужно повторно запустить полный набор тестов.

## Реализованные игровые и технические основы

- `GameEngine`: `Action`/`Result`, изолированное изменение копии `GameState`, `VisibleState` и server-side `AvailableActions`.
- `StartGame`, `Draw`, turns, Fuel, timers, `PlayCard`, `Move`, `Attack`, HQ/Platoon, `FinishGame` и `Surrender`.
- Hidden information, события Engine и визуальные Turbo/Stimulus реакции.
- Seed базового контента: 3 Nation, 2 Ability, 33 Card, 18 Technique, 6 Platoon, 3 Headquarters, 6 CardAbility.
- Browser UI: selection, Drag & Drop, player perspective, finished UI, timer и Turbo updates.
- Account/guest identity на `Player` и session-based authentication.
- Decision Provider: `Base`, `Context`, `Human` и `AI`.
- OpenAI adapter с конфигурированием модели через `OPENAI_MODEL` и ключа через `OPENAI_API_KEY`.
- Глубокая неизменяемость `GameEngine::Action`.
- Тесты AI, нормализации JSON payload и OpenAI adapter без реальных API-запросов.

## Stage 16 — Players (завершён)

`Player` одновременно account и игровая сущность; реализованы регистрация, вход, выход, `has_secure_password`, `current_player`, session-based identity, header, публичные страницы, зарегистрированный `/statistics`, development command `bin/rails dev:create_game`.

Отдельная модель `User` и Devise не используются.

## Stage 17 — Deck UI (завершён)

Реализованы `Deck`, `DeckCard`, Deck Weight, Headquarters, `StarterDecks::Create`, стартовые колоды для зарегистрированных и гостей, каталог Cards, `/decks`, preview/editor, quantity, валидации, create/edit/destroy, тесты и browser UI.

`/decks` — управление колодами; запуск игры с полной `Deck` выполняется через `/play`. Гость может просматривать starter `Deck`, но не управлять `Deck`.

## Stage 18 — Waiting / Started (завершён)

### /play и matchmaking

- `/play`, выбор полной `Deck`, PvP и UI-кнопка AI.
- Создание waiting `Game` и первого `GamePlayer`.
- `Matchmaking::FindOpponent`: диапазон Deck Weight ±15%, ближайший вес, oldest tie-break, self exclusion, исключение started/finished/two-player games.
- `Matchmaking::Join` с `with_lock`, второй `GamePlayer`, `StartGame`, waiting → started, защита от повторного Join, cancel waiting.
- Проверен lifecycle Player/Guest → `/play` → Deck → waiting → heartbeat → Join → `StartGame` → started → first Action.
- Проверены состав `GamePlayer`, Nation/Deck/Headquarters, начальный `GameState`, field/HQ, hand/deck/graveyard/platoons, resources, fuel, current player, время.

### VisibleState и Controller boundary

- Игрок видит собственную руку, публичные данные, свои `AvailableActions`, таймеры и результат игры.
- Не раскрываются чужая рука, содержимое/порядок чужой колоды и скрытая информация о graveyard.
- Actions для waiting + `state == nil` отклоняются: участнику 422, постороннему 403. Waiting game не поступает в Engine как started game.

### Waiting heartbeat и cleanup

- Heartbeat при подключении и далее каждые 10 секунд; остановка при Stimulus disconnect; session-based request и CSRF.
- Проверены ответы heartbeat: успешное обновление, чужая игра 403, started 422, отсутствие авторизации 401.
- `Matchmaking::CleanupStaleWaitingGames` удаляет stale waiting, сохраняет fresh waiting, started/finished и waiting с `last_seen_at == nil`; обновляет другие waiting rooms через Turbo.
- Turbo refresh проверен при Join, создании waiting game и cleanup.

### Guest lifecycle

- Гость создаётся при `/play` без current player, получает временный `Player` и три starter `Deck`, identity сохраняется в session.
- Повторный `/play` использует того же гостя. Поддерживаются guest vs guest и guest vs registered.
- Гость не управляет `Deck` и не использует `/statistics`; просмотр `/decks` не создаёт гостя.
- Cleanup неактивных гостей: порог 24 часа; active waiting/started защищены; starter `Deck` и finished `GamePlayer` очищаются с сохранением исторической `Game`.
- Guest browser lifecycle проверен вручную.

## Stage 19 — Human vs Human (завершён)

### Подтверждённая реализация

- Полный PvP lifecycle от `/play` и waiting/Join/`StartGame` до действий и завершения партии неоднократно проверен пользователем в двух независимых браузерах.
- `Move`, `Attack`, `PlayCard`, `EndTurn`, `Surrender` проходят через общий `GamesController#process_game_action` и `GameEngine`.
- `with_lock` перечитывает актуальное состояние перед Engine; только успешный `Result` сохраняется в `Game.state`. Отказанные Actions не сохраняются и не вызывают Turbo update.
- После успешного сохранения общий `broadcast_game_update` рассылает обновление обоим участникам с отдельным `GameEngine::VisibleState` для каждого.
- `show` загружает сохранённое состояние; `show.html.erb` создаёт персональную Turbo-подписку; `_game.html.erb` использует `VisibleState`, а не полный `Game.state`. Перезагрузка страницы получает актуальный snapshot из базы.
- Stimulus `game_events_controller.js` отвечает за взаимодействие и визуальные события, не применяет правила игры.
- `game_timer_controller.js` отображает время с поправкой на серверное время, отсчитывает время активного игрока, отправляет `end_turn` только за активного игрока, блокирует повторный запрос в рамках экземпляра контроллера, очищает interval при disconnect и прекращает работу в finished state.
- Проверены причины завершения: `headquarters_destroyed`, `time_expired`, `empty_deck_damage`, `surrender`; результат, пустые `AvailableActions`, запрет следующих Actions и защита hidden information.
- Существующие тесты проверяют Turbo-обновления обоих игроков при завершении игры, а полный lifecycle — при переходе хода.

### Итог проверки

Stage 19 закрыт после анализа Controller, интеграционных тестов, Turbo-шаблонов, Stimulus и успешного полного набора из 450 тестов / 1574 утверждений на момент завершения этапа.

Последующие изменения Decision Provider увеличили тестовый набор до 478 тестов / 1656 утверждений. Подробности — в разделе Stage 20.

## Stage 20 — Decision Provider (основная реализация выполнена)

### Общая архитектура

Сохранён инвариант:

```
Decision Provider → Action → GameEngine → GameState
```

`GameEngine` остаётся единственным арбитром правил. Provider формирует `GameEngine::Action` и не применяет правила самостоятельно.

### Реализованные компоненты

- `DecisionProviders::Base` — базовый интерфейс с `call`.
- `DecisionProviders::Context` — контекст игрока с `player_id`, `VisibleState` и `available_actions`.
- `DecisionProviders::Human` — преобразование действий пользователя в `Action`.
- `DecisionProviders::AI` — получение решения от источника, проверка формата, преобразование JSON payload в формат, используемый игровыми обработчиками, и ограниченные повторные попытки.
- `DecisionProviders::OpenAiAdapter` — подготовленный адаптер OpenAI Responses API.
- `GameEngine::Action` — глубокое копирование и замораживание вложенных `Hash` и `Array`.

### Граница безопасности

- AI получает `VisibleState`, а не полный исходный `GameState`.
- `Context` рекурсивно замораживает `VisibleState`.
- `Action` рекурсивно копирует и замораживает payload.
- AI не применяет правила и не сохраняет состояние.
- Любое сформированное действие должно пройти обычную проверку `GameEngine`.

### OpenAI adapter

Адаптер использует `OPENAI_API_KEY` и `OPENAI_MODEL`. Модель по умолчанию — `gpt-4.1-mini`.

Тесты адаптера используют fake/mock-объекты. Реальные API-запросы в тестовом наборе не выполняются.

Фактическое подключение AI к пользовательскому игровому lifecycle ещё нужно отдельно проверить и завершить на Stage 21. Наличие класса `AI` и адаптера не считается доказательством того, что режим AI уже полностью работает в браузере.

### Последние проверки

```
bin/rails test test/services/game_engine/action_test.rb
6 runs, 11 assertions, 0 failures, 0 errors, 0 skips

bin/rails test
478 runs, 1656 assertions, 0 failures, 0 errors, 0 skips
```

### Что осталось проверить перед окончательным закрытием Stage 20

- Сверить реализацию `Base`, `Context`, `Human` и `AI` с их тестами и архитектурными границами.
- Убедиться, что контроллер и `GameActionRunner` не позволяют обходить Engine.
- Убедиться, что контекст AI не раскрывает скрытые данные и не предоставляет возможность изменять состояние.
- Обновить `ARCHITECTURE.md`, `PROGRESS.md` и `ROADMAP.md` согласно фактическому коду.

Не менять игровые правила и не подключать платный API для завершения Stage 20.

## Архитектурные границы

```
Decision Provider → Action → GameEngine → GameState
```

```
UI → Stimulus → Controller → Decision Provider → Action
    → GameActionRunner → GameEngine → GameState
    → VisibleState → Turbo → Stimulus
```

```
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

`GameEngine` — единственный арбитр правил. Controller, UI, Stimulus, Turbo и AI не изменяют `GameState` напрямую. `Result.events` передаются через Controller/Turbo для визуальных эффектов; события UI не определяют правила.

## Следующий этап

**Stage 21 — AI в игровом процессе.**

Нужно проверить и завершить полный lifecycle AI: выбор режима AI, запуск партии, получение решения через provider, передача `Action` в Engine, обработка ошибок и обновление игры. Точные критерии — в `ROADMAP.md`.
