# ARCHITECTURE.md

## Основной поток

```text
Decision Provider → Action → GameEngine → GameState
```

`GameEngine` — единственный арбитр правил. `GameEngine::Action` содержит `player_id`, `type`, `payload` и описывает намерение. `GameEngine::Result` содержит успех либо ошибку, новый `GameState` и `events`. Исходный state не мутируется (обычно `deep_dup`); при ошибке новый state не сохраняется.

Полный browser flow:

```text
Browser → Controller → Action → GameEngine → GameState → VisibleState → Turbo → Stimulus
```

## Game, GameState и runtime-объекты

`Game.state` — authoritative JSONB snapshot. Основные поля: `status`, `turn_number`, `current_player_id`, `turn_started_at`, `players`, `field`, `result`. Player state содержит `nation_id`, `hand`, `deck`, `graveyard`, `platoons`, `resources`, `remaining_time`, `empty_deck_draw_attempts`.

`GameState` не обращается к ActiveRecord. Persistent Deck не изменяется во время партии. Для `Game(status: waiting)` всегда `state == nil`: GameState не создаётся, ожидание и его metadata находятся вне игровых правил.

Поле хранит HQ и Technique; Platoon находится в `state["players"][player_id]["platoons"]`. У каждого игрока четыре slots `[nil, nil, nil, nil]`; уничтоженный взвод оставляет `nil`, slots не уплотняются. Логические координаты state не зависят от игрока; DOM хранит их в `data-position="row,column"`.

Runtime Technique содержит: `type`, `card_id`, `player_id`, `nation_id`, `name`, `technique_type`, `hp`, `firepower`, `fuel`, `attack_range`, `movement_count`, `movement_limit`, `movement_type`, attack flags. В нём нет `price`, `weight`, `card_type` и вложенного `technique`; у Technique нет Armor.

Runtime Platoon содержит `type`, `card_id`, `player_id`, `nation_id`, `name`, `firepower`, `hp`, `armor`, `fuel`; отсутствующий, `nil` или `0` armor трактуется как `0`.

Точные правила размеров поля, движения, боя, ресурсов и состава state определяет `GAME_RULES.md`.

## VisibleState и AvailableActions

`GameEngine::VisibleState` (`app/services/game_engine/visible_state.rb`) — единственный вход UI и AI в состояние. Он не мутирует GameState, передаёт `result` finished game и не преобразует координаты.

Собственный игрок получает полную руку, deck/graveyard counts, platoons, resources и remaining time. Противник получает только hand/deck/graveyard counts, публичные platoons, resources и remaining time; содержимое и порядок чужих hand/deck/graveyard не раскрываются. Resources публичны.

`GameEngine::AvailableActions` рассчитывается сервером и входит в VisibleState. Stimulus лишь отображает его. Поддерживаются moves/attacks Technique, attacks HQ, resources и positions Technique card, resources/targets/drop zone Order, resources/free slots Platoon. `resources_sufficient: false` означает только недостаток ресурсов: отсутствие позиции, цели или slot само по себе карту не приглушает. У неактивного игрока и finished game actions пусты. DOM-взвод идентифицируется сочетанием `data-platoon-slot` и `data-player-id`.

## ActiveRecord, Deck и Ability

Основные модели: `Game`, `Player`, `GamePlayer`, `Nation`, `Card`, `Headquarters`, `Technique`, `Platoon`, `Ability`, `CardAbility`, `Deck`, `DeckCard`.

`Player` использует `has_secure_password`, имеет `email`, `name`, `password_digest`, `guest`, `last_seen_at`; email уникален. Методы: `guest?`, `registered?`, `display_name`. Гость остаётся обычным Player с обычным player_id. У Player нет `dependent: :destroy` для game_players, чтобы не уничтожать историю автоматически.

`Game` имеет статусы `waiting`, `started`, `finished`, но игровой логики не содержит. `Game.last_seen_at` — техническая активность waiting room и не часть GameState.

`Deck` — постоянная колода; `DeckCard` хранит quantity. Ограничения Deck, Weight и состав starter Deck определены правилами; реализация использует единый `DECK_SIZE`, `Deck#card_count`, `Deck#complete?` и `StarterDecks::Create::STARTER_DECKS`. `StarterDecks::Create.call(player)` создаёт три постоянные колоды при регистрации и создании гостя в общей transaction. Seed не создаёт игроков или колоды.

Способности имеют единую цепочку `Card → CardAbility → Ability`. Исполнитель — `GameEngine::Abilities::Executor`; каждая новая ability получает отдельный handler. Не создавать `TechniqueAbility` и `HeadquartersAbility`.

## Engine-операции и события

Ключевые сервисы: `StartGame`, `Cards::Draw`, `Turns::PreparePlayer`, `Resources::FuelCalculator`, actions `Move`, `Attack`, `PlayCard`, `EndTurn`, `Surrender`, а также `FinishGame`. Точные игровые эффекты находятся в `GAME_RULES.md`.

События не должны теряться во вложенных операциях:

```text
Draw → DrawCards/PreparePlayer → EndTurn/PlayCard → Result.events → GamesController → Turbo/Stimulus
```

`PreparePlayer` возвращает draw events; `EndTurn` добавляет их к своим; `PlayCard#play_order` собирает events всех ability через `events.concat(result.events)`. Все пути завершения используют `FinishGame` и единый `game_finished`; отдельную систему victory/surrender не создавать.

Таймеры реализованы `TurnTimer` и `TurnTimerForTurn`. Сервер проверяет общий timeout до Action; клиентский `game_timer_controller.js` только показывает время и при окончании turn timer посылает существующий `end_turn`.

## UI, Turbo и перспектива

Stage 15 — функциональный browser vertical slice, не финальный production UI. Каждый игрок подписывается на `turbo_stream_from [@game, current_player_id]`. После успешного Action `GamesController` сохраняет state, строит отдельный VisibleState для каждого игрока, передаёт events в partial и broadcast’ит обновление. Полный скрытый GameState на клиент не передаётся.

Waiting room имеет отдельную подписку на Game и refresh при создании/удалении waiting game, Join и stale cleanup. Game events дают только визуальные реакции: move flash’ит обе клетки, attack — участники, `empty_deck_draw_attempt` — HQ нужного игрока, `platoon_played` — комбинацию player/slot. CSS-класс `.game-event--flash` не является игровой логикой.

Click, hover, selection и Drag & Drop используют `.game-action--card`, `.game-action--card-target`, `.game-action--drop-zone`; platoon bar — drop zone, но slot не передаётся в Action. Finished UI получает пустые actions, приглушает content через `.game-content--muted`, сохраняя видимым результат.

View определяет current/opponent по `current_player_id`: свой HQ снизу слева, чужой сверху справа; свои Platoon слева, рука снизу. Если свой HQ не в `[2][0]`, View разворачивает порядок строк и колонок. State, порядок slots и hand не меняются; Stimulus не преобразует координаты.

## Authentication и routes

Player одновременно аккаунт и игровая сущность; отдельные User/Devise не используются. Session определяет личность, но не GameState:

```text
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

Используются `RegistrationsController`, `SessionsController`, `has_secure_password` и `reset_session` при logout. Гость создаётся только при `/play`, получает три starter Deck и переиспользуется сессией; публичный `/decks` гостя не создаёт. Гость не создаёт/не меняет/не удаляет Deck и не имеет `/statistics`, но игра использует тот же Player/GamePlayer/Engine.

Публичные страницы: `/`, `/rules`, `/play`, `/decks`, `/cards`; `/statistics` — только зарегистрированному. Development-only `bin/rails dev:create_game` создаёт новые тестовые Deck/Game для `dev.player1@example.com` и `dev.player2@example.com` (пароль `password`), но не является пользовательским lifecycle.

Game routes: create, show, `end_turn`, `play_card`, `move`, `attack`, `surrender`, `cancel_waiting`, `waiting_heartbeat`. Полный список находится в `config/routes.rb`.

## Matchmaking и waiting lifecycle

Matchmaking живёт в `app/services/matchmaking/`, а не в Game или StartGame: `FindOpponent`, `Join`, `CleanupStaleWaitingGames`.

`FindOpponent` рассматривает только waiting games с одним GamePlayer и другим игроком; compatibility Weight ±15%, приоритет — минимальная разница, затем самая старая waiting game. `Join` использует `with_lock`, проверяет waiting/одного участника/неучастие присоединяющегося, создаёт второго GamePlayer и вызывает StartGame. Это защита от race condition, не задача JavaScript.

Waiting game: `status = waiting`, `state = nil`, один GamePlayer, `last_seen_at`. Перед игровым Action controller сначала проверяет доступ, затем waiting boundary, затем вызывает Engine: чужой игрок получает 403, участник waiting game — 422. Waiting room показывает собственный HQ и weight, индикатор, совместимые waiting weight и отмену; не показывает чужие имя, Deck, Nation или HQ и не даёт выбирать комнату вручную.

Heartbeat отправляется каждые 10 секунд из `waiting_room_controller.js`; stale порог `STALE_AFTER = 30.seconds`. Cleanup удаляет только stale waiting games с ненулевым last_seen_at, не затрагивает fresh/started/finished и broadcast’ит refresh остальным waiting rooms.
