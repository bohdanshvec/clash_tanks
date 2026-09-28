# AGENTS.md

Общаться со мною на русском языке.

---

## 1. Проект

**clash_tanks** — учебная браузерная пошаговая карточная стратегия про танки. Проект вдохновлён WoT: Generals, но использует собственные названия, правила, карты и материалы.

### Стек

- Ruby 3.4.10
- Rails 8.1.3.1
- PostgreSQL
- Hotwire / Turbo / Stimulus
- RVM
- Ubuntu 22.04

### Запуск

```bash
bin/dev
```

### Development PostgreSQL

- база: `clash_tanks_development`
- порт: `5432`

PostgreSQL 12 и 14 не изменять и не удалять без явного указания.

---

## 2. Источники истины

- `GAME_RULES.md` — правила и игровые механики.
- `AGENTS.md` — архитектура, технические решения и текущее состояние.

При противоречии старые чаты не имеют приоритета.

Не придумывать механики, отсутствующие в `GAME_RULES.md`.

Новые игровые решения сначала фиксировать в `GAME_RULES.md`, архитектурные — в `AGENTS.md`.

---

## 3. Главный архитектурный принцип

Основной поток:

```text
Decision Provider
      ↓
    Action
      ↓
 Game Engine
      ↓
  GameState
```

**Game Engine — единственный арбитр игровых правил.**

Controllers, UI, JavaScript, Stimulus и AI:

- не изменяют GameState напрямую;
- не определяют правила;
- не обходят Engine.

### Action

`GameEngine::Action`:

- `player_id`
- `type`
- `payload`

Action описывает только намерение игрока.

### Result

`GameEngine::Result` содержит:

- успех или ошибку;
- новый GameState;
- события.

Исходный GameState не мутируется. Обычно используется `deep_dup`.

При ошибке новый state не сохраняется.

---

## 4. Game и GameState

`Game.state` — authoritative snapshot (основной снимок состояния) партии в PostgreSQL JSONB.

Основные поля:

- `status`
- `turn_number`
- `current_player_id`
- `turn_started_at`
- `players`
- `field`
- `result`

Player state может содержать:

- `nation_id`
- `hand`
- `deck`
- `graveyard`
- `platoons`
- `resources`
- `remaining_time`
- `empty_deck_draw_attempts`

GameState не обращается к ActiveRecord.

Игровые операции создают новый state:

```ruby
state.deep_dup
```

Persistent Deck во время партии не изменяется.

---

## 5. VisibleState и скрытая информация

Игрок и AI получают только разрешённую информацию.

Нельзя раскрывать противнику:

- содержимое `hand`;
- содержимое и порядок `deck`;
- содержимое `graveyard`;
- `resources`;
- другие запрещённые данные.

`GameEngine::VisibleState`:

```text
app/services/game_engine/visible_state.rb
```

UI получает VisibleState, а не полный `Game.state`.

**Собственный игрок видит:**

- полную руку;
- deck count;
- platoons;
- resources;
- remaining time;
- graveyard count;
- остальные разрешённые данные.

**Противник видит:**

- hand count;
- deck count;
- platoons;
- remaining time;
- graveyard count;
- остальные разрешённые публичные данные.

---

## 6. AvailableActions

Реализован:

```text
app/services/game_engine/available_actions.rb
```

AvailableActions вычисляется сервером и входит в VisibleState.

Stimulus только отображает результат.

Не рассчитывать допустимые действия на клиенте.

Для текущего игрока:

```text
Technique
 ├── moves
 └── attacks

HQ
 └── attacks

Technique card
 └── placement positions

Order
 ├── targets
 └── field drop zone

Platoon card
 └── свободные Platoon slots
```

AvailableActions учитывает:

- текущий ход;
- принадлежность объекта;
- занятость клеток;
- движение;
- дальность;
- spotting;
- допустимые цели;
- ресурсы;
- свободные клетки;
- свободные Platoon slots.

Для Platoon используется:

```text
data-platoon-slot + data-player-id
```

Одинаковые номера слотов разных игроков не должны конфликтовать.

---

## 7. Игровое поле и runtime-объекты

Поле: **3 × 5**

Координаты:

```text
rows    0..2
columns 0..4
```

HQ:

```text
Player 1 → [2][0]
Player 2 → [0][4]
```

В `field` находятся:

- HQ;
- Technique.

Platoon хранится отдельно:

```ruby
state["players"][player_id]["platoons"]
```

У каждого игрока 4 слота:

```ruby
[nil, nil, nil, nil]
```

После уничтожения Platoon его слот становится `nil` и не уплотняется.

### Runtime Technique

Содержит:

- `type`
- `card_id`
- `player_id`
- `nation_id`
- `name`
- `technique_type`
- `hp`
- `firepower`
- `fuel`
- `attack_range`
- `movement_count`
- `movement_limit`
- `movement_type`
- attack flags

В runtime **не** хранятся:

- `price`
- `weight`
- `card_type`
- вложенный объект `technique`

### Runtime Platoon

Содержит:

- `type`
- `card_id`
- `player_id`
- `nation_id`
- `name`
- `firepower`
- `hp`
- `armor`
- `fuel`

`armor` может отсутствовать, быть `nil` или `0`; в боевой логике это `0`.

`firepower >= 0`.

---

## 8. ActiveRecord-модели

Основные модели:

- `Game`
- `Player`
- `GamePlayer`
- `Nation`
- `Card`
- `Headquarters`
- `Technique`
- `Platoon`
- `Ability`
- `CardAbility`
- `Deck`
- `DeckCard`

### Game

Статусы:

- `waiting`
- `started`
- `finished`

Game не содержит игровой логики.

### Card

Типы:

- `headquarters`
- `technique`
- `order`
- `platoon`

Поля:

- `code`
- `name`
- `nation`
- `card_type`
- `weight`
- `price`

`code` — стабильный уникальный машинный идентификатор.

### Technique

Типы:

- `light_tank`
- `medium_tank`
- `heavy_tank`
- `tank_destroyer`
- `artillery`

Типы движения:

- `orthogonal`
- `diagonal`

Текущая конфигурация:

| Тип | Движение | Количество |
|---|---|---|
| `light_tank` | orthogonal | 2 |
| `medium_tank` | diagonal | 1 |
| `heavy_tank` | orthogonal | 1 |
| `tank_destroyer` | orthogonal | 1 |
| `artillery` | orthogonal | 1 |

Technique не имеет Armor.

### Platoon

Поля:

- `firepower`
- `hp`
- `armor`
- `fuel`

### GamePlayer

Связывает:

- `Game`
- `Player`
- `Nation`
- `Deck`
- выбранный HQ card

Уникальность: `game_id + player_id`

---

## 9. Ability

Единая система:

```text
Card → CardAbility → Ability
```

`TechniqueAbility` и `HeadquartersAbility` не создавать.

**Ability:**

- `code`
- `name`

**CardAbility:**

- `card_id`
- `ability_id`
- `parameters`

Текущие способности:

- `damage_technique`
- `draw_cards`

Исполнитель:

```text
GameEngine::Abilities::Executor
```

Каждая новая способность добавляется отдельным handler (обработчиком).

---

## 10. Deck / StartGame

Deck — постоянная колода игрока.

DeckCard хранит количество копий.

Ограничения:

- максимум 3 копии карты;
- уникальность `deck_id + card_id`;
- карта и колода принадлежат одной Nation.

При StartGame:

1. проверяются два GamePlayer;
2. берутся их Deck;
3. создаются полные runtime-карты;
4. колоды перемешиваются;
5. оба игрока получают по 6 карт;
6. выбирается первый игрок;
7. создаётся GameState;
8. создаются оба HQ;
9. игра становится `started`;
10. первому игроку рассчитывается стартовый Fuel.

Первый игрок не получает дополнительный Draw при StartGame.

---

## 11. Draw / Turns / Resources

### Draw

Реализован:

```text
GameEngine::Cards::Draw
```

Draw не является отдельным Action.

Событие:

```json
{
  "type": "card_drawn",
  "player_id": 42
}
```

Содержимое карты в событии не раскрывается.

### Empty Deck

Счётчик:

```text
empty_deck_draw_attempts
```

При попытке Draw из пустой колоды:

```text
counter += 1
HQ HP -= counter
```

При уничтожении HQ используется `FinishGame`.

### Fuel

```text
GameEngine::Resources::FuelCalculator
```

Fuel текущего игрока рассчитывается из:

```text
HQ + собственные Technique + собственные Platoon
```

Неиспользованный Fuel не переносится.

### PreparePlayer

В начале хода:

```text
PreparePlayer
├── восстановление movement_count
├── сброс attack flags Technique
├── сброс attack flags HQ
├── пересчёт Fuel
└── обязательный Draw 1
```

### EndTurn

`GameEngine::Actions::EndTurn`:

- проверяет игрока и ход;
- рассчитывает прошедшее время;
- сохраняет оставшееся время;
- увеличивает turn number;
- меняет current player;
- обновляет turn start;
- вызывает PreparePlayer.

Создаёт `turn_ended`.

---

## 12. Timer

Реализован:

```text
GameEngine::TurnTimer
```

Начальное время:

```ruby
10.minutes.to_i
```

GameState содержит:

- `turn_started_at`
- `remaining_time`

Время списывается только у текущего игрока.

Engine проверяет истечение времени до выполнения Action.

При истечении:

```ruby
FinishGame(reason: "time_expired")
```

UI не является источником истины времени.

---

## 13. PlayCard

Stage 9 завершён.

Поддерживаются:

- Technique;
- Order;
- Platoon.

### Technique

Проверяются:

- текущий игрок;
- наличие карты;
- тип;
- ресурсы;
- координаты;
- свободная клетка;
- соседство с собственным HQ.

При успешном размещении:

```text
movement_count = 0
movement_limit = исходное значение
has_attacked = false
```

### Order

Ability выполняются через Executor.

Order атомарен: ошибка любой Ability откатывает весь Order.

При успехе Order удаляется из `hand` и помещается в `graveyard`.

### Platoon

Platoon занимает первый свободный слот.

При успехе:

- списывается `price`;
- карта удаляется из `hand`;
- создаётся runtime Platoon;
- создаётся `platoon_played`.

Событие содержит:

- `player_id`
- `card_id`
- `name`
- `slot`

`player_id` обязателен для корректного определения Platoon-полосы.

При UI Drag & Drop `slot` не передаётся в Action. Engine сам выбирает первый свободный слот.

---

## 14. Combat

Основной Action:

```text
GameEngine::Actions::Attack
```

Attack проверяет:

- текущий ход;
- координаты;
- атакующего;
- цель;
- принадлежность;
- дальность;
- специальные правила.

### Technique

Поддерживаются:

- Technique → Technique;
- Technique → HQ;
- SAU;
- PT-SAU;
- counterattack по правилам.

После успешной атаки:

```text
has_attacked = true
```

### SAU

`artillery` использует spotting для дальней атаки.

Источником spotting может быть:

- собственная Technique;
- наш штаб / штаб атакующего игрока.

Не создавать отдельную систему spotting для HQ.

Дальняя атака не вызывает counterattack.

### HQ

Поддерживаются:

- Technique → HQ;
- SAU → HQ;
- HQ → HQ;
- HQ → Technique.

HQ не контратакует HQ.

### HQ firepower

При атаке HQ:

```text
HQ firepower
+
firepower всех активных Platoon этого игрока
```

После выстрела каждый активный Platoon этого игрока получает урон, равный собственному firepower.

Уничтоженный Platoon:

- получает HP 0;
- помещается в `graveyard`;
- его слот становится `nil`;
- остальные слоты не сдвигаются.

### Защита HQ

Входящий урон проходит:

```text
slot 0 → slot 1 → slot 2 → slot 3 → HQ
```

Armor Platoon поглощает:

```ruby
[remaining_damage, platoon["armor"].to_i].min
```

После уничтожения Platoon оставшийся урон идёт дальше.

---

## 15. Victory / Defeat

Stage 13 завершён.

Единый сервис:

```text
GameEngine::FinishGame
```

Причины:

- `headquarters_destroyed`
- `empty_deck_damage`
- `time_expired`

Результат:

```ruby
status = "finished"

result = {
  winner_id: ...,
  loser_id: ...,
  reason: ...
}
```

Создаётся `game_finished`.

Все способы окончания партии используют `FinishGame`.

Не создавать отдельную систему победы внутри Combat или Actions.

---

## 16. Seed / базовый игровой контент

Stage 14 завершён.

Структура:

```text
db/
├── seeds.rb
└── seeds/
    ├── nations.rb
    ├── abilities.rb
    ├── cards.rb
    └── card_abilities.rb
```

Seed содержит только базовый игровой контент:

- Nation
- Ability
- Card
- Technique
- Platoon
- Headquarters
- CardAbility

**Не изменять через seed:**

- Player
- Deck
- DeckCard
- Game
- GamePlayer

Не использовать `destroy_all` / `delete_all` для пользовательских данных.

Seed должен быть идемпотентным.

Базовый контент:

```text
Nations:        3
Abilities:      2
Cards:         33
Techniques:    18
Platoons:       6
Headquarters:   3
CardAbilities:  6
```

Nations:

- `ussr`
- `germany`
- `usa`

Seed является базовым контентом и может быть явно запущен в production. Это не означает автоматический запуск seed при каждом deploy.

---

## 17. Stage 15 — Browser UI

Stage 15 — функциональный browser vertical slice, а не финальный production UI.

Основной поток:

```text
Browser
   ↓
Controller
   ↓
Action
   ↓
GameEngine
   ↓
GameState
   ↓
VisibleState
   ↓
Turbo
   ↓
Stimulus
```

UI не содержит игровых правил.

### Завершено

- [x] 15.1 Visible State
- [x] 15.2 временный dev player identity
- [x] 15.3 GamesController + `GET /games/:id`
- [x] 15.4 минимальная игровая страница
- [x] 15.5 поле 3×5
- [x] 15.6 рука
- [x] 15.7 End Turn
- [x] 15.8 PlayCard
- [x] 15.9 Move
- [x] 15.10 Attack
- [x] 15.11 базовая геометрия и характеристики
- [x] 15.12 Turbo / real-time
- [x] 15.13.1 рука
- [x] 15.13.2 выбор карты / объекта
- [x] 15.13.3 AvailableActions
- [x] 15.13.4 mouse actions / click + drag & drop
- [x] 15.13.5 Drag & Drop refinement + mouse hover/click interaction
- [x] 15.16 Order / Platoon HTML vertical slice

### Далее

- [ ] 15.13.6 визуальная обработка недоступных действий
- [ ] 15.14 Timer
- [ ] 15.15 waiting / started / finished

---

## 18. Dev player identity

Полной авторизации пока нет.

Временно используется:

```text
?player_id=1
```

Например:

```text
/games/7?player_id=1
```

Controller проверяет, что player является GamePlayer этой партии.

Это только dev-механизм, не authentication.

---

## 19. GamesController / Routes

Создан:

```text
app/controllers/games_controller.rb
```

Actions:

- `show`
- `end_turn`
- `play_card`
- `move`
- `attack`

Routes:

```ruby
get  "games/:id",           to: "games#show",      as: :game
post "games/:id/end_turn",  to: "games#end_turn",  as: :end_turn
post "games/:id/play_card", to: "games#play_card", as: :play_card
post "games/:id/move",      to: "games#move",      as: :move
post "games/:id/attack",    to: "games#attack",    as: :attack

mount ActionCable.server => "/cable"
```

Controller flow:

```text
HTTP request
    ↓
Game / player check
    ↓
Action
    ↓
GameEngine
    ↓
Result
    ↓
Game.update!
    ↓
Turbo / redirect
```

Controller не содержит игровых правил.

Ошибка Action:

```text
HTTP 422
GameState не изменяется
```

---

## 20. Stage 15.11 — UI geometry

Игровая зона:

```text
верхняя рука
      ↓
планка / поле / планка
      ↓
нижняя рука
```

HQ определяет сторону:

```text
[0,4] → верх
[2,0] → низ
```

Основная зона ориентирована примерно на:

```text
100px + 10px + 900px + 10px + 100px
```

Рука:

- одна горизонтальная строка;
- адаптивный gap;
- при переполнении допускается overlap;
- второй строки нет;
- hover работает у любой карты;
- карта при hover выходит вперёд и увеличивается;
- `100vw` не использовать как основу расчёта ширины руки.

Отображаются необходимые характеристики Technique, Order, Platoon и HQ.

`attack_range` отдельно в UI не отображается.

---

## 21. Stage 15.12 — Turbo / real-time

Turbo используется для обновления игры между браузерами.

Каждый игрок получает свой поток:

```erb
turbo_stream_from [@game, current_player_id]
```

Не отправлять полный скрытый GameState клиенту.

Turbo должен обновлять содержимое игры, не удаляя сам target-контейнер.

Полный ручной refresh для обычного игрового обновления не требуется.

---

## 22. Stage 15.13 — Stimulus / mouse / visual interaction

Controller:

```text
app/javascript/controllers/game_events_controller.js
```

Подключается через:

```html
data-controller="game-events"
```

Stimulus отвечает за:

- визуальные реакции на игровые события;
- выбор карты / объекта;
- подсветку AvailableActions;
- mouse interaction;
- Drag & Drop.

Stimulus не изменяет GameState и не рассчитывает игровые правила.

### 22.1 Игровые события

Обрабатываются:

- `technique_moved`
- `technique_attacked`
- `headquarters_attacked`
- `technique_played`
- `order_played`
- `platoon_played`
- `turn_ended`

#### Move

`technique_moved` flash'ит:

- исходную клетку;
- конечную клетку.

#### Attack

`technique_attacked` flash'ит:

- атакующего;
- цель.

`headquarters_attacked` также flash'ит атакующего и цель.

Для `headquarters_attacked` дополнительно:

- при атакующем HQ flash'ятся активные Platoon этого игрока с `firepower > 0`;
- при атакованном HQ flash'ятся активные Platoon этого игрока с `armor > 0`.

#### Technique / Order

`technique_played` flash'ит клетку.

`order_played` flash'ит target или позиции из `targets`.

#### Platoon

`platoon_played` использует:

```text
event.player_id
event.slot
```

чтобы выбрать правильный Platoon slot.

#### Turn

`turn_ended` временно добавляет:

```text
game--turn-changed
```

Общая flash-анимация:

```css
.game-event--flash {
  animation: game-event-flash 0.5s ease;
}
```

Существующие визуальные реакции нельзя удалять при дальнейшем развитии Stage 15.13.

### 22.2 Выбор объектов

Можно выбрать:

- карту в руке;
- собственную Technique;
- собственный HQ.

Выбранный объект получает:

```text
game-object--selected
```

Повторный клик снимает выбор.

Выбор другого объекта снимает предыдущий.

Выбор не изменяет GameState.

### 22.3 AvailableActions в Stimulus

После выбора объекта Stimulus подсвечивает данные из AvailableActions:

```text
Technique card → placement cells
Order          → targets / field
Platoon card   → свободные slots
Technique      → Move / Attack
HQ             → Attack
```

Не создавать вторую систему игровых Action-кнопок.

Не копировать правила Engine в JavaScript.

### 22.4 Platoon UI

Обе Platoon-полосы используют одинаковые номера:

```text
0, 1, 2, 3
```

Поэтому используется:

```text
data-platoon-slot
data-player-id
```

При подсветке свободных слотов Stimulus использует `player_id` карты.

При `platoon_played` используются одновременно:

```text
event.player_id
event.slot
```

Одинаковые номера слотов двух игроков не конфликтуют.

### 22.5 Mouse interaction

Основной принцип:

```text
AvailableActions
      ↓
Stimulus показывает разрешённые цели
      ↓
клик / hover / Drag
      ↓
Controller
      ↓
GameEngine
```

#### Выбор карты кликом

```text
карта
  ↓
click
  ↓
карта выделена
  ↓
AvailableActions
  ↓
доступные цели подсвечены
```

Наведение мыши на допустимую цель добавляет временную подсветку:

```text
game-action--hover
```

При уходе мыши с цели `game-action--hover` удаляется.

Клик по допустимой цели выполняет действие.

Клик по любой области, которая не является допустимой целью, отменяет выбор.

Повторный клик по самому выбранному объекту также отменяет выбор.

#### Technique / HQ

```text
выбор объекта
  ↓
AvailableActions
  ↓
допустимые Move / Attack targets
  ↓
hover → game-action--hover
  ↓
click target → move / attack
```

Клик вне допустимой цели отменяет выбор.

#### Drag & Drop

**Technique card**

```text
карта
  ↓
drag
  ↓
подсвеченная клетка
  ↓
drag-over
  ↓
drop
  ↓
play_card(card_id, row, column)
```

**Platoon card**

```text
карта
  ↓
drag
  ↓
Platoon bar
  ↓
drag-over
  ↓
drop
  ↓
play_card(card_id)
  ↓
Engine выбирает первый свободный slot
```

Slot не передаётся клиентом.

**Order без target**

```text
карта
  ↓
drag
  ↓
field drop zone
  ↓
drag-over
  ↓
drop
  ↓
play_card(card_id)
```

**Order с target**

```text
карта
  ↓
drag
  ↓
подсвеченный target
  ↓
drag-over
  ↓
drop
  ↓
play_card(card_id, target)
```

### 22.6 Drag & Drop refinement — завершено

Реализованы:

- `game-object--dragging` для карты во время Drag;
- `game-action--drag-over` для текущей допустимой цели;
- очистка drag-over при уходе с цели;
- полная очистка временного Drag-состояния при `drop` и `dragend`;
- отмена Drag не изменяет GameState;
- обычный click и Drag не мешают друг другу.

Drag принимает только разрешённые AvailableActions targets.

`dropTarget` использует:

```text
.game-action--card
.game-action--card-target
.game-action--drop-zone
```

Platoon bar является drop zone; отдельный slot не передаётся в Action.

### 22.7 Mouse hover для кликового управления — завершено

Для обычного кликового режима используется отдельное временное состояние:

```text
game-action--hover
```

Hover работает одинаково для:

- Technique card → placement cell;
- Platoon card → свободный slot;
- Order → field drop zone;
- Order → target;
- Technique → Move target;
- Technique → Attack target;
- HQ → Attack target.

Правило:

```text
выбранный объект
      ↓
AvailableActions
      ↓
мышь над допустимой целью
      ↓
game-action--hover
      ↓
мышь ушла
      ↓
game-action--hover удаляется
```

Hover не изменяет GameState и не определяет допустимость действия.

### 22.8 Отмена выбора — завершено

Если выбран объект:

- повторный клик по нему отменяет выбор;
- клик по другой карте или собственному объекту выбирает новый объект;
- клик по недопустимой области отменяет текущий выбор;
- hover сам по себе выбор не отменяет.

При отмене очищаются:

- `game-object--selected`;
- AvailableActions-подсветка;
- `game-action--hover`;
- временные Drag-состояния.

### 22.9 CSS-состояния

Используются:

```text
.game-object--selected
.game-action--move
.game-action--attack
.game-action--card
.game-action--card-target
.game-action--drop-zone
.game-action--hover
.game-action--drag-over
.game-object--dragging
```

`game-action--hover` и `game-action--drag-over` являются только временными визуальными состояниями.

Не использовать их как проверку безопасности или источник игровых правил.

### 22.10 Проверенное состояние

После завершения 15.13.5:

- `bin/rails test` проходит;
- Drag & Drop работает;
- Technique Drag & Drop работает;
- Platoon Drag & Drop работает;
- Order Drag & Drop работает;
- Move через click работает;
- Attack через click работает;
- click + hover для карт работает;
- click + hover для Technique/HQ работает;
- клик по недопустимой области отменяет выбор;
- повторный клик по выбранному объекту отменяет выбор;
- Turbo обновления работают;
- Engine остаётся источником игровых правил.

Изображения и окончательное визуальное оформление откладываются на более поздний этап.

---

## 23. Stage 15.13.6 — визуальная обработка недоступных действий

**Следующая задача.**

Цель — визуально ослабить карты, которые сейчас недоступны для розыгрыша, например:

- недостаточно ресурсов;
- не ваш ход;
- другое ограничение Engine.

Недоступная карта при этом должна:

- сохранять возможность hover;
- увеличиваться для просмотра характеристик.

Не использовать CSS/Stimulus как защиту от запрещённого действия.

Сначала проверить существующую структуру VisibleState / AvailableActions и определить, какие данные уже доступны UI для определения визуального состояния.

Не придумывать клиентские правила для определения доступности карты.

---

## 24. Stage 15.14 — Timer

Начинать после основного Stage 15.13.

Цель:

- отображать оставшееся время;
- обновлять его в UI;
- не делать Stimulus источником истины.

Источник истины:

```text
GameEngine / GameState
```

---

## 25. Stage 15.15 — waiting / started / finished

После Timer.

UI должен различать:

- `waiting`
- `started`
- `finished`

Для `finished` использовать:

```ruby
GameState["result"]
```

Не определять победителя отдельно в UI.

---

## 26. Stage 15.16

Stage 15.16 завершён как функциональный HTML vertical slice.

Через браузер работают:

- открытие игры;
- VisibleState;
- End Turn;
- Play Technique;
- Play Order;
- Play Platoon;
- Move Technique;
- Attack Technique;
- Attack HQ.

Для Order отображаются Ability и параметры.

Для Platoon отображаются характеристики и выполняется размещение в первый свободный слот.

Временные HTML-формы для игровых действий заменены мышиным управлением в рамках Stage 15.13.

---

## 27. Controller / UI boundaries

**Controller может:**

- принять HTTP params;
- проверить Game и player;
- создать Action;
- вызвать Engine;
- обработать Result;
- сохранить новый GameState;
- выполнить Turbo response / redirect / broadcast.

**Controller не должен:**

- менять HP;
- менять hand;
- размещать Technique;
- рассчитывать Fuel;
- определять победителя;
- менять GameState напрямую;
- обходить Engine.

**UI / Turbo / Stimulus:**

- не являются источником правил;
- не получают полный GameState;
- не изменяют `Game.state`;
- не рассчитывают AvailableActions;
- не определяют победу;
- не являются защитой от запрещённых действий.

---

## 28. AI / Decision Provider

Архитектура:

```text
Visible GameState
      ↓
Decision Provider
      ↓
Action
      ↓
GameEngine
```

Планируемый локальный AI:

```text
Ollama + Qwen3 1.7B
```

AI:

- не изменяет GameState напрямую;
- не видит скрытые данные;
- не обходит Engine;
- не делает Engine зависимым от Ollama.

---

## 29. Что запрещено

Не переносить игровую логику в:

- Controllers;
- Stimulus / JavaScript;
- ActiveRecord;
- UI;
- AI;
- Turbo / Action Cable.

Не:

- мутировать исходный GameState;
- изменять persistent Deck во время партии;
- хранить runtime Platoon на основном `field`;
- уплотнять Platoon slots;
- создавать TechniqueAbility;
- создавать HeadquartersAbility;
- создавать отдельный HQ level;
- создавать отдельный `nation_id` внутри HQ runtime;
- создавать отдельную систему spotting для HQ;
- создавать отдельную систему победы внутри Combat;
- создавать отдельный Draw Action;
- дублировать Draw;
- раскрывать скрытую информацию через VisibleState;
- использовать cookies как основное хранилище GameState;
- сохранять каждое промежуточное изменение GameState;
- использовать dev `player_id` как постоянную authentication;
- считать координаты постоянным ID Technique;
- использовать `movement_count` как Counterattack;
- придумывать игровые механики;
- определять Platoon только по номеру slot;
- рассчитывать доступные действия в Stimulus;
- создавать отдельные JS-кнопки поверх существующей системы;
- передавать slot Platoon из UI в `play_card`;
- считать Drag & Drop самостоятельной системой правил.

---

## 30. Порядок работы

Для каждого этапа:

1. Прочитать актуальные `AGENTS.md` и `GAME_RULES.md`.
2. Проверить существующую реализацию.
3. Обсудить существенные изменения до написания кода.
4. Внести только необходимые изменения.
5. Добавить или обновить тесты.
6. Запустить:

   ```bash
   bin/rails test
   ```

7. Проверить соответствие `GAME_RULES.md`.
8. Обновить `AGENTS.md`.
9. При необходимости обновить `GAME_RULES.md`.
10. После значимого этапа сделать отдельный Git commit.

Для Stage 15 работать маленькими шагами.

После существенных изменений UI обязательно проверять результат непосредственно в браузере.

Без явной команды пользователя не изменять файлы проекта.

---

## 31. Текущая контрольная точка

```text
Stage 1–8        завершены
Stage 9           завершён
Stage 10          завершён
Stage 11          завершён
Stage 12          завершён
Stage 13          завершён
Stage 14          завершён

Stage 15.1        завершён
Stage 15.2        завершён
Stage 15.3        завершён
Stage 15.4        завершён
Stage 15.5        завершён
Stage 15.6        завершён
Stage 15.7        завершён
Stage 15.8        завершён
Stage 15.9        завершён
Stage 15.10       завершён
Stage 15.11       завершён
Stage 15.12       завершён
Stage 15.13.1     завершён
Stage 15.13.2     завершён
Stage 15.13.3     завершён
Stage 15.13.4     завершён
Stage 15.13.5     завершён
Stage 15.13.6     следующая задача
Stage 15.14       после 15.13
Stage 15.15       после 15.14
Stage 15.16       завершён
```

Последнее проверенное состояние:

```text
bin/rails test
→ все тесты проходят

Полная партия через браузер
→ проверена
→ click actions работают
→ click + hover работают
→ Drag & Drop работает
→ Turbo работает
```

Продолжать с:

**Stage 15.13.6 — визуальная обработка недоступных действий**

Следующий принцип:

```text
AvailableActions / данные VisibleState
          ↓
визуальное состояние карты
          ↓
hover остаётся доступным
          ↓
Engine остаётся источником истины
```

Архитектурная граница:

```text
мышь / UI
    ↓
Stimulus
    ↓
Controller
    ↓
Action
    ↓
GameEngine
    ↓
GameState
    ↓
VisibleState
    ↓
Turbo
    ↓
Stimulus
```
