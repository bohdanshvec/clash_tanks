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

Development PostgreSQL:

- база: `clash_tanks_development`
- порт: `5432`

PostgreSQL 12 и 14 не изменять и не удалять без явного указания.

---

## 2. Источники истины

- `GAME_RULES.md` — правила и игровые механики.
- `AGENTS.md` — архитектура, технические решения и текущее состояние проекта.

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

Controllers, UI, JavaScript, Stimulus, Turbo и AI:

- не изменяют `GameState` напрямую;
- не определяют игровые правила;
- не обходят Engine.

### Action

`GameEngine::Action` содержит:

- `player_id`
- `type`
- `payload`

Action описывает только намерение игрока.

### Result

`GameEngine::Result` содержит:

- успех или ошибку;
- новый `GameState`;
- события `events`.

Исходный `GameState` не мутируется. Обычно используется `deep_dup`.

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

`GameState` не обращается к ActiveRecord.

Игровые операции создают новый state через `deep_dup`.

Persistent Deck во время партии не изменяется.

---

## 5. Скрытая информация и VisibleState

`GameEngine::VisibleState`:

```text
app/services/game_engine/visible_state.rb
```

UI и AI получают `VisibleState`, а не полный `Game.state`.

Противнику не раскрываются:

- содержимое `hand`;
- содержимое и порядок `deck`;
- содержимое `graveyard`;
- другие запрещённые данные.

Resources являются публичными.

### Собственный игрок видит

- полную руку;
- deck count;
- platoons;
- resources;
- remaining time;
- graveyard count;
- остальные разрешённые данные.

### Противник видит

- hand count;
- deck count;
- resources;
- platoons;
- remaining time;
- graveyard count;
- остальные разрешённые публичные данные.

### VisibleState

- не мутирует `GameState`;
- передаёт `result` завершённой игры;
- передаёт `available_actions`;
- не преобразует логические координаты поля.

Перспектива реализуется только на уровне View.

---

## 6. AvailableActions

Реализован:

```text
app/services/game_engine/available_actions.rb
```

`AvailableActions` вычисляется сервером и входит в `VisibleState`.

Stimulus только отображает результат.

Поддерживаются:

- Technique → moves / attacks;
- HQ → attacks;
- Technique card → resources / placement positions;
- Order → resources / targets / field drop zone;
- Platoon card → resources / свободные slots.

`resources_sufficient == false` означает недостаток ресурсов.

Важно:

- достаточные ресурсы могут сочетаться с отсутствием допустимых позиций, целей или слотов;
- отсутствие позиции/цели/слота само по себе не приглушает карту;
- неактивный игрок получает пустые `AvailableActions`;
- завершённая игра получает полностью пустые `AvailableActions`.

Для Platoon используется:

```text
data-platoon-slot + data-player-id
```

Одинаковые номера slots разных игроков не должны конфликтовать.

---

## 7. Game field и runtime objects

Поле:

- 3 × 5
- rows: `0..2`
- columns: `0..4`

Начальные HQ:

- Player 1 → `[2][0]`
- Player 2 → `[0][4]`

В `field` находятся:

- HQ;
- Technique.

Platoon хранится отдельно:

```text
state["players"][player_id]["platoons"]
```

У каждого игрока 4 slots:

```ruby
[nil, nil, nil, nil]
```

После уничтожения Platoon его slot становится `nil` и не уплотняется.

### Логические координаты

Координаты `GameState` не зависят от игрока.

View может менять только визуальный порядок строк и колонок.

Каждая DOM-клетка сохраняет реальную координату:

```text
data-position="row,column"
```

Stimulus работает с этой логической координатой.

---

## 8. Runtime Technique

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

Technique не имеет Armor.

### Technique movement

| Тип | Движение | Количество |
|---|---|---|
| `light_tank` | orthogonal | 2 |
| `medium_tank` | diagonal | 1 |
| `heavy_tank` | orthogonal | 1 |
| `tank_destroyer` | orthogonal | 1 |
| `artillery` | orthogonal | 1 |

---

## 9. Runtime Platoon

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

---

## 10. ActiveRecord models

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

### Player

Используется `has_secure_password`.

Поля:

- `email`
- `name`
- `password_digest`

Email уникален. `name` необязателен.

```ruby
class Player < ApplicationRecord
  has_secure_password

  has_many :game_players
  has_many :games, through: :game_players
  has_many :decks, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  def display_name
    name.presence || email.split("@").first
  end
end
```

`Player` не использует `dependent: :destroy` для `game_players`, чтобы удаление игрока не уничтожало игровую историю автоматически.

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

Уникальность:

```text
game_id + player_id
```

---

## 11. Ability

Единая система:

```text
Card → CardAbility → Ability
```

Не создавать `TechniqueAbility` или `HeadquartersAbility`.

Текущие abilities:

- `damage_technique`
- `draw_cards`

Исполнитель:

```text
GameEngine::Abilities::Executor
```

Каждая новая способность добавляется отдельным handler.

---

## 12. Deck

`Deck` — постоянная сохранённая колода игрока.

`DeckCard` хранит количество копий карты.

### Deck

Текущие ограничения:

- `DECK_SIZE = 10`;
- максимум 3 копии одной карты;
- уникальность `deck_id + card_id`;
- карта и колода принадлежат одной `Nation`;
- `Deck` имеет `name`;
- `Deck` имеет обязательный `headquarters_card`;
- HQ принадлежит той же `Nation`;
- HQ имеет `card_type == "headquarters"`;
- HQ не входит в `DECK_SIZE`;
- HQ не учитывается в Deck Weight.

`Deck#card_count` считает количество карт с учётом `quantity`.

`Deck#complete?` возвращает `true`, если:

- выбран HQ;
- количество обычных карт равно `DECK_SIZE`.

Incomplete Deck может существовать в базе и редактироваться.

`DECK_SIZE` должен оставаться единым изменяемым параметром для будущего перехода на размер 40.

### DeckCard

Проверяет:

- `quantity` от 1 до 3;
- уникальность карты внутри Deck;
- соответствие Nation карты и Deck;
- карта не может быть HQ.

---

## 13. Deck Weight

Deck Weight рассчитывается только по обычным картам:

```text
sum(card.weight × deck_card.quantity)
```

HQ в Weight не входит.

`weight` и `price` — разные механики:

- `weight` — характеристика карты для веса колоды;
- `price` — стоимость розыгрыша карты за Fuel.

Допуск Deck Weight для будущего matchmaking (подбор соперника): **±15%**

Логика допуска относится к matchmaking, а не к модели Deck.

---

## 14. Starter Decks

Стартовые колоды определяются единым источником:

```text
app/services/starter_decks/create.rb
```

Используется:

```ruby
StarterDecks::Create::STARTER_DECKS
```

Определены три стартовые колоды:

- Германия — Operation „Weiß“;
- США — Second front;
- СССР — Западный фронт.

Каждая стартовая колода содержит:

- HQ;
- 10 обычных карт;
- по одной копии каждой карты.

`StarterDecks::Create.call(player)` создаёт три постоянные Deck для зарегистрированного игрока.

Регистрация выполняет:

```text
Player
 ↓
StarterDecks::Create
 ↓
3 starter Deck
```

Создание `Player` и стартовых Deck выполняется внутри одной transaction.

Seed не создаёт Player и Deck.

---

## 15. StartGame

При `StartGame`:

1. проверяются два `GamePlayer`;
2. берутся их `Deck`;
3. создаются runtime-карты;
4. колоды перемешиваются;
5. оба игрока получают по 6 карт;
6. выбирается первый игрок;
7. создаётся `GameState`;
8. создаются оба HQ;
9. `Game` становится `started`;
10. первому игроку рассчитывается стартовый Fuel.

Первый игрок не получает дополнительный Draw при `StartGame`.

Persistent Deck не изменяется.

---

## 16. Draw / Turns / Resources

### Draw

Реализован:

```text
GameEngine::Cards::Draw
```

Draw не является отдельным Action.

Обычный Draw создаёт:

```json
{
  "type": "card_drawn",
  "player_id": 42
}
```

Содержимое карты в событии не раскрывается.

### Empty Deck

При попытке Draw из пустой колоды:

```text
empty_deck_draw_attempts += 1
HQ HP -= current_attempt_number
```

Создаётся событие:

```json
{
  "type": "empty_deck_draw_attempt",
  "player_id": 42,
  "damage": 1
}
```

При уничтожении HQ используется `FinishGame`.

### Передача Draw events

События Draw не должны теряться при вложенных вызовах.

Текущая цепочка:

```text
Draw
 ↓
DrawCards / PreparePlayer
 ↓
EndTurn / PlayCard
 ↓
Result.events
 ↓
GamesController
 ↓
Turbo / Stimulus
```

- `PreparePlayer` возвращает события Draw.
- `EndTurn` добавляет свои события к `prepare_result.events`.
- `PlayCard#play_order` сохраняет события всех Ability через `events.concat(result.events)`.

Это необходимо, в частности, для визуальной реакции на `empty_deck_draw_attempt`.

### PreparePlayer

В начале хода:

- восстанавливается `movement_count`;
- сбрасываются attack flags Technique;
- сбрасываются attack flags HQ;
- пересчитывается Fuel;
- выполняется обязательный Draw 1.

### Fuel

```text
GameEngine::Resources::FuelCalculator
```

Fuel текущего игрока рассчитывается из:

```text
HQ + собственные Technique + собственные Platoon
```

Неиспользованный Fuel не переносится.

### EndTurn

`GameEngine::Actions::EndTurn`:

- проверяет игрока и ход;
- рассчитывает прошедшее время;
- сохраняет оставшееся время;
- увеличивает turn number;
- меняет current player;
- обновляет turn start;
- вызывает `PreparePlayer`.

Создаёт `turn_ended` и передаёт события `PreparePlayer`.

---

## 17. Timer

Stage 15.14 завершён.

Общее время игрока:

```ruby
10.minutes.to_i
```

Длительность одного хода:

```text
GameEngine::GameState::TURN_TIME
```

Используются:

- `GameEngine::TurnTimer`
- `GameEngine::TurnTimerForTurn`

Общее время списывается только у текущего игрока.

Engine проверяет общий timeout до выполнения Action.

При timeout:

```text
FinishGame(reason: "time_expired")
```

Если общий и turn timer истекают одновременно, приоритет имеет общий timeout.

Клиентский Stimulus timer:

```text
app/javascript/controllers/game_timer_controller.js
```

Клиент:

- компенсирует разницу серверного и клиентского времени;
- отображает таймеры;
- обновляет их каждую секунду;
- при истечении turn timer отправляет существующий `end_turn`.

JavaScript не является источником истины.

После `finished` повторные `end_turn` не выполняются.

---

## 18. PlayCard

Stage 9 завершён.

Поддерживаются:

- Technique
- Order
- Platoon

### Technique

Проверяются:

- текущий игрок;
- наличие карты;
- тип;
- ресурсы;
- координаты;
- свободная клетка;
- соседство с собственным HQ.

При успехе:

```text
movement_count = 0
movement_limit = исходное значение
has_attacked = false
```

### Order

Ability выполняются через Executor.

Order атомарен: ошибка любой Ability откатывает весь Order.

При успехе:

- карта удаляется из `hand`;
- карта помещается в `graveyard`;
- создаётся `order_played`;
- события Ability сохраняются в общем `Result.events`.

### Platoon

Platoon занимает первый свободный slot.

При успехе:

- списывается `price`;
- карта удаляется из `hand`;
- создаётся runtime Platoon;
- создаётся `platoon_played`.

UI не передаёт slot в Action.

---

## 19. Combat

Основной Action:

```text
GameEngine::Actions::Attack
```

Поддерживаются:

- Technique → Technique
- Technique → HQ
- SAU
- PT-SAU
- HQ → HQ
- HQ → Technique
- counterattack по правилам

Attack проверяет:

- текущий ход;
- координаты;
- атакующего;
- цель;
- принадлежность;
- дальность;
- специальные правила.

### SAU

Spotting для дальней атаки может обеспечиваться:

- собственной Technique;
- нашим штабом / штабом атакующего игрока.

Дальняя SAU-атака не вызывает counterattack.

### HQ

HQ не контратакует HQ.

Сила атаки HQ:

```text
HQ firepower + firepower всех активных Platoon этого игрока
```

После выстрела каждый активный Platoon, чей firepower был добавлен, получает урон, равный собственному firepower.

### Защита HQ

Входящий урон проходит:

```text
slot 0 → slot 1 → slot 2 → slot 3 → HQ
```

Armor поглощает:

```ruby
[remaining_damage, platoon["armor"].to_i].min
```

После уничтожения Platoon остаток урона идёт дальше.

Уничтоженный Platoon:

- получает HP 0;
- помещается в `graveyard`;
- его slot становится `nil`;
- остальные slots не сдвигаются.

---

## 20. Victory / FinishGame

Единый сервис:

```text
GameEngine::FinishGame
```

Причины завершения:

- `headquarters_destroyed`
- `empty_deck_damage`
- `time_expired`
- `surrender`

Результат:

```json
{
  "status": "finished",
  "result": {
    "winner_id": "...",
    "loser_id": "...",
    "reason": "..."
  }
}
```

Создаётся событие:

```text
game_finished
```

Все способы окончания партии используют `FinishGame`.

Не создавать отдельную систему победы.

---

## 21. Surrender

Реализовано в Stage 15.15.

Поток:

```text
UI
 ↓
GamesController#surrender
 ↓
Action(type: "surrender")
 ↓
GameEngine
 ↓
FinishGame
 ↓
GameState
 ↓
VisibleState
 ↓
Turbo
```

Сдача:

- доступна независимо от текущего хода;
- определяет противника;
- передаёт победу противнику;
- завершает игру через `FinishGame(reason: "surrender")`.

Завершённая игра отклоняет новый Action.

---

## 22. Seed / базовый игровой контент

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

- `Nation`
- `Ability`
- `Card`
- `Technique`
- `Platoon`
- `Headquarters`
- `CardAbility`

Не изменять через seed:

- `Player`
- `Deck`
- `DeckCard`
- `Game`
- `GamePlayer`

Не использовать `destroy_all` / `delete_all` для пользовательских данных.

Seed идемпотентен.

Базовый контент:

| Сущность | Количество |
|---|---|
| Nations | 3 |
| Abilities | 2 |
| Cards | 33 |
| Techniques | 18 |
| Platoons | 6 |
| Headquarters | 3 |
| CardAbilities | 6 |

Nations:

- `ussr`
- `germany`
- `usa`

---

## 23. Browser UI / Turbo / Stimulus

Stage 15 — функциональный browser vertical slice, не финальный production UI.

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

### Turbo

Каждый игрок получает собственный поток:

```erb
turbo_stream_from [@game, current_player_id]
```

`GamesController` после успешного Action:

- сохраняет новый `GameState`;
- получает `Result.events`;
- строит `VisibleState` отдельно для каждого игрока;
- передаёт events в игровой partial;
- выполняет Turbo broadcast.

Не отправлять полный скрытый `GameState` клиенту.

### Stimulus

Основной controller:

```text
app/javascript/controllers/game_events_controller.js
```

Stimulus отвечает за:

- визуальные реакции;
- выбор объектов;
- `AvailableActions` подсветку;
- mouse interaction;
- Drag & Drop.

Stimulus не изменяет `GameState` и не рассчитывает игровые правила.

---

## 24. Stage 15 — UI visual reactions

Реализованы визуальные реакции:

- `technique_moved`
- `technique_attacked`
- `headquarters_attacked`
- `technique_played`
- `order_played`
- `platoon_played`
- `turn_ended`
- `game_finished`
- `empty_deck_draw_attempt`

### Attack

`technique_attacked`:

- flash атакующего;
- flash цели.

`headquarters_attacked`:

- flash атакующего;
- flash цели;
- если атакует HQ — flash всех активных Platoon атакующего с `firepower > 0`;
- если атакован HQ — flash всех активных Platoon защищающегося с `armor > 0`.

### Empty Deck

При `empty_deck_draw_attempt`:

- определяется HQ игрока через `data-headquarters-player-id`;
- flash получает именно его HQ.

Это работает как для:

- обязательного Draw в начале хода;
- Draw через Ability `draw_cards`.

### Move

`technique_moved` flash'ит:

- исходную клетку;
- конечную клетку.

### PlayCard

- `technique_played` flash'ит клетку;
- `order_played` flash'ит target / targets;
- `platoon_played` использует `player_id + slot`.

### CSS

Основной flash:

```css
.game-event--flash {
  animation: game-event-flash 0.5s ease;
}
```

CSS используется только для визуального эффекта.

---

## 25. Mouse / Drag & Drop

Реализованы:

- click;
- hover;
- selection;
- Drag & Drop;
- очистка drag-over;
- временные drag states.

Используются:

- `.game-action--card`
- `.game-action--card-target`
- `.game-action--drop-zone`

Platoon bar является drop zone.

Отдельный Platoon slot не передаётся в Action.

### Selection

Можно выбрать:

- карту в руке;
- собственную Technique;
- собственный HQ.

Повторный клик снимает выбор.

Клик по недопустимой области отменяет выбор.

### CSS states

Используются:

- `.game-object--selected`
- `.game-action--move`
- `.game-action--attack`
- `.game-action--card`
- `.game-action--card-target`
- `.game-action--drop-zone`
- `.game-action--hover`
- `.game-action--drag-over`
- `.game-object--dragging`
- `.game-object--muted`
- `.game-content--muted`

CSS/Stimulus не являются механизмом безопасности.

---

## 26. Player Perspective

Stage 15.17 завершён.

Для текущего игрока:

```text
              СОПЕРНИК
        рука соперника
        информация соперника

свои Platoon |    ПОЛЕ    | Platoon соперника

        информация игрока
             своя рука
              ИГРОК
```

Правила:

- собственный HQ визуально внизу слева;
- HQ соперника визуально вверху справа;
- свои Platoon слева;
- Platoon соперника справа;
- своя рука внизу;
- рука соперника сверху;
- информация соперника сверху;
- информация текущего игрока снизу.

View определяет current/opponent по `current_player_id`.

Если HQ текущего игрока логически находится в `[2][0]`, поле выводится обычно.

Иначе строки и колонки выводятся в обратном порядке.

`GameState["field"]` не изменяется.

Не использовать:

```css
transform: rotate(180deg);
```

Не менять порядок Platoon slots и карт в руке ради перспективы.

Stimulus не содержит отдельной системы преобразования координат.

---

## 27. Finished UI

Для `status == "finished"`:

- `VisibleState` передаёт `result`;
- UI использует `result["winner_id"]`;
- `AvailableActions` полностью пусты;
- игровой контент приглушается;
- результат остаётся неприглушённым;
- сервер всё равно отклоняет запрещённые Actions.

Используется:

```text
.game-content--muted
```

Отдельные недоступные объекты используют:

```text
.game-object--muted
```

Поддерживаются причины:

- `headquarters_destroyed`
- `empty_deck_damage`
- `time_expired`
- `surrender`

---

## 28. Stage 16 — Players

Stage 16 завершён.

Player одновременно является аккаунтом и игровой сущностью.

Отдельный `User` и Devise не используются.

### Authentication

Используется `has_secure_password`.

Текущий игрок определяется через:

```ruby
def current_player
  @current_player ||= Player.find_by(id: session[:player_id])
end
```

Игровой URL не использует `?player_id=`.

Игровой доступ:

```text
browser session
      ↓
current_player
      ↓
GamePlayer
      ↓
Action.player_id
      ↓
GameEngine
```

Session определяет личность пользователя, но не является источником игрового состояния.

### Registration / Login / Logout

Реализованы:

- `RegistrationsController`;
- `SessionsController`;
- registration;
- login;
- logout;
- session-based identity.

Logout использует:

```ruby
reset_session
```

### Registration

При регистрации:

```text
Player
 ↓
StarterDecks::Create
 ↓
3 starter Deck
```

`Player` и starter Deck создаются атомарно внутри transaction.

### Header

Гость видит:

- Clash Tanks;
- Гость;
- Войти;
- Регистрация.

Авторизованный игрок видит:

- Clash Tanks;
- `display_name`;
- Выйти.

### Pages

Публичные:

- `/`
- `/rules`
- `/play`
- `/decks`
- `/cards`

Для авторизованного игрока:

- `/statistics`

Гость получает redirect на `/` при попытке открыть `/statistics`.

### Development test game

Development-only:

```bash
bin/rails dev:create_game
```

Создаются/используются:

- `dev.player1@example.com`
- `dev.player2@example.com`

Пароль: `password`

Каждый запуск создаёт новые тестовые `Deck` и `Game`.

Для двух игроков нужны разные browser sessions:

- разные браузеры;
- разные profiles;
- либо обычное и приватное окно.

`dev:create_game` не является пользовательским lifecycle.

---

## 29. Deck UI — Stage 17

Stage 17 **завершён**.

Реализованы модель, редактор, список сохранённых колод, стартовые колоды для гостей, ограничения и тесты.

### Routes

Добавлены:

```ruby
resources :decks, only: [:new, :create, :edit, :update, :destroy]
```

Существующий публичный:

```ruby
get "decks", to: "pages#decks", as: :decks
```

используется для списка Deck.

### PagesController

`PagesController#decks` работает в двух режимах.

Авторизованный игрок получает только свои Deck:

```ruby
current_player.decks
```

с необходимыми associations:

- Nation;
- HQ;
- DeckCard;
- Card;
- Technique;
- Platoon;
- Headquarters;
- Abilities.

Гость получает подготовленные стартовые Deck через:

```ruby
StarterDecks::Create::STARTER_DECKS
```

Гостевые Deck не сохраняются и не редактируются.

### DecksController

Реализованы:

- `new`
- `create`
- `edit`
- `update`
- `destroy`

Все операции требуют `current_player`.

Игрок работает только со своими Deck:

```ruby
current_player.decks.find(params[:id])
```

Чужой Deck приводит к:

```text
404 Not Found
```

При создании:

- выбирается HQ;
- Nation Deck определяется через HQ;
- создаётся Deck;
- сохраняются выбранные DeckCard.

При редактировании существующий HQ сохраняется и не заменяется через форму.

Deck может быть сохранён неполным.

При ошибке форма отображается повторно с сохранением выбранных quantities и ошибок.

### Deck editor

Форма поддерживает:

- название Deck;
- выбор HQ;
- отображение Nation;
- выбор количества карт;
- `+` / `−` для quantity;
- максимум 3 копии;
- подсчёт количества карт;
- подсчёт Weight;
- сохранение;
- отмену.

Количество карт ограничено:

```text
0..10
```

HQ после создания изменить нельзя.

### Deck list

Для авторизованного игрока `/decks` показывает:

- только собственные Deck;
- название;
- Nation;
- HQ;
- количество карт;
- Weight;
- состав Deck;
- preview карт;
- редактирование;
- удаление.

«В бой» пока не реализован и остаётся отложенным до дальнейшего lifecycle.

Удаление выполняется через `button_to` с Turbo confirmation.

### Guest /decks

Гость видит:

- три starter Deck;
- Nation;
- HQ;
- состав;
- preview карт.

Гость не может:

- создавать Deck;
- редактировать Deck;
- удалять Deck;
- сохранять изменения.

### Card preview

Для preview Deck используется существующий `.card`.

Для компактного отображения применяются отдельные правила:

```css
.deck-card__card-preview .card__stats
.deck-card__card-preview .card__stats p
.deck-card__card-preview .card__abilities
.deck-card__card-preview .card__stats ul
.deck-card__card-preview .card__stats li
```

Preview не изменяет основной игровой `.card`.

---

## 30. Public Cards

Реализована публичная страница:

```text
/cards
```

Контроллер загружает карты с необходимыми связями:

```ruby
@cards = Card
  .includes(:nation, :technique, :platoon, :headquarters, :abilities)
  .order(:card_type, :name)
```

Каталог визуально использует тот же базовый `.card`, что и игровые карты в руке.

Карты группируются по Nation:

```text
Nation
  ↓
HQ
  ↓
остальные карты этой Nation
```

Порядок наций — по названию Nation.

HQ отображается увеличенным квадратным элементом.

Обычные карты отображаются в формате игровых карточек.

Для Technique в каталоге не выводятся:

- Range;
- Movement;
- Movement type.

Эта информация определяется типом техники и уже описана правилами игры.

Текущий каталог является UI-представлением данных и не содержит игровой логики.

Будущие изображения карт должны сохранять `.card` как общую основу.

Предполагается возможность разделить карту на слои:

```text
нижний слой
  ↓
изображение техники / фон карты

верхний слой
  ↓
числа, характеристики, подписи и другие данные
```

---

## 31. Tests

Для Deck реализованы отдельные тесты:

```text
test/models/deck_test.rb
test/models/deck_card_test.rb
test/controllers/decks_controller_test.rb
```

Проверяются:

### Deck model

- associations;
- обязательное имя;
- обязательный HQ;
- HQ должен быть `headquarters`;
- HQ должен принадлежать Nation Deck;
- `card_count`;
- `complete?`;
- максимум `DECK_SIZE`;
- Deck Weight;
- HQ не входит в Weight.

### DeckCard model

- associations;
- quantity 1;
- quantity 3;
- запрет quantity < 1;
- запрет quantity > 3;
- уникальность карты в Deck;
- соответствие Nation;
- запрет HQ в Deck.

### DecksController

- guest не может открыть `new`;
- guest не может открыть `edit`;
- авторизованный игрок может открыть `new`;
- авторизованный игрок может редактировать свой Deck;
- игрок не может редактировать чужой Deck;
- создание Deck;
- создание с картой другой Nation;
- более 3 копий одной карты;
- более 10 карт;
- редактирование Deck;
- сохранение существующего HQ при редактировании;
- удаление собственного Deck;
- невозможность удалить чужой Deck.

При `RecordNotFound` используется:

```ruby
assert_response :not_found
```

поскольку `ApplicationController` обрабатывает `ActiveRecord::RecordNotFound`.

### Полная проверка

Последняя полная проверка:

```bash
bin/rails test
```

Результат:

```text
383 runs, 1084 assertions, 0 failures, 0 errors, 0 skips
```

---

## 32. Stage 18 — Waiting / Started

Следующий этап.

План:

```text
authenticated player
        ↓
свои Deck
        ↓
выбор Deck
        ↓
«В бой»
        ↓
Game(status: waiting)
        ↓
waiting page
        ↓
второй игрок
        ↓
второй GamePlayer
        ↓
StartGame
        ↓
Game(status: started)
        ↓
GameState
        ↓
game page
```

Waiting:

- отдельная waiting page;
- `Game.state == nil`;
- не создавать fake `GameState`.

После появления второго игрока используется существующий `StartGame`.

Matchmaking Deck Weight: **±15%**

Допуск должен быть отдельной логикой matchmaking, а не частью модели Deck.

На Stage 18 не изменять уже реализованную механику Game Engine без необходимости.

---

## 33. Stage 19–23

### Stage 19 — Human vs Human

- полноценный flow двух реальных игроков;
- выбор Deck;
- waiting → started;
- StartGame;
- существующий Turbo real-time;
- завершение партии.

### Stage 20 — Decision Provider

Создать абстракцию:

- Human;
- AI;
- External API;
- Local model;
- Other provider.

Decision Provider выдаёт только Action и работает с разрешённым `VisibleState`.

### Stage 21 — AI

```text
VisibleState
    ↓
Decision Provider
    ↓
Action
    ↓
GameEngine
```

AI не должен:

- изменять `GameState`;
- видеть hidden information;
- обходить Engine;
- дублировать игровые правила.

### Stage 22 — Ollama / Qwen3 1.7B

Планируемая локальная модель:

- Ollama;
- Qwen3 1.7B.

Интеграция только на уровне Decision Provider.

Game Engine не зависит от Ollama.

### Stage 23 — AI testing

Проверять:

- корректность Action;
- ограничения `VisibleState`;
- запрещённые Actions;
- ошибки Decision Provider;
- отсутствие hidden information;
- невозможность прямого изменения `GameState`.

---

## 34. Что запрещено

Не переносить игровую логику в:

- Controllers;
- Stimulus / JavaScript;
- ActiveRecord;
- UI;
- AI;
- Turbo / Action Cable.

Не:

- мутировать исходный `GameState`;
- изменять persistent Deck во время партии;
- хранить runtime Platoon в основном `field`;
- уплотнять Platoon slots;
- создавать `TechniqueAbility`;
- создавать `HeadquartersAbility`;
- создавать отдельный HQ level;
- создавать `nation_id` внутри HQ runtime;
- создавать отдельную систему spotting для HQ;
- создавать отдельную систему победы;
- создавать отдельный Draw Action;
- дублировать Draw;
- раскрывать hidden information через `VisibleState`;
- использовать cookies как `GameState`;
- сохранять каждое промежуточное изменение `GameState`;
- использовать dev player ID как постоянную authentication;
- использовать `?player_id=` для пользовательской идентификации;
- считать координаты постоянным ID Technique;
- использовать `movement_count` как Counterattack;
- придумывать игровые механики;
- определять Platoon только по slot;
- рассчитывать `AvailableActions` в Stimulus;
- создавать отдельные JS-кнопки поверх существующей системы;
- передавать Platoon slot из UI в `play_card`;
- считать Drag & Drop отдельной системой правил;
- использовать CSS/Stimulus как security mechanism;
- завершать игру из UI/Controller в обход Engine;
- создавать отдельную систему surrender;
- изменять логические координаты `GameState` ради перспективы;
- преобразовывать координаты в `VisibleState`;
- использовать `transform: rotate(180deg)` для поля;
- дублировать правила перспективы в Stimulus;
- использовать визуальный порядок клеток как источник логических координат;
- считать browser session источником `GameState`;
- использовать одну browser session для одновременной авторизации двух разных игроков при browser-тестировании.

---

## 35. Порядок работы

Для каждого этапа:

1. Прочитать актуальные `AGENTS.md` и `GAME_RULES.md`.
2. Проверить существующую реализацию.
3. Обсудить существенные изменения до написания кода.
4. Внести только необходимые изменения.
5. Добавить/обновить тесты.
6. Запустить:

   ```bash
   bin/rails test
   ```

7. Проверить соответствие `GAME_RULES.md`.
8. Обновить `AGENTS.md`.
9. При необходимости обновить `GAME_RULES.md`.
10. После значимого этапа сделать Git commit.

Для UI работать маленькими шагами.

После существенных UI-изменений обязательно проверять результат непосредственно в браузере.

Без явной команды пользователя не изменять файлы проекта.

---

## 36. Текущая контрольная точка

Завершено:

- Stage 1–14;
- Stage 15.1–15.17;
- Stage 16;
- Stage 17.

### Stage 17

Завершены:

- Deck model;
- DeckCard model;
- Deck Weight;
- HQ для Deck;
- `StarterDecks::Create`;
- starter Deck при регистрации;
- публичный каталог Cards;
- `/decks`;
- список собственных Deck;
- гостевой просмотр starter Deck;
- создание Deck;
- редактирование Deck;
- удаление Deck;
- Deck editor;
- quantity;
- ограничения;
- Deck preview;
- Deck tests;
- controller tests;
- проверка UI в браузере.

### Последняя полная проверка

```bash
bin/rails test
```

Результат:

```text
383 runs, 1084 assertions, 0 failures, 0 errors, 0 skips
```

### Текущее состояние

- Stage 15 — **ЗАВЕРШЁН**
- Stage 16 — **ЗАВЕРШЁН**
- Stage 17 — **ЗАВЕРШЁН**
- Stage 18 — **СЛЕДУЮЩИЙ**

Следующая работа: **Stage 18 — Waiting / Started**

Основные задачи:

- выбор полной Deck;
- кнопка «В бой»;
- создание `Game(status: waiting)`;
- создание первого `GamePlayer`;
- waiting page;
- поиск/подключение второго игрока;
- matchmaking по Deck Weight ±15%;
- создание второго `GamePlayer`;
- запуск существующего `StartGame`;
- переход waiting → started.

До Stage 18 не реализовывать пользовательский lifecycle партии.

---

## 37. Архитектурные границы

### Игровой flow

```text
UI
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

### Authentication

```text
browser session
      ↓
current_player
      ↓
GamePlayer
      ↓
Action.player_id
      ↓
GameEngine
```

### Deck lifecycle

```text
Player
 ↓
Deck
 ↓
DeckCard
 ↓
/decks
 ↓
выбор полной Deck
 ↓
Stage 18: waiting
```

### AI

```text
VisibleState
    ↓
Decision Provider
    ↓
Action
    ↓
GameEngine
    ↓
GameState
```

### Event propagation

```text
GameEngine operation
      ↓
Result.events
      ↓
nested operation
      ↓
Result.events
      ↓
Controller
      ↓
Turbo
      ↓
Stimulus visual reaction
```

События должны сохраняться при вложенных Engine-операциях. UI может реагировать на события, но события не являются источником игровых правил.
