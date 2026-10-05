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

Для `Game(status: waiting)`:

- `state == nil`;
- `GameState` не создаётся;
- ожидание соперника не является частью игровых механик;
- waiting metadata хранится отдельно от `GameState`.

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

Для waiting games используется техническое поле:

```text
last_seen_at
```

Оно предназначено только для контроля активности waiting room и не является частью `GameState`.

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

Допуск Deck Weight для matchmaking: **±15%**

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

`StarterDecks::Create.call(player)` создаёт три постоянных Deck для зарегистрированного игрока.

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

Для waiting room используется отдельная Turbo subscription на `Game`.

Waiting room может получать refresh broadcast, когда:

- создаётся новая waiting game;
- waiting game удаляется;
- waiting game получает второго игрока и становится `started`;
- stale waiting game удаляется.

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

Реализованы:

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
- тесты;
- browser UI.

### Routes

```ruby
resources :decks, only: [:new, :create, :edit, :update, :destroy]
```

Публичный список:

```ruby
get "decks", to: "pages#decks", as: :decks
```

### Важно

Кнопка «В бой» на `/decks` удалена.

Выбор Deck для начала игры выполняется только через:

```text
/play
```

`/decks` остаётся страницей управления Deck и не является страницей запуска игры.

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

## 31. Matchmaking

Matchmaking реализуется отдельными сервисами и не помещается в `Game` или `StartGame`.

Основные сервисы:

```text
app/services/matchmaking/find_opponent.rb
app/services/matchmaking/join.rb
app/services/matchmaking/cleanup_stale_waiting_games.rb
```

### FindOpponent

Ищет только:

- `Game(status: waiting)`;
- игры с одним `GamePlayer`;
- другого игрока.

Совместимость Deck Weight: **±15%**

Если подходит несколько кандидатов, приоритет:

1. минимальная абсолютная разница Weight;
2. при одинаковой разнице — более старая waiting game.

### Join

`Matchmaking::Join` использует row lock (`with_lock`), чтобы защитить matchmaking от race condition.

Проверяется:

- игра всё ещё `waiting`;
- в игре только один игрок;
- текущий игрок ещё не является участником.

После добавления второго `GamePlayer` вызывается существующий:

```text
GameEngine::StartGame
```

Matchmaking не содержит игровой логики.

### Waiting cleanup

Для waiting games используется:

```text
Game.last_seen_at
```

Heartbeat отправляется из waiting room каждые 10 секунд.

Stimulus controller:

```text
app/javascript/controllers/waiting_room_controller.js
```

Если waiting room перестал отправлять heartbeat, stale game удаляется сервисом:

```text
Matchmaking::CleanupStaleWaitingGames
```

Текущий предел:

```ruby
STALE_AFTER = 30.seconds
```

Правила cleanup:

- stale waiting game удаляется;
- fresh waiting game сохраняется;
- `started` и `finished` games не удаляются;
- `last_seen_at == nil` не считается stale.

При удалении waiting game обновляются остальные waiting rooms через Turbo refresh.

---

## 32. Stage 18 — Waiting / Started

Stage 18 **ЕЩЁ НЕ ЗАВЕРШЁН**.

На данный момент реализована значительная часть waiting → started flow.

### Текущий flow PvP

```text
authenticated player
        ↓
/play
        ↓
выбор полной Deck
        ↓
«В бой — PvP»
        ↓
FindOpponent
        ├── соперник найден
        │       ↓
        │     Join
        │       ↓
        │   StartGame
        │       ↓
        │     game
        │
        └── соперник не найден
                ↓
          Game(status: waiting)
                +
          первый GamePlayer
                ↓
          waiting room
                ├── соперник найден
                │      ↓
                │    Join
                │      ↓
                │  StartGame
                │
                └── отмена ожидания
                       ↓
                  удаление Game
```

### /play

Для авторизованного игрока показываются только полные Deck.

Для каждой полной Deck доступны:

- В бой — PvP
- В бой — ИИ

На текущем этапе:

- PvP реализуется;
- AI режим не реализован;
- автоматическое создание AI при отсутствии соперника запрещено.

На `/decks` кнопки «В бой» нет.

### GamesController#create

Для PvP:

1. проверяется `current_player`;
2. проверяется `mode == "pvp"`;
3. находится Deck текущего игрока;
4. проверяется `deck.complete?`;
5. выполняется stale waiting cleanup;
6. проверяется, нет ли уже собственного waiting game;
7. вызывается `Matchmaking::FindOpponent`;
8. при найденном сопернике вызывается `Matchmaking::Join`;
9. если соперник не найден — создаётся новая waiting game;
10. создаётся первый `GamePlayer`.

Если у игрока уже есть собственная waiting game, новый waiting game не создаётся.

### Waiting Game

Waiting game содержит:

```text
status = waiting
state = nil
last_seen_at = current time
```

Имеет только одного `GamePlayer`.

### Waiting room

Waiting room показывает:

- собственный HQ;
- собственный Deck Weight;
- индикатор ожидания;
- список других ожидающих игроков только по Weight;
- кнопку «Выйти из ожидания».

Не показываются:

- имена игроков;
- названия Deck;
- Nation;
- HQ соперника;
- другие данные соперника.

Список waiting games используется только для визуальной информации о доступных Weight и не превращается в ручной выбор комнаты.

### Cancel waiting

Endpoint:

```text
DELETE /games/:id/cancel_waiting
```

Отмена разрешена только:

- текущему игроку;
- участнику этой waiting game;
- пока game имеет `waiting`;
- пока в ней только один `GamePlayer`.

После отмены:

- waiting `Game` удаляется;
- его `GamePlayer` удаляется через `dependent: :destroy`;
- остальные waiting rooms получают refresh.

### Waiting heartbeat

Endpoint:

```text
POST /games/:id/waiting_heartbeat
```

Heartbeat разрешён только участнику собственной waiting game.

При heartbeat:

```ruby
last_seen_at = Time.current
```

После этого выполняется stale cleanup.

### Turbo refresh

При создании новой waiting game обновляются другие waiting rooms.

При успешном Join:

- started game получает `broadcast_game_refresh`;
- остальные waiting games получают `broadcast_waiting_games_refresh`.

Это необходимо, чтобы список ожидающих игроков в уже открытых browser sessions обновлялся без ручного reload.

### Проверено в браузере

Проверен сценарий с несколькими browser sessions и Weight:

```text
14
23
24
```

Проверено:

- создание waiting games;
- отображение других ожидающих игроков;
- matchmaking;
- присоединение игрока 24 к игроку 23;
- переход game в `started`;
- обновление других waiting rooms без ручного reload;
- heartbeat;
- удаление stale waiting game после закрытия browser session.

### Текущие ограничения Stage 18

Пока не завершено:

1. Полностью покрыть тестами waiting → started flow.
2. Проверить и зафиксировать тестами структуру созданного `GameState`.
3. Проверить тестами, что оба `GamePlayer` корректно созданы после matchmaking.
4. Проверить тестами, что hidden hand не раскрывается после `StartGame`.
5. Проверить тестами, что игровые Actions отклоняются для waiting game.
6. Проверить все пути завершения игры:
   - `headquarters_destroyed`;
   - `time_expired`;
   - `empty_deck_damage`;
   - `surrender`.
7. Проверить для каждого завершения:
   - `Game.status == finished`;
   - корректный `state["result"]`;
   - корректный winner/loser;
   - корректная причина;
   - `AvailableActions == {}` / пустой результат;
   - последующие Actions отклоняются.
8. Проверить полный browser flow:
   - `/play`;
   - выбор Deck;
   - waiting;
   - второй игрок;
   - started;
   - первая игровая страница.
9. Проверить все edge cases matchmaking:
   - несовместимый Weight;
   - несколько совместимых waiting games;
   - одинаковая разница Weight;
   - повторная попытка Join;
   - race condition.
10. Проверить поведение при закрытии/обрыве waiting browser session.
11. Отдельно реализовать вход в игру гостем.

### Guest game — важно

Гостевой просмотр `/play` и `/decks` существует, но гостевой вход непосредственно в игру сейчас **НЕ реализован**.

Гость не может пройти текущий PvP flow, потому что:

```text
GamePlayer
    ↓
belongs_to Player
```

а текущая идентификация игры использует:

```text
session[:player_id]
        ↓
current_player
        ↓
GamePlayer
```

Поэтому нельзя считать гостевой режим реализованным только потому, что гость видит starter Deck.

Нужно отдельно спроектировать и реализовать гостевой lifecycle.

При этом нельзя:

- подменять гостя постоянным `Player`;
- использовать `?player_id=`;
- использовать dev player как гостя;
- хранить `GameState` в session/cookies;
- нарушать существующую модель скрытой информации;
- обходить `GamePlayer`/Engine архитектуру без отдельного решения.

Архитектура гостевой игры должна быть сначала определена, затем зафиксирована в `AGENTS.md`, а если появляются новые игровые правила — в `GAME_RULES.md`.

---

## 33. Routes текущего игрового lifecycle

Основные маршруты:

```ruby
get "play", to: "pages#play", as: :play
get "decks", to: "pages#decks", as: :decks

resources :games, only: [:create]

get "games/:id", to: "games#show", as: :game

post "games/:id/end_turn",
     to: "games#end_turn",
     as: :end_turn

post "games/:id/play_card",
     to: "games#play_card",
     as: :play_card

post "games/:id/move",
     to: "games#move",
     as: :move

post "games/:id/attack",
     to: "games#attack",
     as: :attack

post "games/:id/surrender",
     to: "games#surrender",
     as: :surrender

delete "games/:id/cancel_waiting",
       to: "games#cancel_waiting",
       as: :cancel_waiting_game

post "games/:id/waiting_heartbeat",
     to: "games#waiting_heartbeat",
     as: :waiting_heartbeat_game
```

---

## 34. Tests

Тесты должны проверять не только отдельные сервисы, но и границы между ними.

### Matchmaking tests

Проверяются:

- поиск совместимого соперника;
- допуск ±15%;
- несовместимый Weight;
- приоритет минимальной разницы Weight;
- при равной разнице — более старая waiting game;
- исключение самого игрока;
- только waiting games;
- только games с одним игроком.

### Join tests

Проверяются:

- успешное присоединение;
- создание второго `GamePlayer`;
- запуск `StartGame`;
- переход waiting → started;
- защита от повторного Join;
- защита от игры, которая уже `started`;
- race-condition protection.

### Cleanup tests

Проверяются:

- stale waiting game удаляется;
- fresh waiting game сохраняется;
- `started` game не удаляется;
- `finished` game не удаляется;
- `last_seen_at == nil` сохраняется.

### GamesController tests

Проверяются:

- создание waiting PvP game;
- невозможность начать игру с incomplete Deck;
- невозможность использовать чужой Deck;
- Join существующей совместимой waiting game;
- создание новой waiting game при отсутствии совместимого соперника;
- cancel waiting;
- запрет отмены чужой waiting game;
- запрет отмены уже `started` game;
- waiting room;
- отображение Weight;
- Turbo refresh после создания waiting game;
- Turbo refresh после Join;
- heartbeat;
- hidden information;
- Actions в waiting game;
- переход waiting → started.

### Finished game tests

Нужно добавить/проверить integration tests для:

- HQ destroyed;
- time expired;
- empty deck damage;
- surrender;
- запрета любых последующих Actions;
- пустого `AvailableActions`;
- корректного `result`.

### Текущая полная проверка

Последний результат:

```bash
bin/rails test
```

```text
409 runs, 1206 assertions, 0 failures, 0 errors, 0 skips
```

Controller tests:

```bash
bin/rails test test/controllers/games_controller_test.rb
```

```text
21 runs, 100 assertions, 0 failures, 0 errors, 0 skips
```

---

## 35. Stage 19–23

### Stage 19 — Human vs Human

После завершения Stage 18:

- полноценный flow двух реальных игроков;
- выбор Deck;
- waiting → started;
- StartGame;
- существующий Turbo real-time;
- полноценная партия;
- завершение партии;
- browser testing полного PvP lifecycle.

Stage 19 не должен дублировать уже реализованный matchmaking. Его задача — довести реальный Human vs Human lifecycle до полноценной игровой партии.

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

## 36. Что запрещено

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
- использовать одну browser session для одновременной авторизации двух разных игроков при browser-тестировании;
- автоматически создавать AI-соперника в PvP, если человек не найден;
- превращать список waiting players в ручной выбор комнаты;
- хранить matchmaking metadata в `GameState`;
- считать `last_seen_at` частью игровых правил;
- удалять `started` или `finished` games через waiting cleanup;
- считать гостевой просмотр starter Deck гостевой игровой сессией.

---

## 37. Порядок работы

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

## 38. Текущая контрольная точка

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

### Stage 18

**В ПРОЦЕССЕ. НЕ ЗАВЕРШЁН.**

Уже реализовано:

- `/play` для авторизованного игрока;
- выбор полной Deck;
- «В бой — PvP»;
- «В бой — ИИ» как UI-кнопка, но AI ещё не реализован;
- создание `Game(status: waiting)`;
- первый `GamePlayer`;
- waiting page;
- `Matchmaking::FindOpponent`;
- matchmaking по Weight ±15%;
- приоритет ближайшего Weight;
- приоритет более старой waiting game при одинаковой разнице;
- `Matchmaking::Join`;
- row lock при Join;
- создание второго `GamePlayer`;
- существующий `StartGame`;
- переход waiting → started;
- cancel waiting;
- waiting heartbeat;
- stale waiting cleanup;
- Turbo refresh waiting rooms;
- browser testing matchmaking;
- browser testing waiting cleanup;
- тесты controller для waiting/matchmaking;
- тест на refresh других waiting rooms после Join.

Последняя полная проверка:

```bash
bin/rails test
```

```text
409 runs, 1206 assertions, 0 failures, 0 errors, 0 skips
```

### Что осталось сделать в Stage 18

1. Integration tests для полного waiting → started lifecycle.
2. Проверка структуры `GameState` после `StartGame`.
3. Проверка двух `GamePlayer`.
4. Проверка скрытой руки после `StartGame`.
5. Проверка запрета Actions для waiting game.
6. Полное покрытие завершения игры:
   - `headquarters_destroyed`;
   - `time_expired`;
   - `empty_deck_damage`;
   - `surrender`.
7. Проверка после каждого завершения:
   - `status == finished`;
   - `result`;
   - winner;
   - loser;
   - reason;
   - пустые `AvailableActions`;
   - отклонение последующих Actions.
8. Полный browser flow waiting → started → игровая страница.
9. Дополнительные edge cases matchmaking.
10. Проверка race conditions.
11. Проверка stale cleanup при реальном закрытии/потере waiting browser session.
12. Спроектировать и реализовать вход в игру гостем.

### Guest mode — отдельная незавершённая задача

Сейчас:

```text
Гость
 ↓
/play
 ↓
starter Deck
```

работает только как просмотр.

Гость не может начать реальную игру.

Причина:

```text
GamePlayer → Player
```

и текущий игровой lifecycle требует:

```text
session[:player_id]
 ↓
current_player
 ↓
GamePlayer
```

Это необходимо считать незавершённой частью Stage 18, а не считать гостевой режим реализованным через наличие гостевых Deck на `/play` или `/decks`.

Перед реализацией гостевой игры необходимо определить архитектуру guest identity (идентификация гостя) так, чтобы:

- гость мог участвовать в реальной партии;
- сохранялась текущая архитектура Engine;
- Engine получал нормальный `player_id`;
- hidden information сохранялась;
- `GameState` оставался authoritative;
- session не становилась `GameState`;
- не использовался `?player_id=`;
- не создавался постоянный dev `Player`;
- не нарушалась история завершённых игр.

Архитектурное решение сначала зафиксировать в `AGENTS.md`.

### Текущее состояние

- Stage 15 — **ЗАВЕРШЁН**
- Stage 16 — **ЗАВЕРШЁН**
- Stage 17 — **ЗАВЕРШЁН**
- Stage 18 — **В ПРОЦЕССЕ**

---

## 39. Архитектурные границы

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
/play
 ↓
выбор полной Deck
 ↓
Stage 18: waiting
```

### Matchmaking

```text
/play
 ↓
FindOpponent
 ├── opponent found
 │      ↓
 │    Join
 │      ↓
 │  StartGame
 │
 └── opponent not found
        ↓
   waiting Game
        ↓
 waiting room
        ↓
     heartbeat
        ↓
 Matchmaking / Join
        ↓
    StartGame
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

### Guest

Будущая архитектура должна сохранить общий игровой поток:

```text
Guest identity
      ↓
GamePlayer
      ↓
Action.player_id
      ↓
GameEngine
      ↓
GameState
```

Гостевая идентификация не должна создавать второй игровой Engine или отдельную систему правил.

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
