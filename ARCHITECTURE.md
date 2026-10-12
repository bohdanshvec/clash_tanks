# ARCHITECTURE.md

## Основной поток

``` text
Decision Provider → Action → GameEngine → GameState
```

`GameEngine` --- единственный арбитр игровых правил.
`GameEngine::Action` содержит `player_id`, `type`, `payload`;
`GameEngine::Result` --- результат, новое состояние и `events`. Исходный
`GameState` не мутируется: операции работают с копией. При ошибке новое
состояние не сохраняется.

Browser flow:

``` text
Browser → Controller → Decision Provider → Action → GameActionRunner → GameEngine → GameState
                                                                          ↓
Browser ← Stimulus ← Turbo ← VisibleState ← GameState
```

Для человека используется `DecisionProviders::Human`, для AI ---
`DecisionProviders::AI`. Все действия проходят через `GameActionRunner`
и `GameEngine`.

## Game и GameState

`Game.state` --- authoritative JSONB snapshot. Основные поля: `status`,
`turn_number`, `current_player_id`, `turn_started_at`, `players`,
`field`, `result`. Состояние игрока содержит `nation_id`, `hand`,
`deck`, `graveyard`, `platoons`, `resources`, `remaining_time`,
`empty_deck_draw_attempts`.

`GameState` не обращается к ActiveRecord. Постоянная `Deck` не
изменяется во время партии. Для `Game(status: waiting)` `state == nil`;
AI-игра должна создаваться и сразу переходить в `started`, не проходя
через waiting room.

Поле `field` хранит HQ и Technique. `Platoon` находится в
`state["players"][player_id]["platoons"]`; четыре slots сохраняют пустые
позиции после уничтожения. Логические координаты state не зависят от
игрока; DOM использует `data-position="row,column"`.

Runtime `Technique` содержит тип, card/player/nation IDs, имя,
характеристики техники и attack flags; не содержит `price`, `weight`,
`card_type` или вложенный `technique`. У `Technique` нет `Armor`.
Runtime `Platoon` содержит firepower, hp, armor и fuel. Точные правила
определяет `GAME_RULES.md`.

## Decision Provider

Provider выбирает намерение, но не применяет правила.

### Base и Context

`DecisionProviders::Base` (`app/services/decision_providers/base.rb`)
задаёт общий интерфейс `call`.

`DecisionProviders::Context`
(`app/services/decision_providers/context.rb`) формирует `player_id`,
`visible_state` через `GameEngine::VisibleState` и `available_actions`.
Контекст и его данные рекурсивно замораживаются. Provider не получает
полный исходный state и не должен видеть скрытые данные противника.

### Human

`DecisionProviders::Human` (`app/services/decision_providers/human.rb`)
преобразует `move`, `attack`, `play_card`, `end_turn` и `surrender` в
`GameEngine::Action`. Контроллер передаёт действие в `GameActionRunner`.

### AI

`DecisionProviders::AI` (`app/services/decision_providers/a_i.rb`):

1.  Передаёт `visible_state` источнику решений.
2.  Проверяет, что ответ --- `Hash`, `type` --- непустая строка, а
    `payload` --- `Hash`.
3.  Рекурсивно преобразует строковые ключи JSON payload в символы.
4.  Создаёт `GameEngine::Action`.
5.  Повторяет запрос при некорректном формате, максимум три попытки.

После трёх неудачных попыток provider сообщает об ошибке. Наличие
provider не означает, что AI уже подключён к игровому lifecycle:
автоматический вызов AI после старта/хода пока не реализован.

Корректный формат не гарантирует допустимость действия. Окончательную
проверку выполняет Engine.

### Adapters

`DecisionProviders::GroqAdapter`
(`app/services/decision_providers/groq_adapter.rb`) использует Groq Chat
Completions API, `GROQ_API_KEY` и `GROQ_MODEL`; текущая модель по
умолчанию --- `openai/gpt-oss-20b`. Поддерживает JSON-ответ и
тестируемый HTTP transport.

`DecisionProviders::OpenAiAdapter`
(`app/services/decision_providers/open_ai_adapter.rb`) ---
альтернативный адаптер, настраиваемый через `OPENAI_API_KEY` и
`OPENAI_MODEL`.

`AI_PROVIDER` выбирает adapter; текущий default --- `groq`, альтернатива
--- `openai`. Адаптеры только получают и разбирают решение: они не
применяют правила и не сохраняют state.

Автоматические тесты не должны делать реальные запросы, требовать ключей
или тратить средства. Использовать fake/mock transport.

## Action и GameActionRunner

`GameEngine::Action` (`app/services/game_engine/action.rb`) содержит
`player_id`, `type`, `payload`; вложенные `Hash` и `Array` рекурсивно
копируются и замораживаются.

`GameActionRunner` (`app/services/game_action_runner.rb`) блокирует
запись игры, использует актуальное состояние, вызывает Engine и
сохраняет только успешный результат. Отклонённое действие не должно
вызывать успешное Turbo-обновление.

``` text
Human / AI → Action → GameActionRunner → GameEngine → GameState
```

Запрещено передавать AI полный скрытый state, напрямую изменять
`Game.state`, переносить игровые правила в provider, считать
`available_actions` заменой серверной валидации или позволять AI
действовать от имени другого игрока.

## VisibleState и AvailableActions

`GameEngine::VisibleState` --- единственный разрешённый источник
представления игры для UI и AI. Собственный игрок получает свою руку;
противник --- только количество карт в руке/колоде/сбросе, публичные
взводы, ресурсы и время. Содержимое и порядок чужих `hand`, `deck` и
`graveyard` не раскрываются.

`GameEngine::AvailableActions` входит в `VisibleState`. UI только
отображает доступные действия. У неактивного игрока и в finished game
actions пусты. Engine в любом случае самостоятельно валидирует Action.

## Модели, Deck и Ability

Основные модели: `Game`, `Player`, `GamePlayer`, `Nation`, `Card`,
`Headquarters`, `Technique`, `Platoon`, `Ability`, `CardAbility`,
`Deck`, `DeckCard`.

`Player` использует `has_secure_password`; имеет `email`, `name`,
`password_digest`, `guest`, `ai`, `last_seen_at`; методы `guest?`,
`registered?`, `ai?`, `display_name`. Отдельные `User`/Devise не
используются.

`Game` имеет статусы `waiting`, `started`, `finished` и режимы `pvp`,
`ai`; игровую логику модель не содержит. `GamePlayer` связывает игру,
игрока, нацию, колоду и штаб.

`Deck` --- постоянная колода; `DeckCard` хранит `quantity`. Вес
считается как сумма `cards.weight * deck_cards.quantity`.
`StarterDecks::Create.call(player)` создаёт три starter Deck для
человека/гостя. Seed не создаёт игроков и колоды.

Способности используют `Card → CardAbility → Ability`, исполнитель ---
`GameEngine::Abilities::Executor`. Не создавать `TechniqueAbility` или
`HeadquartersAbility`.

## Постоянный AI-игрок и его колоды

Миграции добавили `games.mode`, `players.ai` и уникальный частичный
индекс для единственного `Player` с `ai = true`.

`AiPlayers::Setup` (`app/services/ai_players/setup.rb`) идемпотентно
находит/создаёт игрока `ИИ` с email `ai@clash-tanks.local`,
`guest: false`, `ai: true`. При конфликте уникального индекса ищет
существующую запись; если email занят обычным игроком, сообщает об
ошибке.

`AiPlayers::DecksSetup` (`app/services/ai_players/decks_setup.rb`)
создаёт три постоянные колоды:

  Название                           Нация        Вес
  ---------------------------------- ---------- -----
  `ИИ — США: лёгкая техника`         США           13
  `ИИ — СССР: средняя техника`       СССР          22
  `ИИ — Германия: тяжёлая техника`   Германия      28

Повторный вызов не должен создавать дубликаты. Колоды собраны из
существующих карт и штабов; постоянные Deck не меняются во время игры.
`StartGame` копирует и перемешивает карты в state каждой партии.

`Matchmaking::AiDeckSelector`
(`app/services/matchmaking/ai_deck_selector.rb`) ищет полные колоды
AI-игрока, допускает ±10% от веса AI-колоды и при нескольких совпадениях
выбирает ближайший вес. Целочисленные диапазоны человеческого веса:
12--14 для AI 13; 20--24 для AI 22; 26--30 для AI 28. Случайный выбор
пока не реализован.

Проверка на `/play` --- только UI. Сервер обязан повторно проверить
принадлежность и полноту человеческой колоды, режим и наличие
совместимой AI-колоды.

## Engine, events и timers

Ключевые сервисы: `StartGame`, `Draw`, `Turns::PreparePlayer`,
`Resources::FuelCalculator`, actions `Move`, `Attack`, `PlayCard`,
`EndTurn`, `Surrender`, `FinishGame`. Точные эффекты определяются
`GAME_RULES.md`.

Вложенные операции должны сохранять события до `Result.events`, затем
Controller передаёт их Turbo/Stimulus. Все пути завершения используют
`FinishGame` и единый `game_finished`.

`TurnTimer` и `TurnTimerForTurn` отвечают за время. Сервер проверяет
общий timeout до Action; клиентский `game_timer_controller.js`
отображает время и отправляет существующий `end_turn`.

## UI, Turbo и перспектива

Каждый игрок подписывается на `[game, current_player_id]`. После
успешного Action controller строит отдельный `VisibleState` для каждого
игрока и рассылает Turbo update. Полный скрытый state на клиент не
передаётся.

Waiting room использует отдельную подписку и heartbeat; stale cleanup не
должен удалять started/finished игры. Stimulus обрабатывает только
взаимодействие и визуальные события, не игровые правила.

Визуальная перспектива: свой HQ снизу слева, чужой сверху справа; state,
slots и логические координаты не меняются.

## Authentication и matchmaking

Session определяет личность:
`browser session → current_player → GamePlayer → Action.player_id → GameEngine`.
Гость создаётся при `/play`, получает три starter Deck и
переиспользуется сессией. Гость не управляет Deck и не использует
`/statistics`.

PvP `Matchmaking::FindOpponent` ищет waiting games с одним участником,
совместимость веса ±15%, выбирает ближайший вес, затем более старую
игру. `Matchmaking::Join` использует `with_lock`, создаёт второго
`GamePlayer` и вызывает `StartGame`. `CleanupStaleWaitingGames` очищает
только устаревшие waiting games.

## Незавершённая интеграция AI --- Stage 21

На текущей контрольной точке `GamesController#create` разрешает только
`mode == "pvp"` и отклоняет AI-режим. `StartGame` уже запускает игру с
двумя `GamePlayer`, но AI-участник и автоматические AI-ходы ещё не
подключены.

`PagesController#play` формирует `@ai_decks_by_deck_id`. В
`play.html.erb` AI-кнопка для зарегистрированных игроков пока
показывается без проверки совместимости. В ветке стартовых колод `deck`
--- хеш без `id`, а `ensure_guest_player!` может сделать эту ветку
недостижимой; нужно проверить и исправить intended guest flow.

Следующие задачи: 1. Исправить условный показ AI-кнопки. 2. Серверно
валидировать mode, пользовательскую колоду и совместимость. 3. Создать
`Game(mode: "ai")`, два правильных `GamePlayer`, вызвать `StartGame`. 4.
Запускать AI, если он ходит первым, и после хода человека при переходе
хода к AI. 5. Использовать только `VisibleState` нужного игрока и
выполнять все Actions через `GameActionRunner`. 6. Ограничить AI-цикл,
остановить его при смене хода/завершении/ошибке и защититься от
параллельных запусков. 7. Обработать ошибки provider и Engine,
обеспечить Turbo-обновления и отсутствие регрессий PvP/guest. 8.
Добавить тесты и повторить полный `bin/rails test`.

Не создавать AI-игрока или AI-колоду на каждую игру. Redis не вводить
без отдельного архитектурного решения. Реальные API-запросы не
использовать в автоматических тестах.

## Тестирование AI

Использовать fake/mock источники решений и транспорта. Проверять скрытые
данные, правильный `player_id`, отсутствие прямых изменений state, отказ
Engine, ошибки provider, остановку после завершения и отсутствие
параллельных AI-циклов.
