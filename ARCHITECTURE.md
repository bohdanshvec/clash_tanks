# ARCHITECTURE

## Основной поток

```
Decision Provider → Action → GameEngine → GameState
```

`GameEngine` — единственный арбитр игровых правил. `GameEngine::Action` содержит `player_id`, `type`, `payload` и описывает намерение выполнить действие. `GameEngine::Result` содержит результат выполнения, новый `GameState` и `events`.

Исходный `GameState` не мутируется: операции работают с копией состояния. При ошибке новое состояние не сохраняется.

Полный browser flow:

```
Browser → Controller → Decision Provider → Action → GameEngine → GameState
                                                   ↓
Browser ← Stimulus ← Turbo ← VisibleState ← GameState
```

Для человека источник решения — `DecisionProviders::Human`. Для AI используется `DecisionProviders::AI`, который получает разрешённое представление состояния и формирует `Action`.

Все действия, независимо от источника, проходят через `GameEngine`. Наличие AI не меняет игровые правила и не предоставляет AI права самостоятельно изменять состояние партии.

## Game, GameState и runtime-объекты

`Game.state` — authoritative JSONB snapshot, единственный сохранённый источник актуального игрового состояния.

Основные поля:

- `status`;
- `turn_number`;
- `current_player_id`;
- `turn_started_at`;
- `players`;
- `field`;
- `result`.

Состояние игрока содержит `nation_id`, `hand`, `deck`, `graveyard`, `platoons`, `resources`, `remaining_time`, `empty_deck_draw_attempts`.

`GameState` не обращается к ActiveRecord. Постоянная колода `Deck` не изменяется во время партии.

Для `Game(status: waiting)` всегда `state == nil`: `GameState` не создаётся, а ожидание и его metadata находятся вне игровых правил.

Поле `field` хранит HQ и Technique. `Platoon` находится в `state["players"][player_id]["platoons"]`. У каждого игрока четыре slots `[nil, nil, nil, nil]`; уничтоженный взвод оставляет `nil`, slots не уплотняются.

Логические координаты state не зависят от игрока. DOM хранит их в `data-position="row,column"`.

Runtime `Technique` содержит `type`, `card_id`, `player_id`, `nation_id`, `name`, `technique_type`, `hp`, `firepower`, `fuel`, `attack_range`, `movement_count`, `movement_limit`, `movement_type` и attack flags.

В runtime `Technique` нет `price`, `weight`, `card_type` и вложенного `technique`. У `Technique` нет `Armor`.

Runtime `Platoon` содержит `type`, `card_id`, `player_id`, `nation_id`, `name`, `firepower`, `hp`, `armor`, `fuel`. Отсутствующий, `nil` или `0` armor трактуется как `0`.

Точные правила размеров поля, движения, боя, ресурсов и состава состояния определяет `GAME_RULES.md`.

## Decision Provider

Decision Provider отделяет выбор действия от выполнения игровых правил.

Основной контракт:

```
Decision Provider → GameEngine::Action → GameEngine
```

Provider отвечает только за формирование намерения. Проверять допустимость и применять действие обязан `GameEngine`.

### Базовый класс

`DecisionProviders::Base` находится в:

```
app/services/decision_providers/base.rb
```

Базовый класс предоставляет общий интерфейс `call`. Конкретный provider реализует этот метод и возвращает `GameEngine::Action`.

Новый provider должен подключаться через существующую архитектурную границу, без переноса игровых правил в него и без изменения правил `GameEngine`.

### Context

`DecisionProviders::Context` находится в:

```
app/services/decision_providers/context.rb
```

`Context` формирует контекст решения для конкретного игрока:

- `player_id`;
- `visible_state`, полученный через `GameEngine::VisibleState`;
- `available_actions`, доступные игроку.

Полученное представление состояния рекурсивно замораживается. Сам `Context` также замораживается.

Provider не должен получать полный исходный `GameState`, обращаться к скрытым данным противника или изменять сохранённое состояние игры.

### Human

`DecisionProviders::Human` находится в:

```
app/services/decision_providers/human.rb
```

`Human` преобразует ввод игрока в `GameEngine::Action`.

В текущей реализации `GamesController` создаёт `Human` provider для действий:

- `move`;
- `attack`;
- `play_card`;
- `end_turn`;
- `surrender`.

Далее действие передаётся в общий путь выполнения через `GameActionRunner` и `GameEngine`.

`Human` provider не применяет игровые правила. Проверка допустимости действия остаётся ответственностью Engine.

### AI

`DecisionProviders::AI` находится в:

```
app/services/decision_providers/a_i.rb
```

AI получает `Context` с разрешённым `VisibleState` и использует источник решений, чтобы выбрать действие.

Текущая реализация:

1. Передаёт `visible_state` источнику решений.
2. Проверяет, что решение представлено `Hash`.
3. Проверяет наличие непустого строкового `type`.
4. Проверяет, что `payload` — `Hash`.
5. Рекурсивно преобразует строковые ключи JSON payload в символы, совместимые с существующими обработчиками действий.
6. Создаёт `GameEngine::Action`.
7. Повторяет запрос при некорректном формате решения, но не более трёх попыток.

После трёх неудачных попыток AI сообщает об ошибке. Он не должен самостоятельно изменять `GameState` или обходить Engine.

> **Важно:** корректный формат решения ещё не гарантирует допустимость игрового действия. Окончательную проверку выполняет `GameEngine`.

### OpenAI adapter

`DecisionProviders::OpenAiAdapter` находится в:

```
app/services/decision_providers/open_ai_adapter.rb
```

Адаптер подготовлен для получения решения через OpenAI Responses API.

Он:

- передаёт модели инструкции и JSON разрешённого состояния;
- просит вернуть JSON с `type` и `payload`;
- разбирает JSON-ответ;
- поддерживает выбор модели через `OPENAI_MODEL`;
- по умолчанию использует `gpt-4.1-mini`;
- получает ключ из `OPENAI_API_KEY`;
- сообщает об ошибке конфигурации, если ключ отсутствует;
- ограничивает время запроса и количество автоматических повторов на уровне клиента.

Адаптер не применяет действия и не обращается к `GameState` напрямую.

Тесты адаптера используют тестовые объекты и заглушки. Полный набор тестов не должен требовать реального API-ключа, подключения к OpenAI или платных запросов.

Наличие адаптера не означает, что AI уже полностью подключён к игровому процессу. Подключение выбора режима AI, вызова provider и обработки его результата в реальной партии проверяется на последующих этапах.

## Action и неизменяемость

`GameEngine::Action` находится в:

```
app/services/game_engine/action.rb
```

`Action` содержит `player_id`, `type` и `payload`.

Объект `Action`, вложенные `Hash` и `Array` его payload рекурсивно копируются и замораживаются. Поэтому изменение исходного payload после создания `Action` не изменяет действие, а вложенные данные `Action` нельзя изменить через ссылки на его содержимое.

`Action` описывает намерение и не является подтверждением допустимости действия.

## Безопасность и единая валидация

Для всех источников действует единый путь:

```
Human / AI / другой Provider
             ↓
       GameEngine::Action
             ↓
       GameActionRunner
             ↓
        GameEngine
             ↓
         GameState
```

Запрещено:

- передавать AI полный скрытый `GameState`;
- раскрывать AI содержимое чужой руки или колоды;
- позволять provider напрямую сохранять изменения в `Game.state`;
- переносить игровые правила из Engine в AI;
- считать `available_actions` заменой серверной валидации;
- разрешать AI выбирать действия другого игрока;
- обходить проверки завершённой партии, таймеров, ресурсов, целей и позиций.

Если решение AI недопустимо, Engine должен отклонить его в соответствии с существующими правилами.

## VisibleState и AvailableActions

`GameEngine::VisibleState` (`app/services/game_engine/visible_state.rb`) — единственный разрешённый источник игрового представления для UI и AI.

Он не мутирует `GameState`, передаёт `result` завершённой игры и не преобразует координаты.

Собственный игрок получает полную руку, количество карт в колоде и сбросе, взводы, ресурсы и оставшееся время.

Противник получает только количество карт в руке, колоде и сбросе, публичные взводы, ресурсы и оставшееся время. Содержимое и порядок чужих `hand`/`deck`/`graveyard` не раскрываются. Resources публичны.

`GameEngine::AvailableActions` рассчитывается сервером и входит в `VisibleState`. Stimulus только отображает доступные действия.

Поддерживаются `moves`/`attacks` Technique, `attacks` HQ, `resources` и `positions` Technique card, `resources`/`targets`/`drop zone` Order, `resources`/`free slots` Platoon.

`resources_sufficient: false` означает только недостаток ресурсов: отсутствие позиции, цели или slot само по себе карту не приглушает.

У неактивного игрока и в finished game actions пусты. DOM-взвод идентифицируется сочетанием `data-platoon-slot` и `data-player-id`.

## ActiveRecord, Deck и Ability

Основные модели: `Game`, `Player`, `GamePlayer`, `Nation`, `Card`, `Headquarters`, `Technique`, `Platoon`, `Ability`, `CardAbility`, `Deck`, `DeckCard`.

`Player` использует `has_secure_password`, имеет `email`, `name`, `password_digest`, `guest`, `last_seen_at`; `email` уникален. Методы: `guest?`, `registered?`, `display_name`.

Гость остаётся обычным `Player` с обычным `player_id`. У `Player` нет `dependent: :destroy` для `game_players`, чтобы не уничтожать историю автоматически.

`Game` имеет статусы `waiting`, `started`, `finished`, но игровой логики не содержит. `Game.last_seen_at` — техническая активность waiting room, не часть `GameState`.

`Deck` — постоянная колода; `DeckCard` хранит `quantity`. Ограничения `Deck`, Weight и состав starter Deck определяются правилами. Реализация использует единый `DECK_SIZE`, `Deck#card_count`, `Deck#complete?` и `StarterDecks::Create::STARTER_DECKS`.

`StarterDecks::Create.call(player)` создаёт три постоянные колоды при регистрации и создании гостя в общей transaction. Seed не создаёт игроков или колоды.

Способности имеют единую цепочку `Card → CardAbility → Ability`. Исполнитель — `GameEngine::Abilities::Executor`; каждая новая ability получает отдельный handler.

Не создавать `TechniqueAbility` и `HeadquartersAbility`.

## Engine-операции и события

Ключевые сервисы: `StartGame`, `Cards::Draw`, `Turns::PreparePlayer`, `Resources::FuelCalculator`, actions `Move`, `Attack`, `PlayCard`, `EndTurn`, `Surrender`, а также `FinishGame`. Точные игровые эффекты находятся в `GAME_RULES.md`.

События не должны теряться во вложенных операциях:

```
Draw → DrawCards/PreparePlayer → EndTurn/PlayCard → Result.events → GamesController → Turbo/Stimulus
```

`PreparePlayer` возвращает draw events; `EndTurn` добавляет их к своим; `PlayCard#play_order` собирает events всех ability через `events.concat(result.events)`.

Все пути завершения используют `FinishGame` и единый `game_finished`; отдельную систему victory/surrender не создавать.

Таймеры реализованы `TurnTimer` и `TurnTimerForTurn`. Сервер проверяет общий timeout до Action; клиентский `game_timer_controller.js` только показывает время и при окончании turn timer посылает существующий `end_turn`.

## UI, Turbo и перспектива

Stage 15 — функциональный browser vertical slice, не финальный production UI.

Каждый игрок подписывается на `turbo_stream_from [@game, current_player_id]`. После успешного Action `GamesController` сохраняет state, строит отдельный `GameEngine::VisibleState` для каждого игрока, передаёт events в partial и рассылает обновление.

Полный скрытый `GameState` на клиент не передаётся.

Waiting room имеет отдельную подписку на `Game` и refresh при создании/удалении waiting game, Join и stale cleanup.

Game events дают только визуальные реакции: `move` flash'ит обе клетки, `attack` — участников, `empty_deck_draw_attempt` — HQ нужного игрока, `platoon_played` — комбинацию player/slot. CSS-класс `.game-event--flash` не является игровой логикой.

Click, hover, selection и Drag & Drop используют `.game-action--card`, `.game-action--card-target`, `.game-action--drop-zone`; platoon bar — drop zone, но slot не передаётся в Action.

Finished UI получает пустые actions, приглушает content через `.game-content--muted`, сохраняя видимым результат.

View определяет current/opponent по `current_player_id`: свой HQ снизу слева, чужой сверху справа; свои Platoon слева, рука снизу. Если свой HQ не в `[2][0]`, View разворачивает порядок строк и колонок. State, порядок slots и hand не меняются; Stimulus не преобразует координаты.

## Authentication и routes

`Player` одновременно аккаунт и игровая сущность; отдельные `User`/Devise не используются. Session определяет личность, но не `GameState`:

```
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

Используются `RegistrationsController`, `SessionsController`, `has_secure_password` и `reset_session` при logout.

Гость создаётся только при `/play`, получает три starter Deck и переиспользуется сессией. Публичный `/decks` гостя не создаёт.

Гость не создаёт, не меняет и не удаляет `Deck` и не имеет `/statistics`, но игра использует тот же `Player`/`GamePlayer`/Engine.

Публичные страницы: `/`, `/rules`, `/play`, `/decks`, `/cards`; `/statistics` — только зарегистрированному.

Development-only `bin/rails dev:create_game` создаёт новые тестовые `Deck`/`Game` для `dev.player1@example.com` и `dev.player2@example.com` (пароль `password`), но не является пользовательским lifecycle.

Game routes: `create`, `show`, `end_turn`, `play_card`, `move`, `attack`, `surrender`, `cancel_waiting`, `waiting_heartbeat`. Полный список находится в `config/routes.rb`.

## Matchmaking и waiting lifecycle

Matchmaking живёт в `app/services/matchmaking/`, а не в `Game` или `StartGame`: `FindOpponent`, `Join`, `CleanupStaleWaitingGames`.

`FindOpponent` рассматривает только waiting games с одним `GamePlayer` и другим игроком; compatibility Weight ±15%, приоритет — минимальная разница, затем самая старая waiting game.

`Join` использует `with_lock`, проверяет waiting/одного участника/неучастие присоединяющегося, создаёт второго `GamePlayer` и вызывает `StartGame`. Это защита от race condition, не задача JavaScript.

Waiting game: `status = waiting`, `state = nil`, один `GamePlayer`, `last_seen_at`.

Перед игровым Action controller сначала проверяет доступ, затем waiting boundary, затем вызывает Engine: чужой игрок получает 403, участник waiting game — 422.

Waiting room показывает собственный HQ и weight, индикатор, совместимые waiting weight и отмену; не показывает чужие имя, Deck, Nation или HQ и не даёт выбирать комнату вручную.

Heartbeat отправляется каждые 10 секунд из `waiting_room_controller.js`; stale порог `STALE_AFTER = 30.seconds`. Cleanup удаляет только stale waiting games с ненулевым `last_seen_at`, не затрагивает fresh/started/finished и broadcast'ит refresh остальным waiting rooms.

## Тестирование и работа с AI

Тесты AI должны использовать fake/mock-источники решений. Полный тестовый набор не должен вызывать OpenAI API или зависеть от сетевого соединения, ключа API или баланса аккаунта.

Реальные запросы к внешней модели выполняются только в отдельной явно запускаемой проверке. Они не должны быть частью обычного `bin/rails test`.

Для будущего AI обязательны проверки:

- скрытые данные не попадают в `VisibleState`;
- provider не изменяет `GameState`;
- `Action` проходит через Engine;
- некорректные решения и ошибки источника обрабатываются безопасно;
- отказ AI не приводит к сохранению недопустимого состояния;
- AI не получает право действовать от имени другого игрока.
