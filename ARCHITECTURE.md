# ARCHITECTURE.md

## Основной поток

```text
Decision Provider → Action → GameActionRunner → GameEngine → GameState

Browser → Controller → Decision Provider → Action → GameActionRunner → GameEngine → GameState
                                                                          ↓
Browser ← Stimulus ← Turbo ← VisibleState ← сохранённый GameState
```

GameEngine — единственный арбитр игровых правил. `GameEngine::Action` содержит `player_id`, `type`, `payload`. `GameEngine::Result` содержит успех или ошибку, новое состояние и events. Engine работает с копией GameState; при ошибке новое состояние не сохраняется.

Человек использует `DecisionProviders::Human`, AI — `DecisionProviders::AI`. Любое действие проходит через GameActionRunner и GameEngine.

## Язык пользовательского интерфейса

Игра ориентирована на украинскую аудиторию. Основной язык пользовательского интерфейса — украинский.

Украинскими должны быть заголовки страниц, кнопки, подписи полей, сообщения об ошибках и валидации, инструкции и другой текст, видимый игроку. При исправлении ERB-шаблонов или CSS не переводить существующий интерфейс на русский без прямого указания пользователя.

Язык технической документации и общения с пользователем не определяет язык UI: документация может оставаться на русском.

## Game и GameState

`Game.state` — authoritative JSONB snapshot. Основные поля: `status`, `turn_number`, `current_player_id`, `turn_started_at`, `players`, `field`, `result`. Состояние игрока: `nation_id`, `hand`, `deck`, `graveyard`, `platoons`, `resources`, `remaining_time`, `empty_deck_draw_attempts`.

GameState не обращается к ActiveRecord. Постоянная Deck не меняется во время партии. Для waiting `Game.state == nil`; AI-игра создаётся сразу в started, минуя waiting room.

`field` содержит HQ и Technique. Platoon хранится в `state["players"][player_id]["platoons"]`; четыре slots сохраняют пустые позиции после уничтожения. Логические координаты не зависят от визуальной перспективы; DOM использует `data-position="row,column"`.

Runtime Technique содержит тип, идентификаторы, имя, характеристики и флаги атаки; не содержит price, weight, card_type или вложенный technique. У Technique нет Armor. Runtime Platoon содержит firepower, hp, armor, fuel. Правила — только `GAME_RULES.md`.

## Decision Provider

Provider выбирает намерение, но не применяет игровые правила.

### Base и Context

`DecisionProviders::Base` задаёт интерфейс `call`. `DecisionProviders::Context` формирует `player_id`, `visible_state` через `GameEngine::VisibleState` и available actions. Контекст рекурсивно заморожен. Provider не получает полный скрытый state.

### Human

`DecisionProviders::Human` преобразует move, attack, play_card, end_turn, surrender в `GameEngine::Action`. Controller передаёт действие в GameActionRunner.

### AI

`DecisionProviders::AI` проверяет Hash-ответ, непустой type, Hash-payload, рекурсивно нормализует ключи JSON и создаёт Action. При некорректном формате допускается до трёх попыток (`MAX_ATTEMPTS = 3`). Формат не заменяет проверку допустимости в Engine.

### Groq и OpenAI

`DecisionProviders::GroqAdapter` использует Groq Chat Completions API, `GROQ_API_KEY`, `GROQ_MODEL` (по умолчанию `openai/gpt-oss-20b`). `DecisionProviders::ActionOptions` готовит индексируемые `legal_actions`. Модели передаётся только видимое состояние без повторного `available_actions` и список разрешённых действий. Модель возвращает JSON `action_index`; адаптер валидирует индекс и выбирает исходное разрешённое действие, не создавая произвольный Action.

Актуальная конфигурация Groq:

- Structured Outputs: строгая JSON-схема ответа с `action_index`.
- `reasoning_effort=low`.
- `max_completion_tokens=512`.
- Подменяемый HTTP transport для тестов.
- Логирование token usage, `finish_reason` и доступных HTTP/rate-limit метрик.
- Ограниченные повторы HTTP 429 при распознанной положительной задержке; ограниченная обработка временных сетевых ошибок.
- Если доступно ровно одно допустимое действие, адаптер возвращает его без запроса к API.
- Стратегическая инструкция `INSTRUCTIONS` оставлена без сокращения по решению пользователя.

Исторически наблюдались HTTP 429 из-за TPM и HTTP 400 `json_validate_failed` в прежней конфигурации. Успешная браузерная партия подтверждает работоспособность проверенного сценария, но не исключает будущие сетевые ошибки или ограничения API.

Не оставлять включённым подробное логирование полного request payload: оно может раскрывать руку AI и разрешённые действия. Предпочтительны token usage, классы ошибок и HTTP/rate-limit диагностика без тел запросов и ответов.

`DecisionProviders::OpenAiAdapter` — альтернатива через `OPENAI_API_KEY` и `OPENAI_MODEL`. `AI_PROVIDER` выбирает адаптер, default — groq. Адаптеры не применяют правила и не сохраняют state. Автоматические тесты используют fake/mock transport, не обращаются к реальным API и не требуют ключей.

## Action и GameActionRunner

`GameEngine::Action` содержит `player_id`, `type`, `payload`; вложенные Hash/Array копируются и замораживаются. GameActionRunner блокирует игру, сверяет `expected_state_digest` с актуальным состоянием, вызывает Engine и сохраняет только успешный результат. Отказанный или устаревший Action не должен менять state и вызывать успешный Turbo broadcast.

Нельзя давать AI скрытый state, изменять `Game.state` напрямую, переносить правила в provider или позволять AI действовать от имени другого игрока.

## VisibleState и AvailableActions

`GameEngine::VisibleState` — разрешённая граница данных UI/AI. Игрок видит свою руку; противник — только количества карт в руке/колоде/сбросе и публичные объекты, ресурсы и время. Содержимое и порядок чужих hand/deck/graveyard скрыты. AvailableActions входит в VisibleState; у неактивного игрока и finished game действий нет. Engine всё равно самостоятельно валидирует Action.

`GameEngine::AvailableActions` формирует серверные подсказки для перемещений, атак, размещения техники, взводов и приказов. Эти данные не заменяют проверку действия в Engine и не должны дублироваться внутри `game_state` запроса Groq, когда `legal_actions` уже переданы отдельно.

## Модели, Deck и Ability

Модели: Game, Player, GamePlayer, Nation, Card, Headquarters, Technique, Platoon, Ability, CardAbility, Deck, DeckCard.

Player использует `has_secure_password`, поля email, name, password_digest, guest, ai, last_seen_at, методы `guest?`, `registered?`, `ai?`, `display_name`. Отдельные User/Devise отсутствуют.

Game имеет waiting, started, finished и режимы pvp, ai. GamePlayer связывает игру, игрока, нацию, колоду и штаб. DeckCard хранит quantity; вес Deck — сумма `card.weight * quantity`. `StarterDecks::Create.call(player)` создаёт три starter Deck; seed не создаёт игроков и колоды. Способности: Card → CardAbility → Ability → GameEngine::Abilities::Executor; не создавать TechniqueAbility или HeadquartersAbility.

## Карты, штаб и колоды

Каталог карт определяется seed-файлами, в частности `db/seeds/cards.rb`, а характеристики карт документируются в `CARDS.md`.

Сиды должны обновлять существующие карты по стабильному `code`, чтобы повторный запуск применял актуальные характеристики, а не оставлял старые значения.

Каждый штаб имеет собственный уникальный `code`. Код идентифицирует конкретную карту штаба, а не только нацию. Это позволяет в дальнейшем добавить несколько штабов одной нации. При изменении кодов штабов необходимо синхронно обновлять сервисы, которые выбирают штаб по коду, включая `StarterDecks::Create` и `AiPlayers::DecksSetup`.

Стартовые колоды гостя создаются сервисом `StarterDecks::Create`. Постоянные колоды AI подготавливаются сервисом `AiPlayers::DecksSetup`. Составы и характеристики этих колод должны соответствовать существующим картам и правилам валидации Deck.

`Deck::DECK_SIZE` определяет размер колоды. Вес Deck вычисляется динамически из весов выбранных карт и их количества; штаб не включается в обычную сумму веса колоды. Количество копий одной карты ограничено правилами модели DeckCard.

## Постоянный AI-игрок и колоды

`AiPlayers::Setup` идемпотентно находит или создаёт единственного Player с `ai: true`, email `ai@clash-tanks.local`; частичный уникальный индекс не допускает второго. Если email занят обычным игроком, возвращается ошибка.

`AiPlayers::DecksSetup` готовит постоянные AI-колоды на основе существующих карт. Колоды используются повторно между партиями и не создаются заново на каждую игру.

Сервис может возвращать уже существующую колоду по игроку и названию. При изменении состава существующих AI-колод необходимо учитывать это поведение: повторный вызов сам по себе не обязательно обновит уже сохранённый состав.

`Matchmaking::AiDeckSelector` выбирает полную совместимую колоду в пределах ±10% веса и при нескольких совпадениях предпочитает ближайший вес. Фактические веса определяются актуальными характеристиками карт и составами колод; не фиксировать в документации устаревшие значения.

## Engine, events и timers

Основные сервисы: StartGame, Draw, Turns::PreparePlayer, Resources::FuelCalculator, Move, Attack, PlayCard, EndTurn, Surrender, FinishGame. Вложенные операции сохраняют события до `Result.events`; завершение игры использует единый `game_finished`. TurnTimer и TurnTimerForTurn отвечают за время; сервер проверяет общий timeout до Action, клиентский `game_timer_controller.js` отображает время и вызывает существующий end_turn.

## Games::RunAiTurns — автоматический цикл

`app/services/games/run_ai_turns.rb`:

- Максимум 20 действий за запуск (`MAX_ACTIONS_PER_RUN`).
- PostgreSQL advisory lock предотвращает параллельные AI-циклы одной игры; независимые игры не блокируют друг друга.
- До трёх повторов stale state (`MAX_STALE_STATE_RETRIES`).
- Перед каждым решением перечитывает Game и проверяет status, current player и лимит.
- Действия проходят `DecisionProviders::AI → GameActionRunner → GameEngine`.
- Прекращает цикл при завершении, смене хода, ошибке или лимите; ранее сохранённые действия не откатываются при последующей ошибке.
- Необязательный callback `on_action` получает events отдельного успешного действия после его сохранения. Callback не должен изменять state или содержать игровые правила.

## UI, Turbo и перспектива — пошаговый AI broadcast

Каждый участник подписан на `[game, current_player_id]`. `GamesController#broadcast_game_update(events)` формирует отдельный VisibleState для каждого игрока и отправляет Turbo update в `game-content`; скрытый полный state не передаётся браузеру.

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

Не возвращаться к схеме «накопить события всех AI-действий и отправить один broadcast в конце». Не помещать Turbo в GameActionRunner, Engine или provider. Controller организует рассылку, Engine отвечает за правила. AI выполняется синхронно; callback сам по себе не гарантирует визуальной паузы между действиями.

## Редактор колод

Редактор использует ERB-шаблоны и Stimulus для ввода количества карт и отображения сводных характеристик.

Текущие UI-решения:

- На странице списка колод кнопка создания размещается рядом с заголовком «Колоди».
- В редакторе колоды поле названия, штаб и действия сохранения/отмены находятся в верхней области.
- Кнопки «Зберегти колоду» и «Відміна» располагаются в одном ряду с основными полями, насколько позволяет ширина экрана.
- Карты сортируются по типу: `technique`, затем `order`, затем `platoon`; внутри типа — по весу и названию.
- Список карт использует перенос строк при недостаточной ширине, без искусственного растягивания карточек по вертикали.
- Все видимые надписи интерфейса — на украинском языке.

Изменения оформления не должны менять правила Deck, доступные действия или GameState.

## Authentication и matchmaking

```text
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

Гость создаётся при `/play`, получает три starter Deck и переиспользуется в сессии; не управляет Deck и не использует `/statistics`. PvP `Matchmaking::FindOpponent` ищет waiting games с одним участником, совместимость веса ±15%, выбирает ближайший вес, затем более старую игру. `Matchmaking::Join` использует `with_lock`, создаёт второго GamePlayer и вызывает StartGame. `CleanupStaleWaitingGames` очищает только устаревшие waiting games.

## Статус Stage 21 и Stage 22

Stage 21 — AI в игровом процессе — завершён по решению пользователя. Последовательный Turbo broadcast и полноценная браузерная партия с реальным Groq проверены.

Stage 22 — дополнительная надёжность AI и корректировка диагностического логирования — завершён по решению пользователя. Последний подтверждённый полный набор после изменений логирования:

```text
534 runs, 2031 assertions, 0 failures, 0 errors, 0 skips
```

## Статус Stage 23

Stage 23 — каталог карт, характеристики и вес, стартовые колоды гостя, постоянные колоды AI и UI редактора колод — завершён по решению пользователя.

В ходе этапа обновлён каталог seed-карт, выделены уникальные коды штабов, синхронизированы ссылки в сервисах создания колод и исправлен интерфейс редактора. Подробный каталог карт и характеристики должны соответствовать `CARDS.md` и актуальному коду. Последующие UI-изменения требуют отдельной проверки после их применения.

## Тестирование AI

Fake/mock источники решений и HTTP transport. Проверять скрытые данные, правильный `player_id`, отсутствие прямой мутации state, отказ Engine, stale state, ошибки provider, сохранение частичных результатов, остановку цикла, advisory lock и отдельный broadcast после каждого успешного действия. Реальный API — только при отдельной ручной проверке.
