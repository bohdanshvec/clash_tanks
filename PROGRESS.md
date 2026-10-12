# PROGRESS.md

## Текущая контрольная точка

**Завершены:** Stage 1–14, Stage 15.1–15.17, Stage 16 — Players, Stage 17 — Deck UI, Stage 18 — Waiting / Started, **Stage 19 — Human vs Human**.

**Следующий этап:** Stage 20 — Decision Provider. Его реализация ещё не начата в рамках этой контрольной точки.

## Последний подтверждённый результат тестов

```text
bin/rails test
450 runs, 1574 assertions, 0 failures, 0 errors, 0 skips
```

Перед завершением Stage 19 также выполнялись целевые тесты Engine, таймеров и GamesController:

```text
52 runs, 432 assertions, 0 failures, 0 errors, 0 skips
```

В завершающей проверке Stage 19 код и тесты не изменялись. Не добавлять тесты для уже проверенного поведения без конкретного пробела или ошибки.

## Реализованные игровые и технические основы

- `GameEngine`: Action/Result, изолированное изменение копии GameState, VisibleState и server-side AvailableActions.
- StartGame, Draw, turns, Fuel, timers, PlayCard, Move, Attack, HQ/Platoon, FinishGame и Surrender.
- Hidden information, события Engine и визуальные Turbo/Stimulus реакции.
- Seed базового контента: 3 Nation, 2 Ability, 33 Card, 18 Technique, 6 Platoon, 3 Headquarters, 6 CardAbility.
- Browser UI: selection, Drag & Drop, player perspective, finished UI, timer и Turbo updates.
- Account/guest identity на Player и session-based authentication.

## Stage 16 — Players (завершён)

`Player` одновременно account и игровая сущность; реализованы регистрация, вход, выход, `has_secure_password`, `current_player`, session-based identity, header, публичные страницы, зарегистрированный `/statistics`, development command `bin/rails dev:create_game`. Отдельная модель User и Devise не используются.

## Stage 17 — Deck UI (завершён)

Реализованы Deck, DeckCard, Deck Weight, Headquarters, `StarterDecks::Create`, стартовые колоды для зарегистрированных и гостей, каталог Cards, `/decks`, preview/editor, quantity, валидации, create/edit/destroy, тесты и browser UI.

`/decks` — управление колодами; запуск игры с полной Deck выполняется через `/play`. Гость может просматривать starter Deck, но не управлять Deck.

## Stage 18 — Waiting / Started (завершён)

### /play и matchmaking

- `/play`, выбор полной Deck, PvP, UI-кнопка AI.
- Создание waiting Game и первого GamePlayer.
- `Matchmaking::FindOpponent`: диапазон Deck Weight ±15%, ближайший вес, oldest tie-break, self exclusion, исключение started/finished/two-player games.
- `Matchmaking::Join` с `with_lock`, второй GamePlayer, StartGame, waiting → started, защита от повторного Join, cancel waiting.
- Проверен lifecycle `Player/Guest → /play → Deck → waiting → heartbeat → Join → StartGame → started → first Action`.
- Проверены состав GamePlayer, Nation/Deck/Headquarters, начальный GameState, field/HQ, hand/deck/graveyard/platoons, resources, fuel, current player, время.

### VisibleState и Controller boundary

- Игрок видит собственную руку, публичные данные, свои AvailableActions, таймеры и результат игры.
- Не раскрываются чужая рука, содержимое/порядок чужой колоды и скрытая информация о graveyard.
- Actions для `waiting + state == nil` отклоняются: участнику 422, постороннему 403. Waiting game не поступает в Engine как started game.

### Waiting heartbeat и cleanup

- Heartbeat при подключении и далее каждые 10 секунд; остановка при Stimulus disconnect; session-based request и CSRF.
- Проверены ответы heartbeat: успешное обновление, чужая игра 403, started 422, отсутствие авторизации 401.
- `Matchmaking::CleanupStaleWaitingGames` удаляет stale waiting, сохраняет fresh waiting, started/finished и waiting с `last_seen_at == nil`; обновляет другие waiting rooms через Turbo.
- Turbo refresh проверен при Join, создании waiting game и cleanup.

### Guest lifecycle

- Гость создаётся при `/play` без current player, получает временный Player и три starter Deck, identity сохраняется в session.
- Повторный `/play` использует того же гостя. Поддерживаются guest vs guest и guest vs registered.
- Гость не управляет Deck и не использует `/statistics`; просмотр `/decks` не создаёт гостя.
- Cleanup неактивных гостей: порог 24 часа; active waiting/started защищены; starter Deck и finished GamePlayer очищаются с сохранением исторической Game.
- Guest browser lifecycle проверен вручную.

## Stage 19 — Human vs Human (завершён)

### Подтверждённая реализация

- Полный PvP lifecycle от `/play` и waiting/Join/StartGame до действий и завершения партии неоднократно проверен пользователем в **двух независимых браузерах**.
- `Move`, `Attack`, `PlayCard`, `EndTurn`, `Surrender` проходят через общий `GamesController#process_game_action` и GameEngine.
- `with_lock` перечитывает актуальное состояние перед Engine; только успешный Result сохраняется в `Game.state`. Отказанные Actions не сохраняются и не вызывают Turbo update.
- После успешного сохранения общий `broadcast_game_update` рассылает обновление обоим участникам с отдельным `GameEngine::VisibleState` для каждого.
- `show` загружает сохранённое состояние; `show.html.erb` создаёт персональную Turbo-подписку; `_game.html.erb` использует VisibleState, а не полный Game.state. Перезагрузка страницы получает актуальный snapshot из базы.
- Stimulus `game_events_controller.js` отвечает за взаимодействие и визуальные события, не применяет правила игры.
- `game_timer_controller.js` отображает время с поправкой на серверное время, отсчитывает время активного игрока, отправляет `end_turn` только за активного игрока, блокирует повторный запрос в рамках экземпляра контроллера, очищает interval при disconnect и прекращает работу в finished state.
- Проверены причины завершения: `headquarters_destroyed`, `time_expired`, `empty_deck_damage`, `surrender`; результат, пустые AvailableActions, запрет следующих Actions и защита hidden information.
- Существующие тесты проверяют Turbo-обновления обоих игроков при завершении игры, а полный lifecycle — при переходе хода.

### Итог проверки

Stage 19 закрыт после анализа Controller, интеграционных тестов, Turbo-шаблонов, Stimulus и успешного полного набора из **450 тестов / 1574 утверждений**. Новых тестов и изменений рабочего кода в заключительной проверке не потребовалось.

### Некритичные наблюдения (не блокируют Stage 20)

- `game_events_controller.js` и `game_timer_controller.js` передают `player_id` в запросах, хотя сервер определяет игрока по session. Это избыточный параметр, а не используемый в показанном Controller источник identity.
- При сетевой ошибке `fetch` автоматического `end_turn` нет повторной попытки в текущем экземпляре Stimulus controller; при переподключении экземпляр создаётся заново.
- Turbo broadcast выполняется после транзакции с `with_lock`. При почти одновременных успешных запросах теоретически возможен порядок доставки обновлений, отличающийся от порядка сохранения. В проверенной игре проблема не воспроизведена; не вводить изменения без конкретного случая.

## Архитектурные границы

```text
Decision Provider → Action → GameEngine → GameState
```

```text
UI → Stimulus → Controller → Action → GameEngine → GameState → VisibleState → Turbo → Stimulus
```

```text
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

GameEngine — единственный арбитр правил. Controller, UI, Stimulus, Turbo и AI не изменяют GameState напрямую. `Result.events` передаются через Controller/Turbo для визуальных эффектов; события UI не определяют правила.

## Следующий этап

**Stage 20 — Decision Provider.** Спроектировать общий интерфейс источника решений для Human и будущих AI/External API/Local model. Provider получает только разрешённый VisibleState, выдаёт Action; GameEngine валидирует и применяет Action. Задачи и критерии — в `ROADMAP.md`.
