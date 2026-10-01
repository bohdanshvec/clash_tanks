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

- не изменяют `GameState` напрямую;
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
- новый `GameState`;
- события.

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

## 5. VisibleState и скрытая информация

Игрок и AI получают только разрешённую информацию.

Скрыты от противника:

- содержимое `hand`;
- содержимое и порядок `deck`;
- содержимое `graveyard`;
- другие запрещённые данные.

Resources являются публичной информацией.

`GameEngine::VisibleState`: `app/services/game_engine/visible_state.rb`

UI получает `VisibleState`, а не полный `Game.state`.

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

- не раскрывает скрытые данные;
- не мутирует исходный `GameState`;
- передаёт `result` завершённой игры;
- передаёт `available_actions`;
- не преобразует логические координаты поля для конкретного игрока.

Визуальная перспектива реализуется на уровне View.

---

## 6. AvailableActions

Реализован: `app/services/game_engine/available_actions.rb`

`AvailableActions` вычисляется сервером и входит в `VisibleState`.

Stimulus только отображает результат.

Для текущего игрока:

### Technique

- moves
- attacks

### HQ

- attacks

### Technique card

- `resources_sufficient`
- placement positions

### Order

- `resources_sufficient`
- targets
- field drop zone

### Platoon card

- `resources_sufficient`
- свободные Platoon slots

`resources_sufficient == false` означает недостаток ресурсов.

### Важно

- `resources_sufficient == true` может сочетаться с пустым списком допустимых позиций, слотов или целей;
- отсутствие позиции/слота/цели само по себе не приглушает карту;
- неактивный игрок получает пустые `AvailableActions`;
- завершённая игра получает полностью пустые `AvailableActions`.

`AvailableActions` учитывает:

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

- rows: `0..2`
- columns: `0..4`
- Player 1 HQ: `[2][0]`
- Player 2 HQ: `[0][4]`

В `field` находятся:

- HQ;
- Technique.

Platoon хранится отдельно:

```text
state["players"][player_id]["platoons"]
```

У каждого игрока 4 слота:

```ruby
[nil, nil, nil, nil]
```

После уничтожения Platoon его слот становится `nil` и не уплотняется.

### Важное разделение логики и представления

Координаты поля являются логическими координатами `GameState`.

Они не изменяются в зависимости от игрока, который смотрит игру.

Например:

```text
Player 1 HQ → [2][0]
Player 2 HQ → [0][4]
```

Эти координаты остаются такими и при отображении игры для любого игрока.

View может менять только визуальный порядок клеток.

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

### Player

`Player` использует `has_secure_password`.

Текущая модель:

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

Поля:

- `email`
- `name`
- `password_digest`

`name` необязателен.

### Game

Статусы:

- `waiting`
- `started`
- `finished`

`Game` не содержит игровой логики.

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

Движение:

| Тип | Движение | Количество |
| --- | --- | --- |
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

Уникальность: `game_id + player_id`.

---

## 9. Ability

Единая система:

```text
Card → CardAbility → Ability
```

`TechniqueAbility` и `HeadquartersAbility` не создавать.

Текущие способности:

- `damage_technique`
- `draw_cards`

Исполнитель: `GameEngine::Abilities::Executor`

Каждая новая способность добавляется отдельным handler (обработчиком).

---

## 10. Deck / StartGame

`Deck` — постоянная колода игрока.

`DeckCard` хранит количество копий.

Ограничения:

- максимум 3 копии карты;
- уникальность `deck_id + card_id`;
- карта и колода принадлежат одной Nation.

При `StartGame`:

1. проверяются два `GamePlayer`;
2. берутся их `Deck`;
3. создаются полные runtime-карты;
4. колоды перемешиваются;
5. оба игрока получают по 6 карт;
6. выбирается первый игрок;
7. создаётся `GameState`;
8. создаются оба HQ;
9. игра становится `started`;
10. первому игроку рассчитывается стартовый Fuel.

Первый игрок не получает дополнительный Draw при `StartGame`.

---

## 11. Draw / Turns / Resources

### Draw

Реализован: `GameEngine::Cards::Draw`

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

При попытке Draw из пустой колоды:

```text
counter += 1
HQ HP -= counter
```

При уничтожении HQ используется `FinishGame`.

### Fuel

`GameEngine::Resources::FuelCalculator`

Fuel текущего игрока рассчитывается из:

```text
HQ + собственные Technique + собственные Platoon
```

Неиспользованный Fuel не переносится.

### PreparePlayer

В начале хода:

- восстановление `movement_count`;
- сброс attack flags Technique;
- сброс attack flags HQ;
- пересчёт Fuel;
- обязательный Draw 1.

### EndTurn

`GameEngine::Actions::EndTurn`:

- проверяет игрока и ход;
- рассчитывает прошедшее время;
- сохраняет оставшееся время;
- увеличивает turn number;
- меняет current player;
- обновляет turn start;
- вызывает `PreparePlayer`.

Создаёт `turn_ended`.

---

## 12. Timer

Stage 15.14 завершён.

Реализованы:

- общий остаток времени игрока;
- 2-минутный таймер текущего хода.

### Серверная часть

Используются:

- `GameEngine::TurnTimer`
- `GameEngine::TurnTimerForTurn`

Начальное общее время:

```ruby
10.minutes.to_i
```

Длительность хода:

```ruby
GameEngine::GameState::TURN_TIME
```

`GameState` содержит:

- `turn_started_at`
- `remaining_time`

Общее время списывается только у текущего игрока.

Engine проверяет истечение общего времени до выполнения Action.

При истечении общего времени:

```ruby
FinishGame(reason: "time_expired")
```

Если одновременно истекают общий и turn timer, приоритет имеет общее время.

`EndTurn` также проверяет общее время перед обычным переходом.

### Клиент

Stimulus controller: `app/javascript/controllers/game_timer_controller.js`

Клиент:

- получает серверное время;
- компенсирует разницу времени клиента и сервера;
- отображает оба таймера;
- обновляет отображение каждую секунду;
- при истечении таймера отправляет существующий `end_turn`.

JavaScript не является источником истины времени.

После `finished` повторные `end_turn` не выполняются.

Проверено через браузер:

- обычный End Turn;
- смена хода;
- общий timeout;
- turn timeout;
- приоритет общего timeout;
- `game_finished` broadcast;
- корректное завершение UI.

---

## 13. PlayCard

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

При успешном размещении:

```text
movement_count = 0
movement_limit = исходное значение
has_attacked = false
```

### Order

Ability выполняются через Executor.

Order атомарен: ошибка любой Ability откатывает весь Order.

При успехе Order удаляется из hand и помещается в graveyard.

### Platoon

Platoon занимает первый свободный слот.

При успехе:

- списывается `price`;
- карта удаляется из hand;
- создаётся runtime Platoon;
- создаётся `platoon_played`.

Событие содержит:

- `player_id`
- `card_id`
- `name`
- `slot`

UI не передаёт slot в Action. Engine сам выбирает первый свободный слот.

---

## 14. Combat

Основной Action: `GameEngine::Actions::Attack`

Attack проверяет:

- текущий ход;
- координаты;
- атакующего;
- цель;
- принадлежность;
- дальность;
- специальные правила.

Поддерживаются:

- Technique → Technique
- Technique → HQ
- SAU
- PT-SAU
- HQ → HQ
- HQ → Technique
- counterattack по правилам

### SAU

Artillery использует spotting для дальней атаки.

Источником spotting может быть:

- собственная Technique;
- наш штаб / штаб атакующего игрока.

Дальняя атака не вызывает counterattack.

### HQ

HQ не контратакует HQ.

При атаке HQ:

```text
HQ firepower + firepower всех активных Platoon этого игрока
```

После выстрела каждый активный Platoon этого игрока получает урон, равный собственному `firepower`.

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

Уничтоженный Platoon:

- получает HP 0;
- помещается в graveyard;
- его слот становится `nil`;
- остальные слоты не сдвигаются.

---

## 15. Victory / Defeat / FinishGame

Stage 13 завершён.

Единый сервис: `GameEngine::FinishGame`

Причины:

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

Создаётся событие `game_finished`.

Все способы окончания партии используют `FinishGame`.

Не создавать отдельную систему победы внутри Combat, Actions, Controller или UI.

---

## 16. Surrender

Реализовано в Stage 15.15.

Создан: `GameEngine::Actions::Surrender`

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

- доступна игроку независимо от того, чей сейчас ход;
- определяет противника;
- передаёт победу противнику;
- завершает игру через `FinishGame(reason: "surrender")`.

В Engine surrender обрабатывается отдельно от проверки текущего игрока и timer, поэтому игрок может сдаться и во время хода противника.

Если игра уже `finished`, новый Action отклоняется.

---

## 17. Seed / базовый игровой контент

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

Seed должен быть идемпотентным.

Базовый контент:

| Сущность | Количество |
| --- | --- |
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

## 18. Stage 15 — Browser UI

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

- 15.1 Visible State
- 15.2 временный dev player identity
- 15.3 GamesController + `GET /games/:id`
- 15.4 минимальная игровая страница
- 15.5 поле 3×5
- 15.6 рука
- 15.7 End Turn
- 15.8 PlayCard
- 15.9 Move
- 15.10 Attack
- 15.11 базовая геометрия и характеристики
- 15.12 Turbo / real-time
- 15.13.1 рука
- 15.13.2 выбор карты / объекта
- 15.13.3 AvailableActions
- 15.13.4 mouse actions / click + drag & drop
- 15.13.5 Drag & Drop refinement + mouse hover/click interaction
- 15.13.6 визуальная обработка недоступных действий
- 15.14 Timer
- 15.15 finished UI + surrender
- 15.16 Order / Platoon HTML vertical slice
- 15.17 Player Perspective

### Важно: что было отложено

Первоначально Stage 15.15 должен был включать:

- waiting / started

Но waiting и пользовательский lifecycle игры отложены на Stage 18.

Поэтому Stage 15 реализует:

- browser gameplay;
- finished;
- surrender;
- Player Perspective.

waiting / started UI сейчас не реализуются.

---

## 19. Stage 15.15 — Finished UI

Stage 15.15 завершён.

### VisibleState

Для завершённой игры `VisibleState` передаёт:

```ruby
"result" => {
  "winner_id" => "...",
  "loser_id" => "...",
  "reason" => "..."
}
```

UI не вычисляет победителя по игровым объектам.

Используется `result["winner_id"]`.

### Finished screen

Победитель видит: **Победа**

Проигравший видит: **Вы проиграли**

После завершения приглушается весь игровой контент:

- поле;
- обе Platoon-полосы;
- обе руки;
- оба info-window;
- кнопки игровых действий.

Результат остаётся неприглушённым.

Используется отдельная обёртка `.game-content--muted`.

`pointer-events: none` — только UI-механизм. Сервер всё равно проверяет состояние игры.

Существующий `.game-object--muted` по-прежнему используется для отдельных недоступных игровых объектов, например карт руки.

### Finished AvailableActions

После `status == "finished"` `AvailableActions` возвращает:

```ruby
{
  "field" => {},
  "hand" => {}
}
```

### Проверено через браузер

- surrender;
- уничтожение HQ;
- отображение «Победа»;
- отображение «Вы проиграли»;
- приглушение игрового экрана;
- Turbo update;
- корректное завершение игры у обоих игроков.

Также уже реализовано завершение через:

- `time_expired`;
- `headquarters_destroyed`;
- `empty_deck_damage`;
- `surrender`.

Все варианты используют общий finished UI.

---

## 20. Stage 15.11 — UI geometry

Игровая зона:

```text
верхняя часть
      ↓
планка / поле / планка
      ↓
нижняя часть
```

Базовая геометрия использует:

```text
100px + 10px + 900px + 10px + 100px
```

Рука:

- центрируется;
- допускает перенос нескольких рядов на широких/больших руках;
- hover работает у любой карты;
- карта при hover выходит вперёд и увеличивается.

`100vw` не использовать как основу расчёта ширины руки.

Отображаются необходимые характеристики Technique, Order, Platoon и HQ.

`attack_range` отдельно в UI не отображается.

### Текущая визуальная перспектива

После Stage 15.17 верх/низ больше не привязаны к конкретному Player ID.

Для любого игрока, открывшего игру:

```text
              СОПЕРНИК
        рука соперника
        информация соперника

свои Platoon |    ПОЛЕ    | Platoon соперника

        информация игрока
             своя рука
              ИГРОК
```

Свой HQ визуально всегда находится в нижней левой части поля.

HQ соперника визуально всегда находится в верхней правой части поля.

### Логические координаты не меняются

`GameState["field"]` не переворачивается и не изменяется.

Для игрока, чей HQ находится логически в `[2][0]`, поле отображается в обычном порядке:

```text
[0][0] [0][1] [0][2] [0][3] [0][4]
[1][0] [1][1] [1][2] [1][3] [1][4]
[2][0] [2][1] [2][2] [2][3] [2][4]
```

Для игрока, чей HQ находится логически в `[0][4]`, поле отображается в обратном порядке:

```text
[2][4] [2][3] [2][2] [2][1] [2][0]
[1][4] [1][3] [1][2] [1][1] [1][0]
[0][4] [0][3] [0][2] [0][1] [0][0]
```

Каждая DOM-клетка сохраняет настоящую логическую координату:

```html
data-position="row,column"
```

Например, визуально нижняя левая клетка для второго игрока может иметь:

```html
data-position="0,4"
```

Stimulus продолжает работать с логическими координатами.

### Важно

Не использовать:

```css
transform: rotate(180deg);
```

для разворота игрового поля.

Разворот выполняется изменением порядка вывода строк и колонок в View.

Не менять порядок Platoon slots внутри боковых панелей без отдельного требования.

Не менять порядок карт в руке только из-за перспективы.

---

## 21. Stage 15.12 — Turbo / real-time

Turbo используется для обновления игры между браузерами.

Каждый игрок получает свой поток:

```erb
turbo_stream_from [@game, current_player_id]
```

Не отправлять полный скрытый `GameState` клиенту.

Turbo должен обновлять содержимое игры, не удаляя сам target-контейнер.

Полный ручной refresh для обычного игрового обновления не требуется.

Перспектива игрока определяется при построении View после Turbo update.

---

## 22. Stage 15.13 — Stimulus / mouse / visual interaction

Controller: `app/javascript/controllers/game_events_controller.js`

Stimulus отвечает за:

- визуальные реакции на игровые события;
- выбор карты / объекта;
- подсветку `AvailableActions`;
- mouse interaction;
- Drag & Drop.

Stimulus не изменяет `GameState` и не рассчитывает игровые правила.

### Игровые события

Обрабатываются:

- `technique_moved`
- `technique_attacked`
- `headquarters_attacked`
- `technique_played`
- `order_played`
- `platoon_played`
- `turn_ended`
- `game_finished`

### Attack

`technique_attacked`:

- flash атакующего;
- flash цели.

`headquarters_attacked`:

- flash атакующего;
- flash цели;
- если атакует HQ — flash активных Platoon атакующего с `firepower > 0`;
- если атакован HQ — flash активных Platoon защищающегося с `armor > 0`.

### Move

`technique_moved` flash'ит:

- исходную клетку;
- конечную клетку.

### PlayCard

- `technique_played` flash'ит клетку;
- `order_played` flash'ит target или позиции из `targets`;
- `platoon_played` использует `event.player_id + event.slot`.

### Turn

`turn_ended` временно добавляет: `game--turn-changed`

### Finished

`game_finished` используется для визуального обновления завершённой игры через Turbo/Stimulus.

Существующие визуальные реакции не удалять при дальнейшем развитии Stage 15.

### Важное правило координат

Stimulus не должен знать о визуальной перспективе игрока.

Он работает с:

```html
data-position="реальная_строка,реальная_колонка"
```

а не с визуальным индексом клетки.

Не добавлять в Stimulus отдельную систему преобразования координат для перспективы.

### Выбор объектов

Можно выбрать:

- карту в руке;
- собственную Technique;
- собственный HQ.

Выбранный объект получает `game-object--selected`.

Повторный клик снимает выбор.

Выбор не изменяет `GameState`.

### AvailableActions в Stimulus

После выбора объекта Stimulus подсвечивает данные из `AvailableActions`:

- Technique card → placement cells
- Order → targets / field
- Platoon card → свободные slots
- Technique → Move / Attack
- HQ → Attack

Не создавать вторую систему игровых Action-кнопок.

Не копировать правила Engine в JavaScript.

### Mouse interaction

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

Hover:

- добавляет `game-action--hover`;
- не изменяет `GameState`.

Клик:

- по допустимой цели выполняет действие;
- по недопустимой области отменяет выбор;
- повторный клик по выбранному объекту отменяет выбор.

### Drag & Drop

Реализованы:

- `game-object--dragging`;
- `game-action--drag-over`;
- очистка drag-over;
- полная очистка временного Drag-состояния;
- обычный click и Drag не мешают друг другу.

Drag принимает только разрешённые `AvailableActions` targets.

Используются:

- `.game-action--card`
- `.game-action--card-target`
- `.game-action--drop-zone`

Platoon bar является drop zone.

Отдельный slot не передаётся в Action.

### Отмена выбора

Если выбран объект:

- повторный клик по нему отменяет выбор;
- клик по другой карте или собственному объекту выбирает новый объект;
- клик по недопустимой области отменяет текущий выбор;
- hover сам по себе выбор не отменяет.

При отмене очищаются:

- `game-object--selected`;
- `AvailableActions`-подсветка;
- `game-action--hover`;
- временные Drag-состояния.

### CSS-состояния

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

`game-action--hover` и `game-action--drag-over` — только временные визуальные состояния.

`game-object--muted` — визуальное состояние отдельного недоступного объекта.

`game-content--muted` — визуальное состояние всей завершённой игры.

CSS/Stimulus не являются проверкой безопасности.

### Визуальная обработка недоступных действий

Приглушаются карты в руке:

- неактивного игрока;
- активного игрока при недостатке ресурсов.

Если карта имеет достаточные ресурсы, но нет подходящей позиции/слота/цели, она не приглушается.

При hover приглушённая карта остаётся интерактивной.

Engine остаётся источником истины.

---

## 23. Stage 15.17 — Player Perspective

Stage 15.17 завершён.

Цель: каждый игрок должен видеть игровую сцену со своей стороны.

### Правило отображения

Для текущего игрока:

- собственный HQ визуально всегда внизу слева;
- HQ соперника визуально всегда вверху справа;
- собственные Platoon всегда слева;
- Platoon соперника всегда справа;
- собственная рука всегда внизу;
- рука соперника всегда вверху;
- информация соперника находится над полем;
- информация текущего игрока находится под полем.

### Реализация

Основная логика находится в: `app/views/games/_game.html.erb`

View определяет:

- `current_player`;
- `opponent_player`;

по `current_player_id`.

Игроки больше не определяются как постоянные `top_player` / `bottom_player`.

### Поле

View определяет, находится ли HQ текущего игрока в логической позиции `[2][0]`.

Если да — поле выводится в обычном порядке.

Если нет — строки и столбцы выводятся в обратном порядке.

Логические координаты при этом не меняются.

### Platoon bars

```text
game-board__left  → current player
game-board__right → opponent
```

В DOM используется `data-player-id`, поэтому одинаковые номера Platoon slots разных игроков не конфликтуют.

### Hands

```text
game-top__hand    → opponent hand count
game-bottom__hand → current player's full hand
```

Содержимое руки соперника не раскрывается.

### Info

```text
game-top__info    → opponent
game-bottom__info → current player
```

Кнопки:

- Сдаться;
- End Turn

отображаются только в нижней информации текущего игрока.

### Важная архитектурная граница

Player Perspective является только presentation/UI logic.

Не изменять ради перспективы:

- `GameState`;
- `VisibleState`;
- `AvailableActions`;
- `GameEngine`;
- логические координаты;
- Action payload;
- Stimulus правила.

`VisibleState` продолжает отдавать поле в исходных логических координатах.

### Проверено через браузер

Проверены обе перспективы:

- просмотр игры первым игроком;
- просмотр игры вторым игроком;
- собственная рука снизу;
- рука соперника сверху;
- свои Platoon слева;
- Platoon соперника справа;
- собственный HQ визуально снизу слева;
- HQ соперника визуально сверху справа;
- сохранение реальных `data-position`;
- корректная работа существующих действий и визуальных реакций.

CSS для отдельного разворота сцены не добавлялся.

`transform: rotate(180deg)` не используется.

---

## 24. Публичные Resources

Resources являются публичной информацией.

`VisibleState` передаёт:

- own player: `resources`;
- opponent: `resources`.

View отображает Resources обоих игроков.

Содержимое hand, deck, graveyard противника не раскрывается.

---

## 25. Stage 16 — Players

Stage 16 завершён.

Цель Stage 16:

- перейти от временного `player_id` к реальному `Player`;
- добавить базовую authentication (аутентификацию);
- определить `current_player` через Rails session;
- убрать `?player_id=` из пользовательского игрового flow;
- добавить базовые публичные страницы;
- подготовить основу для Stage 17 Deck;
- сохранить архитектурную границу `Game → GamePlayer → Player`.

### 25.1 Player authentication

Используется:

```ruby
has_secure_password
```

Для паролей используется `bcrypt`.

`Player` имеет:

- `email`;
- `name`;
- `password_digest`.

Email уникален.

### 25.2 Registration

Создан: `RegistrationsController`

Поддерживаются:

- форма регистрации;
- email;
- name;
- password;
- password confirmation;
- валидация;
- создание `Player`.

После успешной регистрации выполняется redirect на `root_path`.

### 25.3 Login

Создан: `SessionsController`

Поддерживаются:

- форма входа;
- email;
- password;
- authenticate;
- сохранение `session[:player_id]`;
- redirect на `root_path`;
- сообщение об ошибке при неверных данных.

### 25.4 Logout

Поддерживается: `DELETE /logout`

Используется:

```ruby
reset_session
```

После выхода выполняется redirect на `root_path`.

### 25.5 current_player

`ApplicationController` содержит:

```ruby
helper_method :current_player
```

Текущий игрок определяется только через `session[:player_id]`.

Игровой URL больше не определяет пользователя через query parameter.

Используется:

```ruby
def current_player
  @current_player ||= Player.find_by(id: session[:player_id])
end
```

### 25.6 GamesController authentication

Игровые endpoints больше не используют `?player_id=` как способ идентификации игрока.

`GamesController` получает текущего игрока из `current_player`.

Перед игровым действием проверяется:

```text
current_player
      ↓
player_in_game?(game)
      ↓
GamePlayer
```

Игрок может работать только с игрой, участником которой он является.

Игровой `player_id` в `GameState` не изменяется authentication-механизмом.

### 25.7 Routes

Добавлены:

```ruby
get "login", to: "sessions#new", as: :login
post "login", to: "sessions#create"
delete "logout", to: "sessions#destroy", as: :logout

get "register", to: "registrations#new", as: :register
post "register", to: "registrations#create", as: :registrations

get "rules", to: "pages#rules", as: :rules
get "play", to: "pages#play", as: :play
get "decks", to: "pages#decks", as: :decks
get "statistics", to: "pages#statistics", as: :statistics
```

Существующий:

```ruby
root "pages#home"
```

Игровые routes:

```ruby
get  "games/:id",           to: "games#show",      as: :game
post "games/:id/end_turn",  to: "games#end_turn",  as: :end_turn
post "games/:id/play_card", to: "games#play_card", as: :play_card
post "games/:id/move",      to: "games#move",      as: :move
post "games/:id/attack",    to: "games#attack",    as: :attack
post "games/:id/surrender", to: "games#surrender", as: :surrender
```

### 25.8 Header

Layout содержит общий header.

Гость видит:

- Clash Tanks;
- Гость;
- Войти;
- Регистрация.

Авторизованный игрок видит:

- Clash Tanks;
- `display_name`;
- Выйти.

### 25.9 Основные страницы

Главная страница содержит:

- Правила игры;
- Играть;
- Колоды;
- Статистика — только для авторизованного игрока.

Публичные страницы:

```text
/
/rules
/play
/decks
```

`/statistics` доступна только авторизованному игроку.

Для гостя:

```text
GET /statistics
        ↓
redirect /
```

Пока это базовая навигационная основа.

Реальный выбор Deck, создание waiting game и пользовательский запуск партии относятся к следующим этапам.

### 25.10 Guest mode

Гость может открыть:

- `/`;
- `/rules`;
- `/play`;
- `/decks`.

Гость не может открыть: `/statistics`.

Для `/statistics` выполняется redirect на `root_path`.

Авторизованный игрок может открыть все перечисленные страницы.

### 25.11 Development test games

Создание тестовой игры сохранено как development-only механизм:

```bash
bin/rails dev:create_game
```

Development task автоматически создаёт или находит двух специальных development-пользователей:

```text
dev.player1@example.com
dev.player2@example.com
```

Пароль:

```text
password
```

Для каждого запуска создаются новые тестовые Deck и новая Game.

После создания task выводит Game ID и данные development-пользователей.

Игровой URL больше не содержит `?player_id=...`

Пример:

```text
http://localhost:3000/games/61
```

Для тестирования двух игроков используются разные browser sessions:

- разные браузеры;
- разные browser profiles;
- либо обычное и приватное окно.

#### Важно

Одна обычная browser session содержит одного текущего `session[:player_id]`.

Поэтому для одновременного тестирования двух игроков в разных авторизациях нельзя использовать два окна одного и того же browser profile.

Это не является игровой ошибкой.

`dev:create_game` не является пользовательским lifecycle и не заменяет будущие waiting / started механики.

### 25.12 Тесты Stage 16

Добавлены и обновлены тесты:

- Player authentication;
- registration;
- login;
- logout;
- `current_player`;
- доступ к игре через авторизацию;
- отсутствие зависимости от `?player_id=`;
- доступ к публичным страницам;
- ограничение `/statistics` для гостя;
- доступ авторизованного игрока к `/statistics`.

Последняя полная проверка Stage 16:

```bash
bin/rails test
```

Результат:

```text
346 runs, 947 assertions, 0 failures, 0 errors, 0 skips
```

Отдельно:

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Результат:

```text
6 runs, 8 assertions, 0 failures, 0 errors, 0 skips
```

### 25.13 Итог Stage 16

Stage 16 полностью завершён.

Реализовано:

- `Player`;
- email;
- password authentication;
- registration;
- login;
- logout;
- `current_player`;
- session-based identity;
- удаление пользовательской зависимости от `?player_id=`;
- проверка участия в Game через `GamePlayer`;
- общий header;
- главная страница;
- Rules;
- Play;
- Decks;
- Statistics;
- Guest mode;
- development test users;
- development test game без `?player_id=`;
- тесты.

---

## 26. GamesController / Routes

Создан: `app/controllers/games_controller.rb`

Actions:

- `show`
- `end_turn`
- `play_card`
- `move`
- `attack`
- `surrender`

Controller flow:

```text
HTTP request
 ↓
current_player
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

- HTTP 422;
- `GameState` не изменяется.

Surrender также не завершает игру напрямую из Controller.

### Authentication boundary

```text
browser session
      ↓
current_player
      ↓
GamePlayer membership
      ↓
Action.player_id
      ↓
GameEngine
```

Session определяет личность пользователя.

Она не является источником игрового состояния.

`Game.state` остаётся единственным authoritative snapshot игровой партии.

---

## 27. Controller / UI boundaries

### Controller может

- принять HTTP params;
- определить `current_player`;
- проверить Game и player;
- создать Action;
- вызвать Engine;
- обработать Result;
- сохранить новый `GameState`;
- выполнить Turbo response / redirect / broadcast.

### Controller не должен

- менять HP;
- менять hand;
- размещать Technique;
- рассчитывать Fuel;
- определять победителя;
- менять `GameState` напрямую;
- обходить Engine.

### UI / Turbo / Stimulus

- не являются источником правил;
- не получают полный `GameState`;
- не изменяют `Game.state`;
- не рассчитывают `AvailableActions`;
- не определяют победу;
- не являются защитой от запрещённых действий;
- могут изменять только порядок визуального представления данных.

---

## 28. Stage 15.16

Stage 15.16 завершён как функциональный HTML vertical slice.

Через браузер работают:

- открытие игры;
- `VisibleState`;
- End Turn;
- Play Technique;
- Play Order;
- Play Platoon;
- Move Technique;
- Attack Technique;
- Attack HQ.

Для Order отображаются Ability и параметры.

Для Platoon:

- отображаются характеристики;
- выполняется размещение в первый свободный слот.

Временные HTML-формы игровых действий заменены мышиным управлением в рамках Stage 15.13.

---

## 29. Что отложено на Stage 18

Пользовательский lifecycle партии сознательно не реализуется в Stage 16–17.

На Stage 18 планируется:

```text
player authenticated
        ↓
видит свои Deck
        ↓
выбирает Deck
        ↓
«В бой»
        ↓
создаётся Game со status = waiting
        ↓
waiting page
        ↓
второй игрок получает игру
        ↓
второй GamePlayer
        ↓
StartGame
        ↓
Game.status = started
        ↓
создаётся полноценный GameState
        ↓
игровая страница
```

### Waiting

`Game.status == "waiting"` и `Game.state == nil` до вызова `StartGame`.

Waiting должен быть отдельной страницей ожидания, а не игровым полем.

Не создавать fake `GameState` для waiting.

### Started

После появления второго игрока вызывается существующий `StartGame`.

### Player identity

Полноценная базовая authentication уже реализована на Stage 16.

На Stage 18 она будет использоваться для пользовательского lifecycle.

### Deck selection

На Stage 17 игрок должен:

- видеть собственные Deck;
- просматривать Deck;
- выбирать Deck;
- подготавливать его к будущему входу в бой.

`bin/rails dev:create_game` остаётся только development/test механизмом и не является будущим пользовательским flow.

---

## 30. AI / Decision Provider

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

Планируемый локальный AI: **Ollama + Qwen3 1.7B**

AI:

- не изменяет `GameState` напрямую;
- не видит скрытые данные;
- не обходит Engine;
- не делает Engine зависимым от Ollama.

---

## 31. Что запрещено

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
- хранить runtime Platoon на основном `field`;
- уплотнять Platoon slots;
- создавать `TechniqueAbility`;
- создавать `HeadquartersAbility`;
- создавать отдельный HQ level;
- создавать отдельный `nation_id` внутри HQ runtime;
- создавать отдельную систему spotting для HQ;
- создавать отдельную систему победы внутри Combat;
- создавать отдельный Draw Action;
- дублировать Draw;
- раскрывать скрытую информацию через `VisibleState`;
- использовать cookies как основное хранилище `GameState`;
- сохранять каждое промежуточное изменение `GameState`;
- использовать dev `player_id` как постоянную authentication;
- использовать `?player_id=` для пользовательской идентификации;
- считать координаты постоянным ID Technique;
- использовать `movement_count` как Counterattack;
- придумывать игровые механики;
- определять Platoon только по номеру slot;
- рассчитывать доступные действия в Stimulus;
- создавать отдельные JS-кнопки поверх существующей системы;
- передавать slot Platoon из UI в `play_card`;
- считать Drag & Drop самостоятельной системой правил;
- использовать CSS/Stimulus как механизм безопасности;
- завершать игру напрямую из UI, JavaScript или Controller в обход `GameEngine`;
- создавать отдельную систему завершения игры для surrender;
- изменять логические координаты `GameState` ради визуальной перспективы;
- преобразовывать координаты игрового поля внутри `VisibleState`;
- использовать CSS `transform: rotate(180deg)` для разворота игрового поля;
- дублировать правила перспективы в Stimulus;
- использовать визуальный порядок клеток как источник их логических координат;
- считать browser session источником игрового состояния;
- использовать одну browser session для одновременной авторизации двух разных игроков при browser-тестировании.

---

## 32. Текущий план дальнейшей реализации

Текущий план проекта:

```text
Stage 1–14    фундамент, Game Engine, правила, карты, Combat, Victory, Seed
Stage 15      Browser UI
Stage 16      Players
Stage 17      Deck
Stage 18      waiting / started game lifecycle
Stage 19      Human vs Human
Stage 20      Decision Provider
Stage 21      AI
Stage 22      Ollama / Qwen3 1.7B
Stage 23      AI testing
Stage 24      Deck Weight
Stage 25+     дальнейшее развитие
```

### Stage 15

Завершён:

```text
15.1  Visible State
15.2  dev player identity
15.3  GamesController / show
15.4  game page
15.5  field
15.6  hand
15.7  End Turn
15.8  PlayCard
15.9  Move
15.10 Attack
15.11 UI geometry
15.12 Turbo / real-time
15.13.1 hand
15.13.2 selection
15.13.3 AvailableActions
15.13.4 mouse / Drag & Drop
15.13.5 hover / click refinement
15.13.6 muted unavailable actions
15.14 Timer
15.15 finished UI + surrender
15.16 Order / Platoon vertical slice
15.17 Player Perspective
```

### Stage 16

Завершён:

```text
16.1  Player model
16.2  Player authentication foundation
16.3  Registration
16.4  Login
16.5  Logout
16.6  current_player
16.7  remove ?player_id=
16.8  Header
16.9  Main pages
16.10 Guest mode
16.11 Development test users / create_game
```

### Stage 16 итог

Реализовано:

- реальный `Player`;
- session-based authentication;
- Registration;
- Login;
- Logout;
- `current_player`;
- защита игровых endpoints через `GamePlayer`;
- публичные Rules / Play / Decks;
- Statistics для авторизованного игрока;
- Guest mode;
- development test game через `bin/rails dev:create_game`;
- отсутствие `?player_id=` в игровом URL;
- тесты.

Последняя полная проверка:

```bash
bin/rails test
```

```text
346 runs, 947 assertions, 0 failures, 0 errors, 0 skips
```

### Следующий этап

**Stage 17 — Deck**

Основная задача:

```text
Player
  ↓
свои Deck
  ↓
просмотр Deck
  ↓
создание / редактирование Deck
  ↓
подготовка выбора Deck
  ↓
Stage 18
```

Не реализовывать waiting / started lifecycle раньше Stage 18.

---

## 33. Stage 17 — Deck

План:

- UI собственных Deck;
- просмотр состава Deck;
- создание Deck;
- редактирование Deck;
- добавление/удаление Card;
- изменение количества копий;
- отображение Nation Deck;
- отображение текущего размера Deck;
- отображение существующих ограничений Deck;
- подготовка выбора Deck для будущего входа в бой.

Guest:

- может просматривать подготовленные тестовые/готовые Deck;
- не может изменять их;
- не может сохранять изменения.

Authenticated Player:

- видит собственные Deck;
- может работать со своими Deck;
- не получает доступа к чужим Deck.

Persistent Deck не изменять во время партии.

Правила Deck должны проверяться сервером.

UI не должен самостоятельно определять допустимость Deck.

---

## 34. Stage 18 — Waiting / Started Game Lifecycle

План:

1. Игрок идентифицирован через authentication.
2. Игрок видит свои Deck.
3. Игрок выбирает Deck.
4. Нажимает «В бой».
5. Создаётся `Game` со статусом `waiting`.
6. Открывается отдельная waiting page.
7. Второй игрок входит в подходящую игру.
8. Создаётся второй `GamePlayer`.
9. Вызывается `StartGame`.
10. `Game` становится `started`.
11. Создаётся `GameState`.
12. Игроки переходят на игровую страницу.

Не создавать отдельный fake `GameState` для ожидания.

---

## 35. Stage 19 — Human vs Human

План:

- полноценный пользовательский flow двух реальных игроков;
- вход двух игроков в одну партию;
- выбор Deck;
- `StartGame`;
- переход из waiting в started;
- работа существующего Turbo real-time flow;
- корректное завершение партии.

---

## 36. Stage 20 — Decision Provider

Создать абстракцию Decision Provider:

- Human;
- AI;
- External API;
- Local model;
- Other provider.

Decision Provider должен выдавать только Action.

Он не должен иметь прямого доступа к `GameState`, который не входит в разрешённую ему `VisibleState`.

---

## 37. Stage 21 — AI

Создать первого AI Decision Provider.

AI должен:

```text
VisibleState
    ↓
Decision
    ↓
Action
    ↓
GameEngine
```

AI не должен:

- менять `GameState`;
- видеть скрытую руку противника;
- видеть скрытую колоду противника;
- обходить `AvailableActions`/Engine;
- содержать копию игровых правил вместо Engine.

---

## 38. Stage 22 — Ollama / Qwen3 1.7B

Планируемая локальная модель:

- Ollama;
- Qwen3 1.7B.

Интеграция должна находиться на уровне Decision Provider.

Game Engine не должен зависеть от Ollama.

---

## 39. Stage 23 — AI testing

План:

- тестирование корректности Action;
- тестирование ограничений `VisibleState`;
- тестирование запрещённых действий;
- тестирование поведения при ошибках Decision Provider;
- проверка, что AI не получает hidden information;
- проверка, что AI не может напрямую изменить `GameState`.

---

## 40. Stage 24 — Deck Weight

После базового AI/testing:

- реализовать правила Deck Weight;
- использовать существующее поле `weight`;
- не смешивать Deck Weight с `price`;
- сервер должен быть источником истины для ограничения Deck.

---

## 41. Порядок работы

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

Для UI работать маленькими шагами.

После существенных изменений UI обязательно проверять результат непосредственно в браузере.

Без явной команды пользователя не изменять файлы проекта.

---

## 42. Текущая контрольная точка

Завершено:

- Stage 1–8
- Stage 9
- Stage 10
- Stage 11
- Stage 12
- Stage 13
- Stage 14
- Stage 15.1
- Stage 15.2
- Stage 15.3
- Stage 15.4
- Stage 15.5
- Stage 15.6
- Stage 15.7
- Stage 15.8
- Stage 15.9
- Stage 15.10
- Stage 15.11
- Stage 15.12
- Stage 15.13.1
- Stage 15.13.2
- Stage 15.13.3
- Stage 15.13.4
- Stage 15.13.5
- Stage 15.13.6
- Stage 15.14
- Stage 15.15
- Stage 15.16
- Stage 15.17
- Stage 16.1
- Stage 16.2
- Stage 16.3
- Stage 16.4
- Stage 16.5
- Stage 16.6
- Stage 16.7
- Stage 16.8
- Stage 16.9
- Stage 16.10
- Stage 16.11

Последняя полная проверка:

```bash
bin/rails test
```

Результат:

```text
346 runs, 947 assertions, 0 failures, 0 errors, 0 skips
```

Дополнительно проверено через браузер:

- регистрация;
- login;
- logout;
- header;
- Guest mode;
- доступ к Rules;
- доступ к Play;
- доступ к Decks;
- ограничение Statistics для гостя;
- доступ Statistics для авторизованного игрока;
- создание development game;
- вход первым development player;
- вход вторым development player;
- игра двумя игроками через разные browser sessions;
- End Turn;
- смена игрока;
- PlayCard;
- Move;
- Attack;
- Timer;
- Turbo;
- Finished UI;
- surrender;
- завершение по уничтожению HQ.

### Текущее состояние

**Stage 15 — ЗАВЕРШЁН**

**Stage 16 — ЗАВЕРШЁН**

waiting / started UI сознательно отложены на Stage 18.

### Продолжать с

**Stage 17 — Deck**

Следующий крупный lifecycle:

```text
Stage 16 — Players
        ↓
Stage 17 — Deck
        ↓
Stage 18 — waiting / started
        ↓
Stage 19 — Human vs Human
        ↓
Stage 20 — Decision Provider
        ↓
Stage 21 — AI
        ↓
Stage 22 — Ollama / Qwen3 1.7B
        ↓
Stage 23 — AI testing
        ↓
Stage 24 — Deck Weight
```

### Архитектурная граница

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
FinishGame / GameState
    ↓
VisibleState
    ↓
Turbo
    ↓
Stimulus
```

Authentication:

```text
browser session
      ↓
current_player
      ↓
GamePlayer
      ↓
Action
      ↓
GameEngine
```

Для AI:

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
