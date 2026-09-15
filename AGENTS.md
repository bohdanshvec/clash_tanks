# AGENTS.md

> Без моей команды не изменять никакие файлы
> Общаться со мною на русском языке

## 1. Проект

**clash_tanks** — учебная браузерная пошаговая карточная стратегия про танки.

Проект вдохновлён WoT: Generals, но использует собственные названия, правила, карты и материалы.

### Стек

- Ruby 3.4.10
- Rails 8.1.3.1
- PostgreSQL 17.x
- Hotwire / Turbo / Stimulus
- RVM
- Ubuntu 22.04
- запуск: `bin/dev`

PostgreSQL проекта работает на порту **5434**.

PostgreSQL 12 и 14 **не изменять и не удалять** без явного указания.

## 2. Источники истины

Используются два основных файла:

- **GAME_RULES.md** — что делает игра: игровые правила и механики.
- **AGENTS.md** — как это реализуется: архитектура, технические решения и состояние разработки.

При противоречии старые сведения из чатов **не имеют приоритета**.

Если реализация противоречит `GAME_RULES.md`, исправляется реализация.

Новые игровые решения сначала фиксируются в `GAME_RULES.md`.
Новые архитектурные решения — в `AGENTS.md`.

Не придумывать игровые механики, которых нет в правилах.

## 3. Архитектура

Основной поток:

```
Decision Provider
      ↓
    Action
      ↓
  Game Engine
      ↓
   GameState
```

Decision Provider может быть:

- человеком;
- локальным AI;
- внешним API;
- другим источником решений.

Decision Provider **только предлагает** Action.

Game Engine — единственный арбитр игры.

AI, контроллеры и клиентский JavaScript **не изменяют** GameState напрямую.

### Action

`GameEngine::Action` содержит намерение игрока:

- `player_id`;
- тип действия;
- параметры действия.

Action не изменяет состояние.

### Result

`GameEngine::Result` содержит:

- успех или ошибку;
- новый GameState;
- события.

Исходный state не мутируется.

При ошибке Result не должен возвращать новое состояние.

### Engine

`GameEngine::Engine` маршрутизирует Action к соответствующему обработчику.

Игровая логика не должна превращаться в один большой класс Engine.

Текущая маршрутизация:

```ruby
ACTIONS = {
  "move" => Actions::Move,
  "attack" => Actions::Attack,
  "play_card" => Actions::PlayCard,
  "end_turn" => Actions::EndTurn
}.freeze
```

Engine также проверяет истечение времени текущего игрока до выполнения его Action.

## 4. Game и GameState

`Game.state` — текущий снимок состояния конкретной партии.

Хранится в PostgreSQL в JSONB.

После успешного действия новый state сохраняется в `Game.state`.

Не нужно сохранять каждое промежуточное изменение.

Клиент и AI передают только Action, а не новый GameState.

### Основные данные GameState

В зависимости от стадии игры state содержит:

- `turn_number`;
- `current_player_id`;
- `turn_started_at`;
- `players`;
- `field`.

Состояние игрока может содержать:

- `nation_id`;
- `hand`;
- `deck`;
- `resources`;
- `remaining_time`;
- `graveyard`;
- `platoons`;
- другие данные, предусмотренные правилами.

Карты в `hand` и текущей `deck` хранятся как полные объекты, а не только как ID.

### Иммутабельность

Игровые операции создают новый state.

Исходный state не изменяется.

Обычно используется `deep_dup`.

GameState не должен обращаться к ActiveRecord.

Actions не должны заново получать изменяемое состояние из базы.

## 5. Скрытая информация

Сервер и Game Engine самостоятельно контролируют информацию, доступную игроку.

Игрок/AI не должен получать:

- руку противника;
- содержимое и порядок колоды противника;
- кладбище противника;
- другую запрещённую правилами скрытую информацию.

Клиентский интерфейс не является механизмом защиты.

AI получает только информацию, доступную соответствующему игроку.

## 6. Игровое поле

Основное поле:

- 3 × 5;
- строки `0..2`;
- столбцы `0..4`.

HQ:

- игрок 1 — `[2][0]`;
- игрок 2 — `[0][4]`.

В одной клетке находится только один объект.

Текущие объекты основного поля:

- HQ;
- Technique.

HQ не перемещается и не может быть назначением движения.

Другая Technique блокирует клетку.

Platoon не является объектом основного поля.

За каждым HQ существует отдельная линия Platoon из 4 слотов.

GameState предоставляет операции над основным полем, но не должен самостоятельно решать игровые правила движения.

### Runtime HQ

HQ хранится непосредственно в `field`, как и другие объекты поля.

Формат:

```ruby
{
  "type" => "headquarters",
  "card_id" => 10,
  "player_id" => 42,
  "nation_id" => 10,
  "name" => "Test HQ",
  "hp" => 20,
  "firepower" => 3,
  "fuel" => 5,
  "abilities" => []
}
```

`hp` в GameState — текущее HP HQ.

`firepower` и `fuel` — текущие характеристики, используемые игровым Engine.

Способности HQ используют общую систему `CardAbility`.

Отдельная система `HeadquartersAbility` не создаётся.

HQ создаётся в GameState при StartGame из выбранной `headquarters_card` каждого GamePlayer.

## 7. Модели

Основные ActiveRecord-модели:

- Game
- Player
- GamePlayer
- Nation
- Card
- Headquarters
- Technique
- Platoon
- Ability
- CardAbility
- Deck
- DeckCard

### GamePlayer

Связывает:

```
Game + Player + Nation + Deck
```

Уникальная пара: `game_id + player_id`

В партии два игрока.

GamePlayer также связан с выбранной `headquarters_card`.

### Nation

Источник данных о нации.

Не создавать новые нации без необходимости.

### Card

Общая сущность карты.

Основные поля:

- `nation`;
- `name`;
- `card_type`;
- `weight`;
- `price`.

Допустимые `card_type`:

- `headquarters`;
- `technique`;
- `order`;
- `platoon`.

`price` — стоимость розыгрыша в fuel.

Для обычных карт `price` обязателен и не может быть отрицательным.

Для HQ `price` может быть `nil`, поскольку HQ не разыгрывается из руки.

`weight` — уровень/вес для формирования и балансировки колоды.

Для HQ `weight` используется как уровень HQ.

Это разные характеристики.

### Headquarters

`Headquarters` — характеристики карты HQ.

Связана с Card отношением:

```
Card
  └── Headquarters
```

Файл модели:

```
app/models/headquarters.rb
```

Таблица:

```
headquarters
```

Поля:

- `card_id`;
- `hp`;
- `firepower`;
- `fuel`.

`nation_id` и `name` отдельно не хранятся — они принадлежат Card.

`level` отдельно не хранится — для этого используется `Card.weight`.

Валидации модели:

- `hp > 0`;
- `firepower >= 0`;
- `fuel >= 0`.

Игровая логика HQ не реализуется в ActiveRecord.

### Technique

Связана с Card.

Поля:

- `technique_type`;
- `attack_range`;
- `movement_count`;
- `movement_type`;
- `firepower`;
- `hp`;
- `fuel`.

Допустимые `technique_type`:

- `light_tank`
- `medium_tank`
- `heavy_tank`
- `tank_destroyer`
- `artillery`

Допустимый `movement_type`:

- `orthogonal`
- `diagonal`

Текущая конфигурация:

| technique_type | movement_type | движений |
|---|---|---|
| light_tank | orthogonal | 2 |
| medium_tank | diagonal | 1 |
| heavy_tank | orthogonal | 1 |
| tank_destroyer | orthogonal | 1 |
| artillery | orthogonal | 1 |

Это игровая логика Engine, а не логика модели.

Technique не имеет Armor.

Модель Technique не реализует:

- бой;
- движение;
- размещение;
- расход ресурсов;
- специальные боевые правила.

### Runtime Technique

При размещении Technique на поле сохраняется также:

```ruby
"movement_limit" => 1
```

`movement_count` — текущее количество оставшихся перемещений в текущем ходу.

`movement_limit` — максимальное количество перемещений, которое Technique получает в начале своего хода.

Пример:

```ruby
{
  "type" => "technique",
  "card_id" => 15,
  "player_id" => 42,
  "nation_id" => 10,
  "name" => "Т-34",
  "technique_type" => "medium_tank",
  "hp" => 10,
  "firepower" => 4,
  "fuel" => 2,
  "attack_range" => 1,
  "movement_count" => 1,
  "movement_limit" => 1,
  "movement_type" => "diagonal",
  "has_attacked" => false,
  "has_counterattacked" => false
}
```

В начале хода владельца:

- `movement_count` восстанавливается до `movement_limit`;
- `has_attacked` сбрасывается в `false`;
- `has_counterattacked` сбрасывается в `false`.

### Platoon

Связан с Card.

Поля:

- `firepower`;
- `hp`;
- `armor`;
- `fuel`.

`name` хранится в Card, а не в Platoon.

Platoon — определение карты в базе данных.

Активный Platoon во время партии хранится только в GameState и может изменять свои характеристики вследствие игровых эффектов.

Platoon не является объектом основного поля.

Одновременно у игрока может быть до 4 активных Platoon.

Runtime-представление:

```ruby
{
  "type" => "platoon",
  "card_id" => 40,
  "player_id" => 42,
  "nation_id" => 10,
  "name" => "Пехотный взвод",
  "firepower" => 5,
  "hp" => 10,
  "armor" => 3,
  "fuel" => 2
}
```

В GameState Platoon хранится в:

```
state["players"][player_id]["platoons"]
```

Формат линии:

```ruby
[nil, nil, nil, nil]
```

Слоты физически сохраняются.

При уничтожении Platoon слот становится `nil`.

Следующий новый Platoon занимает первый свободный слот.

Не выполнять автоматическое уплотнение массива.

## 8. Ability

Система способностей универсальная.

Схема:

```
Card
  ↓
CardAbility
  ↓
Ability
```

`TechniqueAbility` больше не используется.

### Ability

Каталог способностей:

- `name` — название;
- `code` — уникальный машинный код.

### CardAbility

Хранит:

- `card_id`;
- `ability_id`;
- `parameters` JSONB.

Пара `card_id + ability_id` уникальна.

Пример:

```json
{
  "damage": 3
}
```

### Сериализация в GameState

Способности карты сохраняются без `Ability.name`.

Формат:

```ruby
"abilities" => [
  {
    "code" => "damage_technique",
    "damage" => 3
  }
]
```

Используются `code` и параметры.

В GameState не добавлять `name` способности.

### Executor

Реализован:

```
GameEngine::Abilities::Executor
```

Executor получает:

- `state`;
- способность;
- `player_id`;
- `targets`.

Он выбирает обработчик по `Ability.code`.

Текущий обработчик:

- `damage_technique`

Новая способность должна добавляться отдельным обработчиком, а не через разрастание PlayCard.

## 9. Колоды

`Deck` — постоянная сохранённая колода игрока.

`DeckCard` хранит количество копий карты.

Ограничения:

- одна карта — до 3 копий;
- `DeckCard` уникален по `deck_id + card_id`;
- карта и колода должны принадлежать одной нации.

Persistent Deck не изменяется во время партии.

Текущие рука и колода партии находятся в GameState.

### StartGame

При начале партии:

1. проверяется `waiting`;
2. должны быть два GamePlayer;
3. берутся их Deck;
4. `GameState.cards_from_deck` создаёт полные карты;
5. колоды перемешиваются;
6. первые 6 карт идут в руку;
7. остальные — в текущую deck;
8. выбирается случайный первый игрок;
9. создаётся GameState;
10. создаются runtime HQ обоих игроков;
11. Game переводится в `started`;
12. для выбранного первого игрока рассчитывается стартовый Fuel.

Persistent Deck после этого не изменяется.

HQ выбирается через `GamePlayer.headquarters_card`.

Характеристики HQ берутся из связанной записи Headquarters.

## 10. Форматы карт в GameState

Базовая карта:

```ruby
{
  "card_id" => 15,
  "name" => "Т-34",
  "card_type" => "technique",
  "nation_id" => 10,
  "weight" => 1,
  "price" => 2
}
```

Для HQ:

```ruby
{
  "card_id" => 10,
  "name" => "Test HQ",
  "card_type" => "headquarters",
  "nation_id" => 10,
  "weight" => 1,
  "price" => nil
}
```

HQ не является обычной картой руки и автоматически размещается на поле при старте партии.

Technique дополнительно содержит:

```ruby
"technique" => {
  "technique_type" => "medium_tank",
  "attack_range" => 1,
  "movement_count" => 1,
  "movement_type" => "diagonal",
  "firepower" => 4,
  "hp" => 10,
  "fuel" => 2
}
```

Platoon дополнительно содержит:

```ruby
"platoon" => {
  "firepower" => 5,
  "hp" => 10,
  "armor" => 3,
  "fuel" => 2
}
```

Order не имеет вложенного `technique` или `platoon`.

### Technique на поле

```ruby
{
  "type" => "technique",
  "card_id" => 15,
  "player_id" => 42,
  "nation_id" => 10,
  "name" => "Т-34",
  "technique_type" => "medium_tank",
  "hp" => 10,
  "firepower" => 4,
  "fuel" => 2,
  "attack_range" => 1,
  "movement_count" => 1,
  "movement_limit" => 1,
  "movement_type" => "diagonal",
  "has_attacked" => false,
  "has_counterattacked" => false
}
```

На поле не должны находиться:

- `price`;
- `weight`;
- `card_type`;
- вложенный объект `technique`.

`movement_count` на поле — оставшееся количество перемещений.

`movement_limit` — лимит восстановления движения в начале хода владельца.

### HQ на поле

HQ хранится непосредственно в клетке поля:

```ruby
{
  "type" => "headquarters",
  "card_id" => 10,
  "player_id" => 42,
  "nation_id" => 10,
  "name" => "Test HQ",
  "hp" => 20,
  "firepower" => 3,
  "fuel" => 5,
  "abilities" => []
}
```

В runtime HQ характеристики являются текущими характеристиками объекта партии.

`hp` — текущее HP.

HQ не содержит `price`.

HQ не содержит отдельный `level`; его уровень определяется `Card.weight`.

### Platoon в GameState

Platoon не помещается в `field`.

Он находится в:

```
state["players"][player_id]["platoons"]
```

Пример:

```ruby
"platoons" => [
  {
    "type" => "platoon",
    "card_id" => 40,
    "player_id" => 42,
    "nation_id" => 10,
    "name" => "Пехотный взвод",
    "firepower" => 5,
    "hp" => 10,
    "armor" => 3,
    "fuel" => 2
  },
  nil,
  nil,
  nil
]
```

## 11. Graveyard

У каждого игрока:

```ruby
"graveyard" => []
```

Кладбище хранит полное состояние соответствующих карт.

Туда могут попадать:

- разыгранные Order;
- уничтоженные Technique;
- уничтоженные Platoon;
- карты, сброшенные игровыми эффектами.

При обычном успешном розыгрыше Technique или Platoon карта не попадает в graveyard.

Восстановление карт текущими правилами не предусмотрено.

Кладбище скрыто от игрока и противника согласно `GAME_RULES.md`.

## 12. Таймер хода

Каждый игрок имеет независимое оставшееся игровое время.

Начальное значение:

```ruby
10.minutes.to_i
```

GameState содержит:

```
"turn_started_at"
```

`turn_started_at` — момент начала текущего хода.

У каждого игрока:

```ruby
"remaining_time" => 600
```

### TurnTimer

Реализован:

```
GameEngine::TurnTimer
```

Он:

- определяет прошедшее время текущего хода;
- проверяет истечение времени;
- вычисляет оставшееся время после завершения хода.

Таймер использует время текущего игрока.

Вычитание времени выполняется только для текущего игрока.

### Engine

Перед Action текущего игрока Engine проверяет:

**Time expired**

Если время истекло, Action не выполняется.

На Stage 10 завершение игры из-за истечения времени не реализуется.

Определение победителя/проигравшего относится к Stage 13.

## 13. Resources / Fuel

### FuelCalculator

Реализован:

```
GameEngine::Resources::FuelCalculator
```

Он рассчитывает Fuel текущего игрока по его активным объектам.

В расчёт входят:

- Fuel собственного HQ;
- Fuel собственных Technique на поле;
- Fuel собственных Platoon.

Противоположные объекты не учитываются.

`nil`-слоты Platoon игнорируются.

Пример:

```
HQ 5
+ Technique 2
+ Technique 3
+ Platoon 3
= 13 Fuel
```

FuelCalculator не изменяет переданный GameState.

### Начало партии

При StartGame:

1. создаётся GameState;
2. создаются оба HQ;
3. выбирается первый игрок;
4. для первого игрока рассчитывается начальный Fuel.

Другой игрок на момент старта получает `resources = 0`.

### Начало нового хода

При переходе хода Fuel нового текущего игрока пересчитывается заново.

Текущее значение `resources` заменяется рассчитанным значением.

Это означает, что неиспользованный Fuel предыдущего хода не переносится автоматически.

Дополнительные эффекты Fuel будут реализовываться отдельными игровыми механиками согласно `GAME_RULES.md`.

## 14. Подготовка нового хода

Реализован сервис:

```
GameEngine::Turns::PreparePlayer
```

Он получает:

- `state`;
- `player_id`.

Создаёт новый state через `deep_dup`.

Для всех Technique данного игрока:

```ruby
movement_count = movement_limit
has_attacked = false
has_counterattacked = false
```

Technique противника не изменяются.

После восстановления состояния Technique пересчитывается Fuel нового игрока через:

```
GameEngine::Resources::FuelCalculator
```

PreparePlayer не изменяет исходный GameState.

## 15. Реализованные действия

### Move

Проверяет:

- игрок существует;
- сейчас его ход;
- координаты корректны;
- в source находится Technique;
- Technique принадлежит игроку;
- осталось движение;
- destination свободен;
- направление допустимо для типа техники.

Успешное действие:

- очищает source;
- помещает Technique в destination;
- уменьшает `movement_count` на 1.

State не мутируется.

### Attack

Реализована базовая система боя:

- проверка владельца и цели;
- обычная дальность;
- огневой урон;
- уничтожение Technique;
- counterattack;
- ограничения атак за ход;
- `has_attacked`;
- `has_counterattacked`;
- специальные правила PT-SAU;
- PT-SAU против PT-SAU;
- HQ-HQ;
- HQ против Technique через условие дальней атаки САУ.

Полная боевая система ещё развивается по этапам.

### EndTurn

Проверяет:

- игрок существует;
- сейчас его ход;
- время текущего игрока ещё не истекло.

При успешном завершении:

- вычисляется фактически прошедшее время;
- оно вычитается из `remaining_time` текущего игрока;
- увеличивается `turn_number`;
- переключается `current_player_id`;
- обновляется `turn_started_at`;
- вызывается `GameEngine::Turns::PreparePlayer` для нового текущего игрока;
- восстанавливается движение его Technique;
- сбрасываются `has_attacked` и `has_counterattacked`;
- рассчитывается его новый Fuel;
- создаётся событие `turn_ended`.

Исходный state не мутируется.

Mandatory draw при переходе хода пока не выполняется.

Он относится к Stage 11.

## 16. Stage 9 — PlayCard

Stage 9 завершён.

Реализованы:

- `Card.price`;
- `Technique.firepower`;
- `Technique.hp`;
- `Technique.fuel`;
- `Platoon.firepower`;
- `Platoon.hp`;
- `Platoon.armor`;
- `Platoon.fuel`;
- Headquarters;
- persistent Deck;
- DeckCard;
- `GamePlayer.deck`;
- `GamePlayer.headquarters_card`;
- создание текущих deck и hand через `GameState.cards_from_deck`;
- перемешивание deck;
- начальная рука;
- graveyard;
- универсальная система Ability;
- CardAbility;
- `CardAbility.parameters`;
- сериализация Ability в GameState;
- `Actions::PlayCard`;
- маршрутизация `"play_card"` в Engine;
- Technique PlayCard;
- Order PlayCard;
- Platoon PlayCard;
- `damage_technique`;
- атомарное выполнение нескольких Ability Order.

### 16.1. PlayCard — Technique

Для Technique используется Action:

```ruby
Action.new(
  type: "play_card",
  player_id: 42,
  payload: {
    card_id: 20,
    row: 1,
    column: 1
  }
)
```

Проверяется:

- игрок существует;
- сейчас его ход;
- карта находится в руке;
- карта является Technique;
- хватает resources для `card.price`;
- координаты корректны;
- клетка свободна;
- клетка находится рядом с собственным HQ.

Для HQ `[2][0]` допустимы:

```
[1][0]
[1][1]
[2][1]
```

При успешном розыгрыше:

- списывается `price`;
- удаляется ровно одна копия карты из hand;
- создаётся объект Technique на поле;
- `movement_limit` устанавливается равным исходному `movement_count`;
- создаётся событие `technique_played`;
- исходный state не изменяется.

Если размещение невозможно:

- карта остаётся в руке;
- resources не изменяются;
- исходный state не изменяется.

При дубликатах `card_id` удаляется только одна копия.

`Technique.fuel` не является стоимостью розыгрыша.

### 16.2. PlayCard — Order

Order разыгрывается через:

```
Action
  ↓
PlayCard
  ↓
Abilities::Executor
  ↓
конкретные Ability handlers
```

Action для Order использует `targets`:

```ruby
Action.new(
  type: "play_card",
  player_id: 42,
  payload: {
    card_id: 20,
    targets: [
      { row: 1, column: 2 }
    ]
  }
)
```

Количество и смысл `targets` определяется конкретной способностью.

**Проверки Order**

Перед выполнением проверяется:

- игрок существует;
- сейчас его ход;
- карта находится в руке;
- хватает resources для `card.price`;
- у Order есть хотя бы одна Ability.

Если Ability отсутствует, Order не разыгрывается.

**Выполнение Ability**

Abilities выполняются последовательно.

Например:

```
Order
 ├─ damage_technique
 └─ damage_technique
```

Вторая способность получает состояние, созданное первой.

Каждый успешный handler возвращает новый state.

PlayCard не изменяет исходный state.

**Атомарность Order**

Розыгрыш Order является атомарным.

Если Order содержит несколько способностей и одна из последующих способностей завершается ошибкой:

```
Order
 ├─ Ability 1 → успешно
 ├─ Ability 2 → ошибка
 └─ весь Order → ошибка
```

изменения Ability 1 не сохраняются.

При таком отказе:

- исходный GameState не изменяется;
- изменения предыдущих Ability откатываются;
- Order остаётся в hand;
- price не списывается;
- Order не попадает в graveyard.

Это достигается тем, что промежуточные состояния Ability существуют только локально:

```ruby
current_state = @state

abilities.each do |ability|
  result = Executor.new(...).call

  return failure(result.error) unless result.success?

  current_state = result.state
end
```

Только после успешного выполнения всех Ability выполняются:

- удаление Order из hand;
- списание price;
- помещение полного Order в graveyard.

**Успешный Order**

```
hand
  ↓
Order
  ↓
Abilities
  ↓
успех всех Ability
  ↓
price списан
  ↓
Order удалён из hand
  ↓
Order помещён в graveyard
```

### 16.3. Ability damage_technique

Первая реализованная Ability:

```
damage_technique
```

Она:

- требует одну target;
- проверяет координаты;
- требует наличие Technique;
- запрещает атаковать собственную Technique;
- уменьшает HP цели на величину damage;
- при HP <= 0 уничтожает Technique;
- помещает уничтоженную Technique в graveyard;
- очищает её клетку.

Ability работает через:

```
GameEngine::Abilities::Executor
```

Executor выбирает handler по:

```
ability["code"]
```

Не использовать названия карт или `card_type` для выбора обработчика способности.

### 16.4. PlayCard — Platoon

Platoon является отдельным типом карты.

Он не помещается на основное поле.

Для каждого игрока в GameState существует линия из 4 слотов:

```ruby
"platoons" => [nil, nil, nil, nil]
```

Action:

```ruby
Action.new(
  type: "play_card",
  player_id: 42,
  payload: {
    card_id: 40
  }
)
```

При успешном розыгрыше:

- проверяется наличие игрока;
- проверяется ход игрока;
- карта должна находиться в руке;
- проверяется price;
- находится первый свободный слот;
- списывается price;
- удаляется ровно одна копия карты из hand;
- создаётся runtime-объект Platoon;
- объект помещается в первый свободный слот;
- создаётся событие `platoon_played`;
- исходный state не изменяется.

Если все четыре слота заняты, новый Platoon не разыгрывается.

При отказе:

- карта остаётся в hand;
- price не списывается;
- существующие Platoon не изменяются;
- новый state не возвращается.

При обычном розыгрыше Platoon не попадает в graveyard.

Боевые свойства Platoon здесь не реализуются.

В частности, PlayCard не отвечает за:

- добавление firepower Platoon к HQ;
- Armor;
- распределение урона;
- каскадный урон;
- уничтожение Platoon;
- отправку уничтоженного Platoon в graveyard.

Эти механики относятся к последующим этапам боевой системы.

## 17. Stage 9 — тесты

Stage 9 завершён.

Проверяются:

### Technique

- успешный розыгрыш;
- удаление карты из руки;
- списание price;
- удаление только одной копии;
- неизменность исходного state;
- неправильный ход;
- отсутствующая карта;
- недостаток resources;
- занятая клетка;
- некорректные координаты;
- клетка вне зоны HQ;
- соседство с вражеским HQ.

### Order

- Order без Ability не разыгрывается;
- успешный Order с Ability;
- списание price;
- перемещение Order в graveyard;
- ошибка Ability не позволяет разыграть Order;
- несколько Ability выполняются последовательно;
- ошибка последующей Ability откатывает ранее выполненную Ability;
- при ошибке Order не изменяет исходный state.

### Platoon

- успешный розыгрыш в первый слот;
- создание правильного runtime-объекта;
- удаление карты из hand;
- списание price;
- последовательное заполнение слотов;
- использование первого свободного слота;
- сохранение остальных занятых слотов;
- отказ при четырёх занятых слотах;
- неизменность исходного state;
- отсутствие Platoon в graveyard после розыгрыша.

### Headquarters

Проверяются:

- корректное создание HQ;
- связь Headquarters с Card;
- связь Card с HQ;
- положительное HP;
- неотрицательное firepower;
- неотрицательное fuel;
- возможность HQ иметь `price: nil`.

## 18. Stage 10 — Resources / Turns

Stage 10 завершён.

Реализованы:

- `TURN_TIME = 10.minutes.to_i`;
- `turn_started_at`;
- `remaining_time` для каждого игрока;
- `GameEngine::TurnTimer`;
- проверка истечения времени текущего игрока в Engine;
- списание прошедшего времени при EndTurn;
- переключение `current_player_id`;
- увеличение `turn_number`;
- обновление `turn_started_at`;
- создание runtime HQ при StartGame;
- стартовый Fuel первого игрока;
- `GameEngine::Resources::FuelCalculator`;
- Fuel от HQ;
- Fuel от собственных Technique;
- Fuel от собственных Platoon;
- `GameEngine::Turns::PreparePlayer`;
- восстановление `movement_count`;
- `movement_limit`;
- сброс `has_attacked`;
- сброс `has_counterattacked`;
- пересчёт Fuel при начале нового хода;
- переход хода через EndTurn;
- сохранение иммутабельности GameState.

### Fuel

Расчёт текущего Fuel:

```
HQ
+
собственные Technique
+
собственные Platoon
```

Неиспользованный Fuel автоматически не переносится на следующий ход.

При начале нового хода ресурсы нового текущего игрока пересчитываются заново.

### PreparePlayer

Сервис:

```
GameEngine::Turns::PreparePlayer
```

отвечает за подготовку нового текущего игрока:

```
PreparePlayer
├── восстановление movement_count
├── сброс attack flags
└── пересчёт Fuel
```

### EndTurn

EndTurn выполняет переход от текущего игрока к следующему и вызывает PreparePlayer.

Mandatory draw в EndTurn не реализуется.

Он относится к Stage 11.

### Тесты Stage 10

Тесты PreparePlayer:

```
5 tests
12 assertions
0 failures
0 errors
0 skips
```

Тесты EndTurn:

```
9 tests
23 assertions
0 failures
0 errors
0 skips
```

Полный набор тестов после завершения Stage 10:

```
207 tests
542 assertions
0 failures
0 errors
0 skips
```

Stage 10 считается завершённым при этом зелёном полном прогоне.

## 19. Что ещё не реализовано

Основные будущие этапы:

```
Stage 11 — Draw / Hand / Graveyard     ← текущий следующий
Stage 12 — Combat Completion
Stage 13 — Victory / Defeat
Stage 14 — UI
Stage 15 — Human vs Human
Stage 16 — Decision Provider
Stage 17 — AI
Stage 18 — Ollama / Qwen3 1.7B
Stage 19 — AI testing
Stage 20 — Deck Weight
Stage 21 — дальнейшее развитие
```

### Stage 11

- обязательный draw в начале хода;
- дополнительные карты;
- обработка пустой колоды;
- нарастающий урон HQ при попытках draw из пустой колоды;
- дальнейшая работа с hand/graveyard.

**Важно:** mandatory draw ещё не реализован в PreparePlayer и EndTurn.

### Stage 12

- оставшиеся правила артиллерии;
- полные правила HQ;
- Platoon;
- Armor;
- каскадный урон;
- полное уничтожение HQ;
- оставшиеся боевые механики из GAME_RULES.md.

### Stage 13

- победа;
- поражение;
- завершение партии;
- победа при достижении условий из GAME_RULES.md.

## 20. AI

Планируется локальный AI через Ollama:

```
Qwen3 1.7B
```

AI должен быть заменяемым.

Engine не должен зависеть от Ollama.

AI получает разрешённую информацию о партии и возвращает Action.

AI не имеет права:

- напрямую менять GameState;
- видеть скрытую информацию противника;
- обходить проверки Engine.

## 21. Ограничения разработки

Не делать:

- игровую логику в контроллерах;
- игровую логику в Stimulus;
- прямое изменение GameState AI;
- зависимость Engine от конкретного AI;
- передачу скрытой информации клиенту/AI;
- правила игры в ActiveRecord validations;
- отдельные AR-модели для runtime-объектов поля без необходимости;
- повторное создание Deck/DeckCard внутри партии;
- изменение persistent Deck во время игры;
- запись каждого промежуточного состояния в БД;
- cookies как основное хранилище состояния;
- выдумывание механик, отсутствующих в GAME_RULES.md.

Не создавать отдельную систему способностей для HQ — используется существующая `CardAbility`.

Не создавать отдельный level для HQ — используется `Card.weight`.

Не создавать отдельный `nation_id` в Headquarters — нация определяется через Card.

Не усложнять архитектуру без необходимости.

## 22. Порядок работы над этапом

Для каждого этапа:

1. прочитать актуальные `AGENTS.md` и `GAME_RULES.md`;
2. определить текущий этап;
3. проверить существующую реализацию;
4. обсудить план значительных изменений до написания кода;
5. внести только необходимые изменения;
6. добавить или обновить тесты;
7. выполнить:

```
bin/rails test
```

8. проверить соответствие `GAME_RULES.md`;
9. обновить `AGENTS.md`;
10. при необходимости обновить `GAME_RULES.md`;
11. сделать отдельный Git commit после значимого этапа.

При изменении существующего файла при необходимости предоставлять его полностью, чтобы файл можно было заменить без ручного поиска фрагментов.

## 23. Текущая контрольная точка

Stage 1–10 завершены.

Текущий следующий этап:

**Stage 11 — Draw / Hand / Graveyard**

Последний полный зелёный прогон:

```
207 tests
542 assertions
0 failures
0 errors
0 skips
```

Текущее состояние Stage 10 полностью включает:

- таймер;
- `turn_started_at`;
- `remaining_time`;
- TurnTimer;
- проверку истечения времени;
- HQ в GameState;
- создание HQ при StartGame;
- стартовый Fuel;
- FuelCalculator;
- Fuel от HQ;
- Fuel от Technique;
- Fuel от Platoon;
- PreparePlayer;
- восстановление движения Technique;
- movement_limit;
- сброс has_attacked;
- сброс has_counterattacked;
- пересчёт Fuel при начале нового хода;
- полный переход хода через EndTurn.

Stage 11 должен добавить обязательный draw в начале хода.

При реализации Stage 11 необходимо учитывать:

- EndTurn уже подготавливает нового текущего игрока через PreparePlayer;
- PreparePlayer уже отвечает за восстановление состояния Technique и Fuel;
- mandatory draw не должен дублировать эту ответственность;
- empty deck и нарастающий урон HQ должны реализовываться в рамках Stage 11;
- не переносить сюда победу/поражение из-за уничтожения HQ или времени — это Stage 13.

Перед продолжением разработки необходимо снова сверить актуальные:

- AGENTS.md;
- GAME_RULES.md.

Не считать старые сообщения чата источником истины, если они противоречат этим файлам.

**Главный принцип:**

```
GAME_RULES.md = ЧТО
AGENTS.md     = КАК
```

- Game Engine — арбитр.
- Decision Provider — источник Action.
- Game.state — текущее состояние партии.
- Client/AI — только Action.
