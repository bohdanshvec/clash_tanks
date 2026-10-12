# PROGRESS.md

## Текущая контрольная точка

Завершены Stage 1--14, Stage 15.1--15.17, Stage 16 --- Players, Stage 17
--- Deck UI, Stage 18 --- Waiting / Started, Stage 19 --- Human vs
Human, Stage 20 --- Decision Provider.

**Stage 21 --- AI в игровом процессе --- НЕ завершён.**

Последний подтверждённый пользователем полный набор тестов после
добавления постоянного AI-игрока и его колод:

``` text
489 runs, 1786 assertions, 0 failures, 0 errors, 0 skips
```

Отдельно подтверждены:

``` text
bin/rails test test/services/ai_players/decks_setup_test.rb
2 tests, 106 assertions, 0 failures, 0 errors, 0 skips

bin/rails test test/services/ai_players
4 tests, 114 assertions, 0 failures, 0 errors, 0 skips
```

Эти результаты подтверждают имеющиеся тесты, но не полный lifecycle
AI-игры. После следующих изменений кода полный набор необходимо
запускать заново.

## Завершённые этапы

### Stage 16 --- Players

`Player` одновременно account и игровая сущность. Реализованы
регистрация, вход, выход, `has_secure_password`, `current_player`,
session-based identity, header, публичные страницы, зарегистрированный
`/statistics`, development command `bin/rails dev:create_game`.
Отдельные `User`/Devise не используются.

### Stage 17 --- Deck UI

Реализованы `Deck`, `DeckCard`, Deck Weight, Headquarters,
`StarterDecks::Create`, стартовые колоды для зарегистрированных и
гостей, каталог Cards, `/decks`, preview/editor, quantity, валидации,
create/edit/destroy и browser UI. Гость просматривает starter Deck, но
не управляет Deck.

### Stage 18 --- Waiting / Started

Реализованы `/play`, выбор полной Deck, PvP UI, создание waiting Game и
первого GamePlayer, `FindOpponent`, безопасный `Join`, `StartGame`,
cancel waiting, heartbeat, stale cleanup, guest lifecycle, VisibleState
boundary и Turbo refresh. Проверен lifecycle Player/Guest → `/play` →
waiting → Join → `StartGame` → started → first Action.

### Stage 19 --- Human vs Human

Полный PvP lifecycle проверен пользователем в двух браузерах. `Move`,
`Attack`, `PlayCard`, `EndTurn`, `Surrender` проходят через controller и
Engine. `GameActionRunner` блокирует запись; только успешный результат
сохраняется. Turbo рассылает каждому игроку свой `VisibleState`.
Проверены причины завершения, пустые actions после завершения и защита
скрытой информации. Контрольная точка при закрытии Stage 19: 450 runs /
1574 assertions.

### Stage 20 --- Decision Provider

Реализованы `Base`, `Context`, `Human`, `AI`, `GameEngine::Action` с
глубоким копированием/замораживанием payload, `GameActionRunner`,
`VisibleState`, Groq adapter и OpenAI adapter. AI проверяет формат
ответа, нормализует JSON payload и делает максимум три попытки при
некорректном формате. Тесты adapters не требуют реальных API-запросов.

Текущая конфигурация: `AI_PROVIDER` по умолчанию `groq`, модель Groq по
умолчанию `openai/gpt-oss-20b`; OpenAI adapter доступен как
альтернатива. Ключи должны храниться только в переменных окружения, не в
Git.

## Stage 21 --- AI в игровом процессе (НЕ завершён)

### Что уже реализовано

#### База и модели

-   Миграция `20261012155105_add_mode_to_games.rb`: режимы игры `pvp` и
    `ai`.
-   Миграция `20261012155225_add_ai_to_players.rb`: поле `players.ai`.
-   Миграция с уникальным частичным индексом `MakeAiPlayerUnique`:
    только один игрок с `ai = true`.
-   `Game` имеет enum `mode` (`pvp`, `ai`), default `pvp`.
-   `Player#ai?` возвращает признак технического игрока.

#### Постоянный AI-игрок

`app/services/ai_players/setup.rb` (`AiPlayers::Setup`): - email
`ai@clash-tanks.local`, имя `ИИ`; - `guest: false`, `ai: true`; -
идемпотентно возвращает существующего AI-игрока; - обрабатывает конфликт
уникального индекса; - если email занят обычным игроком, сообщает об
ошибке.

#### Три постоянные AI-колоды

`app/services/ai_players/decks_setup.rb` (`AiPlayers::DecksSetup`)
создаёт:

  Название                           Нация        Вес
  ---------------------------------- ---------- -----
  `ИИ — США: лёгкая техника`         США           13
  `ИИ — СССР: средняя техника`       СССР          22
  `ИИ — Германия: тяжёлая техника`   Германия      28

Колоды собраны из существующих карт и штабов, полные, содержат по 10
карт с допустимым количеством копий. Повторный вызов не дублирует колоды
и DeckCard. Колоды принадлежат постоянному AI-игроку и должны
использоваться повторно в разных партиях.

#### Совместимость по весу

`app/services/matchmaking/ai_deck_selector.rb`
(`Matchmaking::AiDeckSelector`): - рассматривает полные колоды игрока с
`ai: true`; - допускает вес пользователя в пределах ±10% от AI-колоды; -
при нескольких совпадениях выбирает ближайший вес.

Целочисленные диапазоны: - AI weight 13 → пользовательский вес 12--14; -
AI weight 22 → 20--24; - AI weight 28 → 26--30.

Случайный выбор между совместимыми колодами обсуждался как возможное
будущее улучшение, но пока не реализован и не нужен для завершения
текущего этапа.

#### `/play`

`PagesController#play` загружает полные пользовательские колоды и
формирует `@ai_decks_by_deck_id`, вызывая selector для каждой
пользовательской колоды.

### Что ещё не реализовано

1.  **UI:** `play.html.erb` в ветке зарегистрированного игрока
    безусловно показывает кнопку «В бой --- ИИ». Нужно проверять
    `@ai_decks_by_deck_id[deck.id]`; при отсутствии совместимой колоды
    показывать сообщение, сохраняя PvP-кнопку.
2.  **Стартовые колоды и гость:** `PagesController#play` вызывает
    `ensure_guest_player!`, поэтому ветка `else` шаблона может быть
    недостижима. В ней `deck` является хешем без `id`, поэтому
    `@ai_decks_by_deck_id[deck.id]` неверно. Проверить intended guest
    flow и исправить согласованно.
3.  **Создание игры:** текущий `GamesController#create` разрешает только
    `mode == "pvp"` и отклоняет AI-режим с `422`. Нужна серверная
    валидация режима, принадлежности/полноты человеческой колоды и
    совместимости AI-колоды.
4.  **AI participants:** создать `Game(mode: "ai")` с человеком и
    постоянным AI-игроком, добавить обоих `GamePlayer` с правильными
    Deck/Nation/HQ и вызвать `GameEngine::StartGame`. Не создавать AI
    player/deck на каждую игру.
5.  **Автоматические ходы:** если первым ходит AI, вызвать его сразу
    после старта; после действия человека запускать AI только при
    активной игре и передаче хода ИИ.
6.  **Выполнение AI Action:** контекст строить для AI `player_id`,
    использовать только его `VisibleState`, все действия передавать
    через `GameActionRunner` и Engine.
7.  **Цикл и concurrency:** ограничить последовательные действия AI;
    после каждого действия перепроверять статус и текущего игрока;
    останавливать цикл при смене хода, завершении или ошибке; защититься
    от параллельного запуска AI для одной игры и устаревшего состояния.
8.  **Ошибки:** безопасно обрабатывать provider/API errors, timeout,
    неверный JSON, исчерпание повторов и отказ Engine. Отклонённый
    Action не должен сохранять состояние или считаться успешным ходом.
9.  **UI updates/security:** использовать существующий
    Turbo/VisibleState path; не раскрывать скрытые данные; не запускать
    AI после окончания игры.
10. **Тесты:** покрыть совместимость и server validation, создание/старт
    AI-игры, первый AI-ход, ответ на ход человека, несколько действий,
    ошибки, остановку цикла, concurrency, Turbo, hidden information,
    guest lifecycle и регрессии PvP. Использовать fake/mock provider; не
    делать реальные API-запросы.

### Следующие файлы для проверки

-   `app/controllers/games_controller.rb`
-   `app/controllers/pages_controller.rb`
-   `app/views/pages/play.html.erb`
-   `app/services/matchmaking/ai_deck_selector.rb`
-   `app/services/ai_players/setup.rb`
-   `app/services/ai_players/decks_setup.rb`
-   `app/services/decision_providers/a_i.rb`
-   `app/services/decision_providers/context.rb`
-   `app/services/decision_providers/groq_adapter.rb`
-   `app/services/game_action_runner.rb`
-   `app/services/game_engine/start_game.rb`
-   тесты controller, matchmaking, AI services, provider и StartGame.

Следующий практический шаг: изучить AI provider/context/adapters,
`Matchmaking::Join` и `FindOpponent`, `ApplicationController` и
существующие тесты; затем реализовать серверный AI create path и старт
партии. Не переписывать controller целиком до проверки текущих
контрактов.

## Архитектурный инвариант

``` text
Decision Provider → Action → GameActionRunner → GameEngine → GameState
```

Controller организует процесс, provider выбирает действие, Engine
валидирует и применяет его. `VisibleState` ограничивает видимые данные.
UI и AI не применяют правила напрямую.
