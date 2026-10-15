# ARCHITECTURE.md

## Основной поток

```text
Decision Provider → Action → GameActionRunner → GameEngine → GameState

Browser → Controller → Decision Provider → Action → GameActionRunner → GameEngine → GameState
                                                                          ↓
Browser ← Stimulus ← Turbo ← VisibleState ← сохранённый GameState
```

GameEngine — единственный арбитр игровых правил. `GameEngine::Action` содержит `player_id`, `type`, `payload`. `GameEngine::Result` содержит успех/ошибку, новое состояние и events. Engine работает с копией GameState; при ошибке новое состояние не сохраняется.

Человек использует `DecisionProviders::Human`, AI — `DecisionProviders::AI`. Любое действие проходит через GameActionRunner и GameEngine.

## Game и GameState

`Game.state` — authoritative JSONB snapshot. Основные поля: `status`, `turn_number`, `current_player_id`, `turn_started_at`, `players`, `field`, `result`. Состояние игрока: `nation_id`, `hand`, `deck`, `graveyard`, `platoons`, `resources`, `remaining_time`, `empty_deck_draw_attempts`.

GameState не обращается к ActiveRecord. Постоянная Deck не меняется во время партии. Для waiting `Game.state == nil`; AI-игра создаётся сразу в started, минуя waiting room.

`field` содержит HQ и Technique. Platoon хранится в `state["players"][player_id]["platoons"]`; четыре slots сохраняют пустые позиции после уничтожения. Логические координаты не зависят от визуальной перспективы; DOM использует `data-position="row,column"`.

Runtime Technique содержит тип, идентификаторы, имя, характеристики и флаги атаки; не содержит price, weight, card_type или вложенный technique. У Technique нет Armor. Runtime Platoon содержит firepower, hp, armor, fuel. Правила — только GAME_RULES.md.

## Decision Provider

Provider выбирает намерение, но не применяет игровые правила.

### Base и Context

`DecisionProviders::Base` задаёт интерфейс `call`. `DecisionProviders::Context` формирует `player_id`, `visible_state` через `GameEngine::VisibleState` и available actions. Контекст рекурсивно заморожен. Provider не получает полный скрытый state.

### Human

`DecisionProviders::Human` преобразует move, attack, play_card, end_turn, surrender в `GameEngine::Action`. Controller передаёт действие в GameActionRunner.

### AI

`DecisionProviders::AI` проверяет Hash-ответ, непустой type, Hash-payload, рекурсивно нормализует ключи JSON и создаёт Action. При некорректном формате допускается до трёх попыток (`MAX_ATTEMPTS = 3`). Формат не заменяет проверку допустимости в Engine.

### Groq и OpenAI

`DecisionProviders::GroqAdapter` использует Groq Chat Completions API, `GROQ_API_KEY`, `GROQ_MODEL` (по умолчанию `openai/gpt-oss-20b`). `DecisionProviders::ActionOptions` готовит индексируемые `legal_actions`. Модели передаётся только видимое состояние без повторного `available_actions` и список разрешённых действий. Модель возвращает JSON `action_index`; адаптер валидирует индекс и выбирает **исходное** разрешённое действие, не создавая произвольный Action.

Актуальная конфигурация Groq:

- Structured Outputs: строгая JSON-схема ответа с `action_index`.
- `reasoning_effort=low`.
- `max_completion_tokens=512`.
- Подменяемый HTTP transport для тестов.
- Логи `prompt_tokens`, `completion_tokens`, `reasoning_tokens`, `total_tokens`, `finish_reason` и диагностика HTTP/rate-limit headers.
- Ограниченные повторы HTTP 429 при распознанной положительной задержке; ограниченная обработка временных сетевых ошибок.
- Если доступно ровно одно допустимое действие, адаптер возвращает его без запроса к API.
- Стратегическая инструкция `INSTRUCTIONS` оставлена без сокращения по решению пользователя.

Исторически наблюдались HTTP 429 из-за TPM и HTTP 400 `json_validate_failed` в прежней конфигурации. Structured Outputs и ограничение completion tokens успешно работали в полноценной браузерной партии; это не означает, что сетевые ошибки и лимиты полностью устранены. Дальнейшая оптимизация token usage или устойчивости может быть выполнена отдельно.

Временное development-логирование полного request payload не следует оставлять включённым: оно выводит всё состояние запроса, включая руку AI и legal actions, и создаёт объёмные логи. Предпочтительны usage-метрики и HTTP/rate-limit диагностика.

`DecisionProviders::OpenAiAdapter` — альтернатива через `OPENAI_API_KEY` и `OPENAI_MODEL`. `AI_PROVIDER` выбирает адаптер, default — groq. Адаптеры не применяют правила и не сохраняют state. Автоматические тесты используют fake/mock transport, не обращаются к реальным API и не требуют ключей.

## Action и GameActionRunner

`GameEngine::Action` содержит `player_id`, `type`, `payload`; вложенные Hash/Array копируются и замораживаются. GameActionRunner блокирует игру, сверяет `expected_state_digest` с актуальным состоянием, вызывает Engine и сохраняет только успешный результат. Отказанный или устаревший Action не должен менять state и вызывать успешный Turbo broadcast.

Нельзя давать AI скрытый state, изменять `Game.state` напрямую, переносить правила в provider или позволять AI действовать от имени другого игрока.

## VisibleState и AvailableActions

`GameEngine::VisibleState` — разрешённая граница данных UI/AI. Игрок видит свою руку; противник — только количества карт в руке/колоде/сбросе и публичные объекты/ресурсы/время. Содержимое и порядок чужих hand/deck/graveyard скрыты. AvailableActions входит в VisibleState; у неактивного игрока и finished game действий нет. Engine всё равно самостоятельно валидирует Action.

`GameEngine::AvailableActions` формирует серверные подсказки для перемещений, атак, размещения техники, взводов и приказов. Эти данные не заменяют проверку действия в Engine и не должны дублироваться внутри `game_state` запроса Groq, когда `legal_actions` уже переданы отдельно.

## Модели, Deck и Ability

Модели: Game, Player, GamePlayer, Nation, Card, Headquarters, Technique, Platoon, Ability, CardAbility, Deck, DeckCard.

Player использует `has_secure_password`, поля email, name, password_digest, guest, ai, last_seen_at, методы `guest?`, `registered?`, `ai?`, `display_name`. Отдельные User/Devise отсутствуют.

Game имеет waiting, started, finished и режимы pvp, ai. GamePlayer связывает игру, игрока, нацию, колоду и штаб. DeckCard хранит quantity, вес Deck — сумма `card.weight * quantity`. `StarterDecks::Create.call(player)` создаёт три starter Deck; seed не создаёт игроков/колоды. Способности: Card → CardAbility → Ability → GameEngine::Abilities::Executor; не создавать TechniqueAbility или HeadquartersAbility.

## Постоянный AI-игрок и колоды

`AiPlayers::Setup` идемпотентно находит/создаёт единственного Player с `ai: true`, email `ai@clash-tanks.local`; частичный уникальный индекс не допускает второго. Если email занят обычным игроком, возвращается ошибка.

`AiPlayers::DecksSetup` идемпотентно готовит три полные колоды:

| Название | Нация | Вес |
|---|---|---:|
| ИИ — США: лёгкая техника | США | 13 |
| ИИ — СССР: средняя техника | СССР | 22 |
| ИИ — Германия: тяжёлая техника | Германия | 28 |

StartGame копирует/перемешивает карты в state новой партии, постоянные Deck не изменяются. `Matchmaking::AiDeckSelector` ищет полные колоды в допуске ±10%, выбирает ближайший вес. Целочисленные диапазоны человеческого веса: 12–14, 20–24, 26–30 соответственно.

## Engine, events и timers

Основные сервисы: StartGame, Draw, Turns::PreparePlayer, Resources::FuelCalculator, Move, Attack, PlayCard, EndTurn, Surrender, FinishGame. Вложенные операции сохраняют события до `Result.events`; завершение игры использует единый `game_finished`. TurnTimer и TurnTimerForTurn отвечают за время; сервер проверяет общий timeout до Action, клиентский `game_timer_controller.js` отображает время и вызывает существующий end_turn.

## Games::RunAiTurns — автоматический цикл

`app/services/games/run_ai_turns.rb`:

- Максимум 20 действий за запуск (`MAX_ACTIONS_PER_RUN`).
- PostgreSQL advisory lock предотвращает параллельные AI-циклы одной игры; независимые игры не блокируют друг друга.
- До трёх повторов stale state (`MAX_STALE_STATE_RETRIES`).
- Перед каждым решением перечитывает Game и проверяет status/current player/лимит.
- Действия проходят `DecisionProviders::AI → GameActionRunner → GameEngine`.
- Прекращает цикл при завершении, смене хода, ошибке или лимите; ранее сохранённые действия не откатываются при последующей ошибке.
- Необязательный callback `on_action` получает events отдельного успешного действия **после его сохранения**. Callback не должен изменять state или содержать игровые правила. Тест проверяет, что состояние уже сохранено к моменту вызова.

## UI, Turbo и перспектива — пошаговый AI broadcast

Каждый участник подписан на `[game, current_player_id]`. `GamesController#broadcast_game_update(events)` формирует **отдельный VisibleState для каждого игрока** и отправляет Turbo update в `game-content`; скрытый полный state не передаётся браузеру.

Проверенный flow после человеческого действия:

```text
Human Action
  → GameActionRunner (validate/apply/save)
  → @game.reload
  → broadcast_game_update(human_events) для каждого игрока
  → run_ai_turns_if_needed(broadcast_each_action: true)
       → Games::RunAiTurns
       → AI Action → GameActionRunner (save)
       → on_action(action_events)
            → @game.reload
            → broadcast_game_update(action_events) для каждого игрока
       → следующее AI Action → ...
  → @game.reload → respond_after_success
```

`GamesController#show` также запускает AI с `broadcast_each_action: true`, если при открытии started-игры ход принадлежит AI. `run_ai_turns_if_needed` логирует ошибки и не отменяет уже сохранённые действия.

**Важно:** не возвращаться к схеме «накопить события всех AI-действий и отправить один broadcast в конце». Не помещать Turbo в GameActionRunner, Engine или provider. Controller организует рассылку, Engine отвечает за правила. AI выполняется синхронно; callback сам по себе не гарантирует визуальной паузы между действиями.

Контроллерные тесты подтверждают отдельные broadcasts для attack и end_turn: два действия × два адресата = четыре отправки. Проверяются события/состояния каждого шага и отсутствие скрытой руки. Пользователь подтвердил в браузере последовательное отображение действий и завершение полноценной партии, включая поражение от урона пустой колоды.

Waiting room использует отдельную подписку и heartbeat; stale cleanup не удаляет started/finished игры. Stimulus отвечает за ввод и визуальные события, не правила. Перспектива: свой HQ снизу слева, чужой сверху справа; state и логические координаты не меняются.

## Authentication и matchmaking

```text
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

Гость создаётся при `/play`, получает три starter Deck, переиспользуется в сессии; не управляет Deck и не использует `/statistics`. PvP `Matchmaking::FindOpponent` ищет waiting games с одним участником, совместимость веса ±15%, выбирает ближайший вес, затем более старую игру. `Matchmaking::Join` использует `with_lock`, создаёт второго GamePlayer и вызывает StartGame. `CleanupStaleWaitingGames` очищает только устаревшие waiting games.

## Статус Stage 21

**Stage 21 — AI в игровом процессе — завершён по решению пользователя.** Подтверждены автоматические тесты, последовательный Turbo broadcast и полноценная браузерная партия с реальным Groq. Пользователь решил оставить системную инструкцию без сокращения. Возможные будущие улучшения надёжности Groq, оптимизации токенов, стратегии или дополнительных браузерных edge cases не являются блокерами завершения Stage 21; если потребуется, к ним можно вернуться отдельно.

Последние подтверждённые результаты:

```text
GroqAdapterTest: 23 runs, 62 assertions, 0 failures, 0 errors, 0 skips
Full suite:      534 runs, 2029 assertions, 0 failures, 0 errors, 0 skips
```

## Тестирование AI

Fake/mock источники решений и HTTP transport. Проверять скрытые данные, правильный `player_id`, отсутствие прямой мутации state, отказ Engine, stale state, ошибки provider, сохранение частичных результатов, остановку цикла, advisory lock и отдельный broadcast после каждого успешного действия. Реальный API — только при отдельной ручной проверке.
