# AGENTS.md

Общаться со мною на русском языке.

## 1. Проект

`clash_tanks` — учебная браузерная пошаговая карточная стратегия про танки. Проект вдохновлён WoT: Generals, но использует собственные названия, правила, карты и материалы.

### Стек

- Ruby 3.4.10
- Rails 8.1.3.1
- PostgreSQL
- Hotwire / Turbo / Stimulus
- RVM
- Ubuntu 22.04

### Запуск

```
bin/dev
```

### Development БД

- PostgreSQL
- порт 5432
- `clash_tanks_development`

PostgreSQL 12 и 14 не изменять и не удалять без явного указания.

## 2. Источники истины

- **GAME_RULES.md** — ЧТО делает игра: правила и игровые механики.
- **AGENTS.md** — КАК это реализуется: архитектура, технические решения и текущее состояние разработки.

Старые чаты не имеют приоритета при противоречии с этими файлами.

Не придумывать механики, отсутствующие в `GAME_RULES.md`.

Новые игровые решения сначала фиксировать в `GAME_RULES.md`, архитектурные — в `AGENTS.md`.

## 3. Архитектура

### Основной поток

```
Decision Provider
      ↓
    Action
      ↓
 Game Engine
      ↓
  GameState
```

Decision Provider может быть человеком, локальным AI, внешним API или другим источником.

Game Engine — единственный арбитр игры.

Controllers, UI, JavaScript и AI не изменяют GameState напрямую.

### Action

`GameEngine::Action` содержит:

- `player_id`
- `type`
- `payload`

Action только описывает намерение.

### Result

`GameEngine::Result` содержит:

- успех или ошибку;
- новый GameState;
- события.

Исходный GameState не мутируется. Новый state обычно создаётся через `deep_dup`.

При ошибке новый state не сохраняется.

### Engine

`GameEngine::Engine` маршрутизирует Actions:

```ruby
ACTIONS = {
  "move"      => Actions::Move,
  "attack"    => Actions::Attack,
  "play_card" => Actions::PlayCard,
  "end_turn"  => Actions::EndTurn
}.freeze
```

Engine централизованно:

- проверяет истечение времени текущего игрока;
- запрещает Actions после завершения игры.

После завершения игры известные Actions отклоняются с ошибкой:

```
Game is already finished.
```

Draw не является Action. Draw выполняется внутренними сервисами.

### Actions::Base

Реализован:

```
app/services/game_engine/actions/base.rb
```

Общие методы:

- `initialize(state, action)`
- `player_exists?`
- `current_player?`
- `player`
- `failure(error)`

От Base наследуются:

- `Actions::Move`
- `Actions::Attack`
- `Actions::PlayCard`
- `Actions::EndTurn`

Base содержит только техническое устранение дублирования. Игровые правила остаются в соответствующих Actions.

`EndTurn` получает `current_time`:

```ruby
def initialize(state, action, current_time: Time.current)
  super(state, action)
  @current_time = current_time
end
```

## 4. Game и GameState

`Game.state` — authoritative snapshot (основной снимок состояния) партии, хранится в PostgreSQL JSONB.

После успешного Action Controller сохраняет новый state.

GameState не обращается к ActiveRecord.

### Основные поля GameState

- `status`
- `turn_number`
- `current_player_id`
- `turn_started_at`
- `players`
- `field`
- `result`

### Player state

Игрок может содержать:

- `nation_id`
- `hand`
- `deck`
- `graveyard`
- `platoons`
- `resources`
- `remaining_time`
- `empty_deck_draw_attempts`

Карты в `hand` и текущей `deck` хранятся как полные объекты.

### Иммутабельность

Игровые операции создают новый state, обычно через:

```ruby
state.deep_dup
```

Исходный GameState не изменяется.

## 5. Скрытая информация и VisibleState

Игрок и AI получают только разрешённую правилами информацию.

Нельзя раскрывать:

- руку противника;
- содержимое и порядок колоды противника;
- содержимое кладбища противника;
- ресурсы противника;
- другие запрещённые данные.

Клиентский интерфейс не является механизмом защиты.

### VisibleState

Реализован:

```
app/services/game_engine/visible_state.rb
```

Использование:

```ruby
GameEngine::VisibleState.call(
  state: game.state,
  player_id: player_id
)
```

UI не получает напрямую полный `Game.state`.

#### Собственный игрок

Доступны:

- `nation_id`
- полное содержимое `hand`
- `deck_count`
- `platoons`
- `resources`
- `remaining_time`
- `empty_deck_draw_attempts`
- `graveyard_count`

#### Противник

Доступны:

- `nation_id`
- `hand_count`
- `deck_count`
- `platoons`
- `remaining_time`
- `graveyard_count`

Скрываются:

- содержимое `hand`;
- содержимое и порядок `deck`;
- `resources`;
- содержимое `graveyard`.

`field` является публичным.

VisibleState не изменяет исходный GameState.

### AvailableActions

Реализован:

```
app/services/game_engine/available_actions.rb
```

Использование:

```ruby
GameEngine::AvailableActions.call(
  state: state,
  player_id: player_id
)
```

VisibleState включает результат AvailableActions:

```json
{
  "field": "...",
  "hand": "..."
}
```

AvailableActions является Engine-derived state (состоянием, рассчитанным серверной игровой логикой) для UI.

Stimulus не рассчитывает самостоятельно допустимые действия.

Для текущего игрока AvailableActions предоставляет:

#### Field

Для собственной Technique:

```json
{
  "moves": ["..."],
  "attacks": ["..."]
}
```

Для собственного HQ:

```json
{
  "moves": [],
  "attacks": ["..."]
}
```

Чужие объекты не являются источниками действий.

#### Hand

Для Technique:

```json
{
  "type": "technique",
  "drop_zone": "field",
  "positions": ["..."]
}
```

Для Platoon:

```json
{
  "type": "platoon",
  "drop_zone": "platoon_bar",
  "slots": ["..."]
}
```

Для Order без targeted ability:

```json
{
  "type": "order",
  "drop_zone": "field"
}
```

Для targeted Order:

```json
{
  "type": "order",
  "targets": ["..."]
}
```

Для `damage_technique` targets содержат только вражеские Technique.

AvailableActions учитывает, в частности:

- текущий ход;
- принадлежность объекта;
- наличие свободного движения;
- занятость клеток;
- допустимое движение;
- допустимые цели;
- дальность;
- spotting;
- достаточность ресурсов;
- свободные клетки размещения Technique;
- свободные Platoon slots.

AvailableActions не изменяет GameState.

## 6. Игровое поле

Основное поле: **3 × 5**

- строки: `0..2`
- столбцы: `0..4`

HQ:

- Player 1 → `[2][0]`
- Player 2 → `[0][4]`

Одна клетка содержит максимум один объект.

На основном поле находятся:

- HQ
- Technique

Platoon хранится отдельно от основного field.

За каждым HQ существует 4 Platoon-слота:

```
[nil, nil, nil, nil]
```

После уничтожения Platoon слот становится `nil` и не уплотняется.

## 7. Runtime GameState

### HQ

Runtime HQ находится непосредственно в field:

```json
{
  "type": "headquarters",
  "card_id": 10,
  "player_id": 42,
  "nation_id": 10,
  "name": "Test HQ",
  "hp": 20,
  "firepower": 3,
  "fuel": 5,
  "has_attacked": false,
  "has_counterattacked": false,
  "abilities": []
}
```

`hp`, `firepower`, `fuel` — текущие характеристики партии.

Отдельный `level` не используется. Уровень HQ определяется `Card.weight`.

### Technique

Runtime Technique находится в field:

```json
{
  "type": "technique",
  "card_id": 15,
  "player_id": 42,
  "nation_id": 10,
  "name": "Т-34",
  "technique_type": "medium_tank",
  "hp": 10,
  "firepower": 4,
  "fuel": 2,
  "attack_range": 1,
  "movement_count": 1,
  "movement_limit": 1,
  "movement_type": "diagonal",
  "has_attacked": false,
  "has_counterattacked": false
}
```

В runtime Technique не хранятся:

- `price`
- `weight`
- `card_type`
- вложенный объект `technique`

`movement_count` — оставшиеся движения.

`movement_limit` — максимальное количество движений, восстанавливаемое в начале хода.

Technique, выставленная на поле в текущем ходу, получает:

```
movement_count = 0
movement_limit = исходное количество движений
```

Поэтому:

- в ход выставления двигаться нельзя;
- в ход выставления атаковать можно.

В начале следующего собственного хода PreparePlayer восстанавливает:

```
movement_count = movement_limit
```

### Platoon

Runtime Platoon хранится только здесь:

```
state["players"][player_id]["platoons"]
```

Пример:

```json
{
  "type": "platoon",
  "card_id": 40,
  "player_id": 42,
  "nation_id": 10,
  "name": "Пехотный взвод",
  "firepower": 5,
  "hp": 10,
  "armor": 3,
  "fuel": 2
}
```

Максимум 4 активных Platoon.

`armor` может быть `nil`, отсутствовать или быть `0`. В боевой логике это означает `0`.

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

Game связан:

```ruby
has_many :game_players
has_many :players, through: :game_players
```

Статусы:

- `waiting`
- `started`
- `finished`

Для новой записи устанавливается `waiting`.

Game не содержит игровой логики выполнения Actions.

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

`code` — стабильный уникальный машинный идентификатор карты.

`name` — отображаемое название.

`price` обязателен для обычных карт и может быть `nil` у HQ.

`weight` — уровень/вес карты для колоды. Для HQ используется как уровень HQ.

### Headquarters

Поля:

- `card_id`
- `hp`
- `firepower`
- `fuel`

`nation_id` и `name` берутся через `Card`.

### Technique

Поля:

- `technique_type`
- `attack_range`
- `movement_count`
- `movement_type`
- `firepower`
- `hp`
- `fuel`

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
| light_tank | orthogonal | 2 |
| medium_tank | diagonal | 1 |
| heavy_tank | orthogonal | 1 |
| tank_destroyer | orthogonal | 1 |
| artillery | orthogonal | 1 |

Technique не имеет Armor.

### Platoon

Поля:

- `firepower`
- `hp`
- `armor`
- `fuel`

`firepower >= 0`, поэтому Platoon может иметь нулевую огневую мощь.

### GamePlayer

Связывает:

- Game
- Player
- Nation
- Deck

Уникальная пара:

```
game_id + player_id
```

Также хранит выбранную `headquarters_card`.

## 9. Ability

Используется единая система:

```
Card → CardAbility → Ability
```

`TechniqueAbility` не используется.

### Ability

Поля:

- `code`
- `name`

`code` уникален.

### CardAbility

Поля:

- `card_id`
- `ability_id`
- `parameters`

Пара `card_id + ability_id` уникальна.

В GameState Ability сериализуется без `name`:

```json
{
  "code": "damage_technique",
  "damage": 3
}
```

### Executor

Реализован:

```
GameEngine::Abilities::Executor
```

Текущие способности:

- `damage_technique`
- `draw_cards`

Новая способность добавляется отдельным handler (обработчиком).

#### damage_technique

Реализован:

```
GameEngine::Abilities::DamageTechnique
```

Цель передаётся координатами:

```json
[
  {
    "row": 1,
    "column": 4
  }
]
```

При выполнении повторно проверяются:

- `targets` — массив;
- ровно одна цель;
- целые `row` / `column`;
- координаты находятся в поле;
- на клетке находится Technique;
- Technique принадлежит противнику.

Координаты являются адресом текущей клетки, а не постоянным ID Technique.

При уничтожении Technique:

- удаляется из field;
- помещается в graveyard владельца.

#### draw_cards

Использует общий механизм:

```
Abilities::DrawCards → Cards::Draw
```

## 10. Колоды и StartGame

`Deck` — постоянная колода игрока.

`DeckCard` хранит количество копий.

Ограничения:

- максимум 3 копии одной карты;
- уникальность `deck_id + card_id`;
- карта и колода принадлежат одной Nation.

### StartGame

При старте:

1. Проверяются два GamePlayer.
2. Берутся их Deck.
3. `GameState.cards_from_deck` создаёт полные карты.
4. Колоды перемешиваются.
5. Оба игрока получают по 6 карт.
6. Выбирается первый игрок.
7. Создаётся GameState.
8. Создаются оба runtime HQ.
9. Игра становится `started`.
10. Для первого игрока рассчитывается стартовый Fuel.

Первый игрок не получает дополнительный Draw при StartGame.

Следующий обязательный Draw выполняется при начале следующего хода через PreparePlayer.

## 11. Draw / Hand / Graveyard

Stage 11 завершён.

### Draw

Реализован:

```
GameEngine::Cards::Draw
```

Получает:

- `state`
- `player_id`
- `count`

Каждая попытка Draw обрабатывается отдельно.

Успешный Draw создаёт событие:

```json
{
  "type": "card_drawn",
  "player_id": 42
}
```

Содержимое карты в событии не раскрывается.

### Empty Deck

У игрока:

```
"empty_deck_draw_attempts" => 0
```

При Draw из пустой колоды:

```
counter += 1
HQ HP -= counter
```

То есть:

- 1-я попытка → 1 урон;
- 2-я попытка → 2 урона;
- 3-я попытка → 3 урона.

Если HQ уничтожен, используется:

```
FinishGame(reason: "empty_deck_damage")
```

HP не уменьшается ниже 0.

### Graveyard

В graveyard попадают:

- разыгранные Order;
- уничтоженные Technique;
- уничтоженные Platoon;
- карты, сброшенные игровыми эффектами.

При обычном розыгрыше Technique или Platoon карта в graveyard не попадает.

Восстановление карт правилами не предусмотрено.

## 12. Timer / Resources / Turns

### TurnTimer

Реализован:

```
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

Перед Action Engine проверяет истечение времени.

При истечении:

```
FinishGame(reason: "time_expired")
```

### FuelCalculator

Реализован:

```
GameEngine::Resources::FuelCalculator
```

Fuel текущего игрока:

```
HQ + собственные Technique + собственные Platoon
```

`nil`-слоты Platoon игнорируются.

Неиспользованный Fuel не переносится.

### PreparePlayer

Реализован:

```
GameEngine::Turns::PreparePlayer
```

В начале хода:

```
PreparePlayer
├── восстановление movement_count
├── сброс attack flags Technique
├── сброс attack flags HQ
├── пересчёт Fuel
└── обязательный Draw 1
```

### EndTurn

`GameEngine::Actions::EndTurn`:

1. Проверяет игрока.
2. Проверяет текущий ход.
3. Рассчитывает прошедшее время.
4. Сохраняет оставшееся время.
5. Увеличивает `turn_number`.
6. Переключает `current_player_id`.
7. Обновляет `turn_started_at`.
8. Вызывает PreparePlayer.

Событие:

```json
{
  "type": "turn_ended"
}
```

Исходный state не изменяется.

## 13. PlayCard

Stage 9 завершён.

Реализованы:

- Technique PlayCard;
- Order PlayCard;
- Platoon PlayCard;
- `Card.price`;
- Deck / DeckCard;
- Ability / CardAbility;
- `damage_technique`;
- `draw_cards`;
- атомарное выполнение нескольких Ability;
- graveyard;
- runtime-объекты.

### Technique

Проверяются:

- текущий игрок;
- наличие карты в hand;
- тип Technique;
- достаточный Fuel;
- координаты;
- свободная клетка;
- соседство с собственным HQ.

После успеха:

1. Списывается `price`.
2. Карта удаляется из hand.
3. Создаётся runtime Technique.
4. `movement_limit` получает исходное количество движений.
5. `movement_count` устанавливается в `0`.
6. `has_attacked` остаётся `false`.
7. Создаётся `technique_played`.

Таким образом, новая Technique:

- не может двигаться в ход выставления;
- может атаковать в ход выставления;
- получает полное движение в начале следующего собственного хода.

`Technique.fuel` не является стоимостью розыгрыша.

### Order

Поток:

```
Action
  ↓
PlayCard
  ↓
Abilities::Executor
  ↓
handlers
```

Все Ability выполняются последовательно.

Order атомарен: ошибка любой Ability откатывает весь Order.

При ошибке:

- state не изменяется;
- Order остаётся в hand;
- Fuel не списывается;
- graveyard не изменяется.

После успеха:

- списывается `price`;
- Order удаляется из hand;
- Order помещается в graveyard.

### Platoon

Platoon размещается в первый свободный слот из 4.

При заполненной линии розыгрыш отклоняется.

При успехе:

- списывается `price`;
- карта удаляется из hand;
- создаётся runtime Platoon;
- используется первый свободный слот;
- создаётся `platoon_played`.

Событие `platoon_played` содержит:

```json
{
  "type": "platoon_played",
  "player_id": 42,
  "card_id": 40,
  "name": "Пехотный взвод",
  "slot": 0
}
```

`player_id` используется UI для определения правильной Platoon-полосы.

Обычный Platoon не помещается в graveyard при розыгрыше.

## 14. Combat

Stage 12 завершён.

Основной Action:

```
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

После успешной атаки:

```
has_attacked = true
```

Technique → Technique:

- наносится урон;
- уничтоженная Technique удаляется из field;
- уничтоженная Technique попадает в graveyard;
- выжившая соседняя Technique может контратаковать.

### PT-SAU

`tank_destroyer` стреляет первым.

Если атакующая Technique уничтожена первым выстрелом, её собственный выстрел не выполняется.

### SAU / Spotting

`artillery` может атаковать на дальней дистанции только при spotting.

Источником spotting может быть:

- собственная Technique;
- наш штаб / штаб атакующего игрока.

Для дальней атаки SAU по Technique источник spotting должен находиться рядом с целью.

SAU может атаковать HQ на расстоянии при соответствующем spotting.

Дальняя атака не вызывает counterattack.

Не создавать отдельную систему spotting для HQ.

### HQ

Поддерживаются:

- Technique → HQ;
- SAU → HQ;
- HQ → HQ;
- HQ → Technique.

HQ не контратакует HQ.

При дальней атаке HQ или SAU counterattack не выполняется.

#### HQ firepower

При атаке HQ:

```
HQ firepower + firepower всех активных Platoon
```

После выстрела HQ каждый активный Platoon получает урон, равный собственному firepower.

Уничтоженный Platoon:

- получает HP `0`;
- помещается в graveyard;
- его слот становится `nil`;
- остальные слоты не сдвигаются.

#### Platoon Armor

Входящий урон по HQ проходит:

```
slot 0 → slot 1 → slot 2 → slot 3 → HQ
```

Для Platoon:

```ruby
armor = platoon["armor"].to_i
```

Поглощение:

```ruby
min(remaining_damage, armor)
```

Если Platoon уничтожен, оставшийся урон идёт дальше.

Если Armor отсутствует, `nil` или `0`, Platoon не поглощает урон.

## 15. Victory / Defeat

Stage 13 завершён.

Единый сервис:

```
GameEngine::FinishGame
```

Принимает:

- `state`
- `winner_id`
- `loser_id`
- `reason`

Допустимые причины:

- `headquarters_destroyed`
- `empty_deck_damage`
- `time_expired`

При успехе:

```ruby
new_state["status"] = "finished"

new_state["result"] = {
  "winner_id" => winner_id,
  "loser_id"  => loser_id,
  "reason"    => reason
}
```

Создаётся событие `game_finished`.

FinishGame проверяет:

- игра ещё не завершена;
- winner существует;
- loser существует;
- winner и loser различаются;
- reason допустим.

Повторное завершение запрещено.

Все способы окончания партии используют FinishGame.

## 16. Seed / базовый игровой контент

Stage 14 завершён.

Структура:

```
db/
├── seeds.rb
└── seeds/
    ├── nations.rb
    ├── abilities.rb
    ├── cards.rb
    └── card_abilities.rb
```

`db/seeds.rb` загружает эти четыре файла.

Seed работает только с базовым игровым контентом:

- Nation
- Ability
- Card
- Technique
- Platoon
- Headquarters
- CardAbility

Seed не должен создавать, очищать или изменять:

- Player
- Deck
- DeckCard
- Game
- GamePlayer

Не использовать `destroy_all` / `delete_all` для пользовательских данных.

### Идемпотентность

Базовые записи создаются/обновляются по стабильным ключам, например:

```ruby
find_or_initialize_by(stable_key)
```

Повторный запуск не создаёт дубликаты.

### Базовый контент

Nations:

- `ussr`
- `germany`
- `usa`

Abilities:

- `damage_technique`
- `draw_cards`

Cards:

- 3 HQ
- 18 Technique
- 6 Order
- 6 Platoon

Всего: 33 карты.

CardAbility:

- Germany: 2
- USA: 2
- USSR: 2

Всего: 6 CardAbility.

После seed проверено:

```
Nations:       3
Abilities:     2
Cards:         33
Techniques:    18
Platoons:       6
Headquarters:   3
CardAbilities:  6
```

Seed является базовым контентом и может быть явно запущен в production.

Это не означает автоматический запуск seed при каждом deploy.

## 17. Stage 15 — UI

Stage 15 — функциональный browser vertical slice (браузерный вертикальный срез), а не финальный production UI.

На этом этапе:

- Controller передаёт Actions в GameEngine;
- UI не содержит игровых правил;
- основные Actions доступны через браузер;
- Turbo используется для обновления экрана;
- Stimulus используется для визуального поведения и mouse interaction;
- постепенный переход от HTML-форм к управлению мышью выполняется внутри Stage 15.13.

### 17.1 План Stage 15

- [x] 15.1 Visible State
- [x] 15.2 временный dev player identity
- [x] 15.3 GamesController + GET /games/:id
- [x] 15.4 минимальная страница игры
- [x] 15.5 поле 3×5
- [x] 15.6 рука игрока
- [x] 15.7 End Turn
- [x] 15.8 PlayCard через временный HTML UI
- [x] 15.9 Move Technique → cell
- [x] 15.10 Attack Technique → target
- [x] 15.11 рефакторинг show, базовая геометрия и характеристики
- [x] 15.12 Turbo / real-time
- [ ] 15.13 Stimulus / мышь / визуальный выбор — в работе
- [ ] 15.14 Timer — ожидает завершения 15.13
- [ ] 15.15 waiting / started / finished — ожидает завершения 15.14
- [x] 15.16 Order / Platoon UI, функциональный HTML vertical slice

15.16 был выполнен до Turbo, чтобы завершить базовый HTML vertical slice.

15.16 не означает, что финальное мышиное управление завершено. Переход от временных HTML-форм к мыши реализуется в 15.13.

### 17.2 Временная dev-идентификация

Полноценной авторизации пока нет.

Игрок определяется через:

```
?player_id=1
```

Например:

```
/games/7?player_id=1
```

В ApplicationController:

```ruby
def current_player_id
  params[:player_id]
end

def player_in_game?(game)
  game.game_players.exists?(player_id: current_player_id)
end
```

Контроллер проверяет принадлежность игрока к партии.

Это временный dev-механизм и не является authentication.

### 17.3 GamesController и routes

Создан:

```
app/controllers/games_controller.rb
```

Реализованы:

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

Общий Controller flow:

```
HTTP request
    ↓
проверка Game
    ↓
проверка player_in_game?
    ↓
GameEngine::Action
    ↓
GameEngine::Engine
    ↓
Result
    ↓
Game.update!(state: result.state)
    ↓
Turbo broadcast / redirect
```

Controller не содержит игровых правил.

При ошибке Action:

- GameState не сохраняется;
- возвращается HTTP 422.

### 17.4 show

`GamesController#show`:

1. Загружает Game.
2. Проверяет принадлежность игрока.
3. Создаёт VisibleState.
4. Передаёт его в `show.html.erb`.

При отсутствии `player_id` или если игрок не является GamePlayer:

```
403 Forbidden
```

`show.html.erb` подключает Turbo Stream для конкретного игрока:

```erb
<%= turbo_stream_from [@game, current_player_id] %>
```

Основной контейнер:

```erb
<div id="game-content">
  ...
</div>
```

### 17.5 End Turn

`GamesController#end_turn` передаёт:

```ruby
GameEngine::Action.new(
  player_id: current_player_id,
  type: "end_turn"
)
```

После успешного Action:

```ruby
@game.update!(state: result.state)
```

После сохранения вызывается broadcast обновления игры.

Для Turbo-запроса Controller возвращает:

```
204 No Content
```

Обновление интерфейса выполняется через Turbo Stream broadcast.

Для обычного HTML-запроса сохраняется redirect.

Кнопка End Turn отображается только текущему игроку. Для игрока, чей ход не идёт, кнопка не показывается.

### 17.6 PlayCard через браузер

15.8 завершён.

Временный HTML UI позволяет разыгрывать все три типа обычных карт.

**Technique**

- выбрать карту;
- выбрать row;
- выбрать column;
- отправить `play_card`.

**Order**

- выбрать Order;
- выбрать цель для `damage_technique`;
- отправить `play_card`.

Для `damage_technique` UI показывает только вражеские Technique.

**Platoon**

- выбрать Platoon;
- отправить `play_card`;
- Platoon автоматически занимает первый свободный слот.

Все игровые проверки выполняются Engine.

### 17.7 Move через браузер

15.9 завершён.

Реализован:

```
POST /games/:id/move
```

Controller создаёт:

```ruby
GameEngine::Action.new(
  player_id: current_player_id,
  type: "move",
  payload: {
    from: [from_row, from_column],
    to: [to_row, to_column]
  }
)
```

UI показывает для собственной Technique:

- координаты клетки;
- `movement_count`;
- выбор конечной строки;
- выбор конечного столбца;
- кнопку Move.

Для чужой Technique кнопка Move не показывается.

UI не проверяет правила движения.

`GameEngine::Actions::Move` самостоятельно проверяет:

- существование игрока;
- текущий ход;
- корректность координат;
- наличие Technique;
- принадлежность Technique;
- наличие движения;
- занятость клетки;
- допустимый тип движения;
- допустимое расстояние.

### 17.8 Attack через браузер

15.10 завершён.

Реализован:

```
POST /games/:id/attack
```

Controller создаёт:

```ruby
GameEngine::Action.new(
  player_id: current_player_id,
  type: "attack",
  payload: {
    attacker: [attacker_row, attacker_column],
    target: [target_row, target_column]
  }
)
```

UI позволяет выполнить Attack собственной Technique и собственного HQ.

Attack UI не содержит игровых правил.

Все проверки выполняет:

```
GameEngine::Actions::Attack
```

### 17.9 Stage 15.11 — базовая UI-геометрия

15.11 завершён как этап базовой геометрии и отображения характеристик.

Текущий экран логически состоит из:

```
                верхняя рука
          ┌──────────────────────┐
          │                      │
  верхняя │      поле 3 × 5      │ верхняя
  линия   │                      │ линия
 взводов  └──────────────────────┘ взводов
                нижняя рука
```

Физическое расположение игроков определяется HQ:

- HQ `[0,4]` → верхняя часть;
- HQ `[2,0]` → нижняя часть.

#### Текущая геометрия игровой зоны

Основная игровая зона:

```css
.game-board {
  display: grid;
  grid-template-columns: 100px minmax(600px, 900px) 100px;
  justify-content: center;
  align-items: stretch;
  gap: 10px;
}
```

При максимальной ширине поля:

```
100px + 10px + 900px + 10px + 100px = 1120px
```

Эта ширина используется как ориентир для ширины верхней и нижней руки.

#### Рука

Текущее требование:

- рука занимает практически всю ширину игровой зоны;
- карты находятся в одной горизонтальной линии;
- слева и справа остаётся небольшой внутренний отступ;
- при небольшом количестве карт между ними сохраняется нормальный промежуток;
- когда карты перестают помещаться, расстояние между ними уменьшается;
- при дальнейшем переполнении карты начинают наползать;
- максимальное наползание ограничивается CSS;
- перенос карт на вторую строку не используется;
- hover работает на любой карте;
- hovered card выходит поверх остальных;
- hovered card увеличивается и поднимается вверх.

Текущий принцип ширины руки реализован через CSS-переменную количества карт и адаптивный gap:

```css
.hand {
  display: flex;
  flex-wrap: nowrap;
  justify-content: center;
  align-items: flex-start;
  width: 100%;
  min-width: 0;
  padding: 20px 20px 25px;
  box-sizing: border-box;
  overflow: visible;
  gap: clamp(
    -55px,
    calc((100% - 40px - (var(--hand-count) * 150px)) / (var(--hand-count) - 1)),
    10px
  );
}
```

Важно: при дальнейшем развитии не считать наличие `clamp()` само по себе доказательством завершённости поведения.

Не использовать `100vw` как основу расчёта ширины руки.

#### Отображение карт

Название карты отображается всегда:

- в руке;
- на поле;
- на планке Platoon.

**Technique в руке:**

- название;
- тип карты;
- Technique type;
- Price;
- HP;
- Firepower;
- Fuel.

**Order в руке:**

- название;
- тип карты;
- Price;
- Ability;
- параметры Ability.

**Platoon в руке:**

- название;
- тип карты;
- Price;
- HP;
- Firepower;
- Armor;
- Fuel.

**Technique на поле:**

- название;
- Technique type;
- HP;
- Firepower;
- Fuel;
- состояние Attack;
- состояние Counterattack;
- количество оставшихся движений.

**HQ:**

- название;
- HP;
- Firepower;
- Fuel;
- Attack UI для собственного HQ.

`attack_range` намеренно не отображается как отдельная характеристика.

#### Ability

CSS списка Ability:

```css
.card__stats ul {
  margin: 2px 0 0;
  padding: 0;
  list-style: none;
  width: 100%;
  min-width: 0;
  box-sizing: border-box;
  overflow: hidden;
}

.card__stats li {
  margin: 0;
  padding: 0;
  width: 100%;
  min-width: 0;
  line-height: 1.15;
  overflow: hidden;
  white-space: normal;
  overflow-wrap: anywhere;
  word-break: break-word;
}
```

Убраны стандартные bullets и лишние отступы.

### 17.10 Stage 15.12 — Turbo / real-time

15.12 завершён.

#### Turbo

`application.js`:

```js
import "@hotwired/turbo-rails"
import "controllers"
```

`show.html.erb`:

```erb
<%= turbo_stream_from [@game, current_player_id] %>

<div id="game-content">
  <%= render "game",
             game: @game,
             visible_state: @visible_state,
             current_player_id: current_player_id,
             events: [] %>
</div>
```

В `_game.html.erb` `current_player_id` передаётся явно через locals.

Не использовать:

```ruby
params[:player_id]
```

в `_game.html.erb`, потому что Turbo / Action Cable rendering не должен зависеть от обычных HTTP params.

#### Broadcast

После успешного Action для каждого игрока строится собственный VisibleState:

```ruby
Turbo::StreamsChannel.broadcast_update_to(
  [@game, player_id],
  target: "game-content",
  partial: "games/game",
  locals: {
    game: @game,
    visible_state: visible_state,
    current_player_id: player_id,
    events: result.events
  }
)
```

Используется `broadcast_update_to`.

Не возвращаться к `broadcast_replace_to` для `game-content`, поскольку target-контейнер должен сохраняться.

#### Action Cable

Development:

```yaml
development:
  adapter: async
```

Test:

```yaml
test:
  adapter: test
```

Production:

```yaml
production:
  adapter: solid_cable
```

#### Проверено

Turbo автоматически обновляет второй браузер после:

- End Turn;
- PlayCard;
- Move;
- Attack.

Полный ручной refresh больше не требуется.

### 17.11 Stage 15.13 — Stimulus / мышь / визуальный выбор

Stage 15.13 находится в работе.

Главный принцип:

```
мышь
  ↓
Stimulus
  ↓
Controller
  ↓
GameEngine
  ↓
Result / events
  ↓
GameState
  ↓
VisibleState
  ↓
Turbo
  ↓
Stimulus / UI
```

Stimulus не определяет игровые правила.

#### 17.11.1 Stimulus — визуальные игровые события

Создан Controller:

```
app/javascript/controllers/game_events_controller.js
```

Он подключается к `.game` через:

```erb
data-controller="game-events"
```

События передаются из `_game.html.erb`:

```erb
data-game-events-events-value="<%= events.to_json %>"
```

Обрабатываются:

- `technique_moved`
- `technique_attacked`
- `headquarters_attacked`
- `technique_played`
- `order_played`
- `platoon_played`
- `turn_ended`

**Move**

`technique_moved` подсвечивает:

- исходную клетку;
- конечную клетку.

**Attack**

`technique_attacked` и `headquarters_attacked` подсвечивают:

- источник атаки;
- цель.

Источник должен позволять визуально показать:

- атакующую Technique;
- либо атакующий HQ.

**Technique Play**

`technique_played` подсвечивает клетку, на которую выставлена Technique.

**Order Play**

`order_played` подсвечивает:

- target position;
- либо все позиции из `targets`.

**Platoon Play**

`platoon_played` подсвечивает соответствующий Platoon slot.

Событие содержит `player_id`, поэтому при наличии двух одинаковых slot numbers UI определяет правильную Platoon-полосу по владельцу.

**End Turn**

`turn_ended` временно визуально выделяет изменение хода через:

```
game--turn-changed
```

Общая flash-подсветка:

```css
.game-event--flash {
  animation: game-event-flash 0.5s ease;
}
```

Существующие реакции событий сохранять при дальнейшем развитии 15.13.

#### 17.11.2 Текущий Stimulus Controller

Текущий Controller отвечает за:

- обработку игровых событий;
- визуальный выбор элемента;
- подсветку доступных действий, рассчитанных сервером.

Он не создаёт отдельную систему игровых Action-кнопок.

Текущая логика выбора:

```js
select(event) {
  const element = event.currentTarget

  if (this.selectedElement === element) {
    this.clearSelection()
    return
  }

  this.clearSelection()

  this.selectedElement = element
  element.classList.add("game-object--selected")

  if (element.dataset.cardId) {
    this.showHandAvailableActions(element)
  } else {
    this.showFieldAvailableActions(element)
  }
}
```

`clearSelection()` снимает выбор и очищает подсветку доступных действий.

Визуальный класс:

```css
.game-object--selected {
  outline: 4px solid currentColor;
  outline-offset: 2px;
}
```

Выбор не изменяет GameState.

Важно: Stimulus не должен содержать:

- `actionPanel`;
- `selectedAction`;
- `showActions`;
- `addActionButton`;
- `selectAction`;
- `hideActions`;
- отдельные кнопки Play / Move / Attack, создаваемые JavaScript.

Причина: в UI уже существуют временные HTML-формы действий. Они являются текущим промежуточным механизмом и будут удалены позднее после реализации мышиного управления.

Не создавать второй параллельный набор Action-кнопок через Stimulus.

#### 17.11.3 Выбор карты в руке

Карты в руке используют:

```erb
data-action="click->game-events#select"
```

Также карта содержит:

```erb
data-card-id="<%= card["card_id"] %>"
data-player-id="<%= current_player_id %>"
data-card-type="<%= card["card_type"] %>"
```

`data-player-id` нужен для корректной связи карты с Platoon-полосой её владельца.

Выбор применяется к картам верхней и нижней руки.

Пример:

```erb
<article class="card"
         data-action="click->game-events#select"
         data-card-id="<%= card["card_id"] %>"
         data-player-id="<%= current_player_id %>"
         data-card-type="<%= card["card_type"] %>">
```

Выбор карты:

- визуально выделяет её;
- показывает серверно рассчитанные доступные действия;
- не выполняет Action;
- не меняет GameState;
- не зависит от клиентского расчёта правил.

Недоступная карта также должна продолжать нормально реагировать на hover.

#### 17.11.4 Выбор объектов на поле

Для собственного:

- Technique;
- HQ

обработчик выбора размещён на самой клетке поля:

```erb
<div class="battlefield__cell"
     data-position="<%= row_index %>,<%= column_index %>"
     <% if cell &&
           cell["player_id"].to_s == current_player_id.to_s &&
           ["technique", "headquarters"].include?(cell["type"]) %>
       data-action="click->game-events#select"
       data-object-type="<%= cell["type"] %>"
     <% end %>>
```

`.cell-object` не является источником `data-action`.

Это исправляет проблему, когда выбор не срабатывал при размещении обработчика только на `.cell-object`.

Чужие Technique и HQ не являются источником Action для текущего игрока.

#### 17.11.5 AvailableActions и подсветка

VisibleState передаёт в `_game.html.erb`:

```erb
data-game-events-available-actions-value="<%= visible_state["available_actions"].to_json %>"
```

Stimulus получает эти данные как:

```js
static values = {
  events: Array,
  availableActions: Object
}
```

Stimulus не рассчитывает доступность самостоятельно, а только визуализирует данные AvailableActions.

**Field actions**

Для выбранной собственной Technique подсвечиваются:

```
available_actions["field"][position]["moves"]
available_actions["field"][position]["attacks"]
```

Для собственного HQ:

```
available_actions["field"][position]["attacks"]
```

CSS-классы:

```css
.game-action--move {
  outline: 4px dashed currentColor;
  outline-offset: -4px;
  cursor: pointer;
}

.game-action--attack {
  outline: 4px solid currentColor;
  outline-offset: -4px;
  cursor: pointer;
}
```

**Hand actions**

Для выбранной Technique card подсвечиваются доступные позиции:

```
available_actions["hand"][card_id]["positions"]
```

Для Platoon card подсвечиваются доступные slots:

```
available_actions["hand"][card_id]["slots"]
```

Для Order:

- targeted Order → `targets`;
- Order без target → field drop zone.

CSS:

```css
.game-action--card {
  outline: 4px dashed currentColor;
  outline-offset: -4px;
  cursor: pointer;
}

.game-action--card-target {
  outline: 4px solid currentColor;
  outline-offset: -4px;
  cursor: pointer;
}

.game-action--drop-zone {
  outline: 4px dashed currentColor;
  outline-offset: -4px;
}
```

**Platoon slots**

У каждого Platoon slot есть не только номер, но и владелец:

```erb
data-platoon-slot="<%= index %>"
data-player-id="<%= bottom_player_id %>"
```

или:

```erb
data-platoon-slot="<%= index %>"
data-player-id="<%= top_player_id %>"
```

Это обязательно, потому что у обеих Platoon-полос существуют одинаковые номера:

```
0, 1, 2, 3
```

Stimulus при подсветке ищет slot по двум параметрам:

```
data-platoon-slot
+
data-player-id
```

Благодаря этому слот 0 одного игрока не путается со слотом 0 другого игрока.

Это исправление проверено в браузере.

#### 17.11.6 Временные HTML-формы

Пока остаются существующие формы:

- Play Technique;
- Play Order;
- Play Platoon;
- Move;
- Attack;
- End Turn.

Они являются временным HTML UI.

Не удалять их сейчас.

Они будут удалены после реализации mouse interaction / Drag & Drop.

Не создавать вместо них дублирующие Stimulus-кнопки.

#### 17.11.7 Текущая CSS-очистка Stage 15.13

Для выбора используется:

```css
.game-object--selected {
  outline: 4px solid currentColor;
  outline-offset: 2px;
}
```

Удалены/не должны использоваться старые блоки:

```
.game-action--selected
```

и:

```
.game-actions
.game-actions button
```

если они относятся к удалённой Stimulus action panel.

CSS для существующих временных HTML-форм сохраняется, пока формы используются.

В частности, стили:

```
.cell-object form
```

и формы в информационных блоках не удалять преждевременно.

#### 17.11.8 15.13.1 — Рука

Реализовано и проверено в браузере.

Текущее состояние:

- одна строка реализована;
- hover реализован;
- увеличение и выход вперёд реализованы;
- рамка реализована;
- карты не переходят на вторую строку;
- адаптивный gap реализован;
- наползание при переполнении ограничивается CSS;
- карты корректно отображаются и взаимодействуют с выбором.

Требование остаётся:

```
мало карт
    ↓
нормальные промежутки

много карт
    ↓
уменьшение промежутков

очень много карт
    ↓
наползание
```

Ширина ориентируется на игровую зону:

```
100px + 10px + до 900px + 10px + 100px = до 1120px
```

Рука не должна ориентироваться на `100vw`.

Поведение обязательно проверять непосредственно в браузере:

- при небольшом количестве карт;
- при большом количестве карт.

Не считать CSS-реализацию завершённой только по наличию `clamp()`.

#### 17.11.9 15.13.2 — Выбор карты / объекта

Выполнено.

Реализован визуальный выбор:

- карты в руке;
- собственной Technique;
- собственного HQ.

При выборе:

```
объект
  ↓
game-object--selected
```

При повторном клике выбранный объект снимается.

При выборе другого объекта предыдущий выбор снимается.

Выбор является только UI-состоянием.

#### 17.11.10 15.13.3 — Выбор действия

Завершено.

Реализована связь выбранного объекта с серверно рассчитанными доступными действиями.

Добавлен:

```
GameEngine::AvailableActions
```

VisibleState передаёт:

```
available_actions
```

в UI.

Stimulus после выбора:

- карты
- Technique
- HQ

получает соответствующие данные и визуально подсвечивает допустимые следующие шаги.

Реализовано:

```
Technique card
    ↓
доступные клетки установки

Order
    ↓
targets / field drop zone

Platoon card
    ↓
свободные Platoon slots

Technique
    ↓
Move cells
Attack targets

HQ
    ↓
Attack targets
```

При этом:

- игровые правила не копируются в Stimulus;
- Stimulus только отображает данные AvailableActions;
- GameEngine остаётся источником истины;
- GameState из Stimulus не изменяется;
- отдельная Action panel не создаётся;
- дополнительные Play / Move / Attack кнопки через JavaScript не создаются.

Особенно важно:

- AvailableActions для targeted Order `damage_technique` показывает только вражеские Technique.
- AvailableActions для Platoon показывает свободные slots текущего игрока.

**Исправление Platoon UI**

У обеих Platoon-полос номера slots одинаковые:

```
0, 1, 2, 3
```

Поэтому одного:

```
data-platoon-slot
```

недостаточно.

Используется:

```
data-platoon-slot
data-player-id
```

Карты в руке также содержат:

```
data-player-id
```

При выборе Platoon card Stimulus использует `card.dataset.playerId`, чтобы подсветить Platoon slots именно владельца карты.

При событии:

```
platoon_played
```

Stimulus использует:

```
event.player_id
event.slot
```

чтобы flash применялся к правильной Platoon-полосе.

PlayCard уже передаёт `player_id` в `platoon_played`, поэтому изменение Engine для этого не потребовалось.

Это проверено в браузере для обоих игроков.

#### 17.11.11 15.13.4 — Выбор клетки / цели

Следующая задача.

После завершения 15.13.3 реализовать реальный mouse interaction с подсвеченными клетками и целями.

Нужно сделать:

**Technique card**

```
карта
 ↓
выбор
 ↓
доступные клетки размещения
 ↓
клик по клетке
```

**Technique**

```
Technique
 ├── доступные Move cells
 └── доступные Attack targets
```

**HQ**

```
HQ
 ↓
доступные Attack targets
```

**Order**

```
Order
 ↓
доступные targets / zones
```

**Platoon**

```
Platoon
 ↓
доступный Platoon slot
```

На этом этапе нужно связать уже существующую подсветку с выбором конкретной клетки/цели.

Stimulus не рассчитывает списки самостоятельно.

Данные берутся из:

```
VisibleState
    ↓
AvailableActions
```

Клик по доступному элементу должен привести к подготовке соответствующего Action, а реальное выполнение должно проходить через Controller → GameEngine.

Не переносить игровые проверки в JavaScript.

#### 17.11.12 Drag & Drop

После 15.13.4 реализовать:

**Technique**

```
Technique
   ↓
drag
   ↓
клетка поля
```

**General Order**

```
Order
  ↓
drag
  ↓
поле
```

**Targeted Order**

```
Order
  ↓
drag
  ↓
цель
```

**Platoon**

```
Platoon
  ↓
drag
  ↓
Platoon slot
```

Все реальные действия проходят:

```
Controller → GameEngine
```

Drag & Drop не является обходом Engine.

#### 17.11.13 Недоступные карты

Позже добавить визуальное ослабление карт, которые нельзя использовать в текущем состоянии.

Например:

- недостаточно ресурсов;
- не ваш ход;
- другой запрет Engine.

Даже недоступная карта должна:

- реагировать на hover;
- увеличиваться для просмотра характеристик.

Возможную реакцию при попытке захвата недоступной карты пока не реализовывать.

#### 17.11.14 Ошибочные действия

Пока не вводить отдельную сложную систему обработки HTTP 422 через Stimulus.

Приоритет:

1. mouse selection;
2. визуальное выделение;
3. выбор клетки / цели;
4. Drag & Drop;
5. удаление временных HTML-форм.

#### 17.11.15 Существующие события нельзя потерять

При дальнейшем развитии сохранять:

- Technique played → flash клетки;
- Order played → flash цели;
- Platoon played → flash Platoon slot;
- Technique moved → flash source + destination;
- Attack → flash attacker + target;
- Turn ended → visual turn change.

Новые механизмы выбора мышью должны сосуществовать с этими событиями.

### 17.12 Stage 15.14 — Timer

После завершения основного Stage 15.13.

Цель:

- отображение текущего оставшегося времени;
- обновление UI без изменения authoritative GameState;
- корректная работа с существующим TurnTimer.

Источник истины:

```
GameEngine / GameState
```

Stimulus не должен становиться источником истины времени.

### 17.13 Stage 15.15 — waiting / started / finished

После Timer.

UI должен различать:

- `waiting`;
- `started`;
- `finished`.

Для `finished` отображаются данные:

```
GameState["result"]
```

Не создавать отдельную систему определения победителя в UI.

### 17.14 Stage 15.16 — функциональный HTML UI

15.16 завершён как функциональный этап.

Через браузер доступны:

- открытие игры;
- VisibleState;
- End Turn;
- Play Technique;
- Play Order;
- Play Platoon;
- Move Technique;
- Attack Technique;
- Attack HQ.

Order:

- отображение Ability;
- отображение параметров;
- выбор цели `damage_technique`.

Platoon:

- отображение характеристик;
- Play Platoon;
- автоматический первый свободный слот.

Текущие HTML-формы остаются временным механизмом до завершения мышиного управления Stage 15.13.

### 17.15 Controller и UI: границы

Controller может:

- принять HTTP params;
- проверить доступ к Game;
- создать Action;
- передать Action в Engine;
- обработать Result;
- сохранить новый GameState;
- выполнить redirect или Turbo response;
- инициировать Turbo broadcast.

Controller не должен:

- менять HP;
- менять hand;
- размещать Technique;
- рассчитывать Fuel;
- определять победителя;
- менять GameState напрямую;
- обходить Engine.

UI, Turbo и Stimulus не должны быть источником игровых правил.

Клиентским параметрам нельзя доверять без проверки Engine.

Координаты UI не являются постоянным идентификатором Technique.

### 17.16 Правило движения новой Technique

Зафиксировано в Engine и тестах:

```
PlayCard Technique
        ↓
movement_count = 0
movement_limit = исходное значение
        ↓
в текущий ход:
  Move   ❌
  Attack ✅
        ↓
следующий собственный ход
        ↓
PreparePlayer
        ↓
movement_count = movement_limit
```

Для реализации:

- PlayCard устанавливает `movement_count` в `0`;
- `movement_limit` сохраняет исходное количество движений;
- Move не требует специальных изменений;
- PreparePlayer восстанавливает движение;
- `has_attacked` при выставлении остаётся `false`.

### 17.17 Тесты Stage 15

Controller integration tests проверяют:

- участник игры может открыть её;
- неучастник получает 403;
- отсутствие `player_id` даёт 403;
- успешный Move через Controller изменяет state;
- неуспешный Move возвращает 422 и не изменяет state;
- успешный Attack через Controller изменяет state;
- неуспешный Attack возвращает 422 и не изменяет state;
- неучастник не может выполнить Attack.

AvailableActions tests проверяют:

- отсутствие игрока;
- неправильный ход;
- доступные Move;
- недоступные Move;
- занятую клетку;
- ортогональное движение;
- диагональное движение;
- доступные Attack;
- исключение собственных объектов;
- исключение после `has_attacked`;
- artillery spotting;
- HQ → HQ;
- HQ → Technique;
- отсутствие Move для HQ;
- позиции размещения Technique;
- ограничения ресурсов;
- занятые клетки;
- свободные Platoon slots;
- ограничения ресурсов Platoon;
- Order drop zone;
- targets targeted Order;
- отсутствие раскрытия руки противника;
- неизменность исходного state.

VisibleState tests проверяют:

- собственные и скрытые данные;
- включение `available_actions`;
- пустой результат AvailableActions для неправильного игрока.

Последний полный зелёный прогон:

```
311 runs, 851 assertions, 0 failures, 0 errors, 0 skips
```

После каждого существенного изменения Stage 15 запускать:

```
bin/rails test
```

При изменениях Stimulus/CSS обязательно проверять результат непосредственно в браузере.

## 18. AI / Decision Provider

Планируется заменяемый Decision Provider.

Возможный локальный AI:

```
Ollama + Qwen3 1.7B
```

Архитектура:

```
Visible GameState
      ↓
Decision Provider
      ↓
Action
      ↓
GameEngine
```

AI:

- не изменяет GameState напрямую;
- не видит скрытую информацию;
- не обходит Engine;
- не создаёт зависимость Engine от Ollama.

## 19. Что не делать

Не переносить игровую логику в:

- Controllers;
- Stimulus;
- ActiveRecord models;
- UI;
- AI;
- Turbo / Action Cable.

Запрещено:

- изменять GameState напрямую;
- изменять persistent Deck во время партии;
- создавать AR-модели для runtime-объектов без необходимости;
- создавать отдельный Action для Draw без необходимости;
- дублировать механизм Draw;
- создавать `TechniqueAbility`;
- создавать `HeadquartersAbility`;
- создавать отдельный `level` или `nation_id` в Headquarters;
- хранить runtime Platoon на основном field;
- уплотнять Platoon после уничтожения;
- создавать отдельную систему spotting для HQ;
- переносить победу/поражение обратно в Combat;
- создавать отдельную систему завершения игры внутри Actions;
- дублировать `status`, `result` и `game_finished`;
- выдумывать игровые механики;
- использовать cookies как основное хранилище GameState;
- сохранять каждое промежуточное изменение GameState;
- использовать временный `player_id` как постоянную систему авторизации.

### UI

Не:

- делать Controller, Turbo или Stimulus источником правил;
- доверять клиентским параметрам без проверки Engine;
- передавать полный скрытый GameState в браузер;
- изменять `Game.state` из JavaScript;
- считать координаты постоянным ID Technique;
- использовать `movement_count` как характеристику Counterattack;
- придумывать UI-характеристики, которых нет в правилах или runtime state;
- использовать Turbo broadcast для передачи полного GameState;
- использовать один общий VisibleState для разных игроков;
- возвращаться к `broadcast_replace_to` для `game-content`, если это удаляет сам target-контейнер;
- рассчитывать допустимые Move/Attack/PlayCard действия в Stimulus;
- дублировать правила Engine в JavaScript;
- создавать отдельную Stimulus-систему Play/Move/Attack-кнопок поверх существующих временных HTML-форм;
- удалять временные HTML-формы до завершения соответствующего этапа мышиного управления;
- использовать CSS/Stimulus как единственный механизм защиты от запрещённого действия;
- определять Platoon slot только по номеру без учёта `player_id`;
- рассчитывать доступные клетки, targets или slots непосредственно в Stimulus.

## 20. Порядок работы

Для каждого этапа:

1. Прочитать актуальные AGENTS.md и GAME_RULES.md.
2. Проверить существующую реализацию.
3. Обсудить значительные изменения до написания кода.
4. Внести только необходимые изменения.
5. Добавить/обновить тесты.

Выполнить:

```
bin/rails test
```

6. Проверить соответствие GAME_RULES.md.
7. Обновить AGENTS.md.
8. При необходимости обновить GAME_RULES.md.
9. После значимого этапа сделать отдельный Git commit.

Без явной команды пользователя не изменять файлы проекта.

Для Stage 15 работать маленькими шагами.

После каждого существенного изменения проверять результат непосредственно в браузере.

## 21. Текущий статус и контрольная точка

### Завершены

- [x] Stage 1–8
- [x] Stage 9 — PlayCard
- [x] Stage 10 — Resources / Turns
- [x] Stage 11 — Draw / Hand / Graveyard
- [x] Stage 12 — Combat
- [x] Stage 13 — Victory / Defeat
- [x] Stage 14 — Seed / базовый игровой контент
- [x] Stage 15.1 — Visible State
- [x] Stage 15.2 — dev player identity
- [x] Stage 15.3 — GamesController + GET /games/:id
- [x] Stage 15.4 — минимальная игровая страница
- [x] Stage 15.5 — поле 3×5
- [x] Stage 15.6 — рука игрока
- [x] Stage 15.7 — End Turn
- [x] Stage 15.8 — PlayCard через временный HTML UI
- [x] Stage 15.9 — Move Technique → cell
- [x] Stage 15.10 — Attack Technique → target
- [x] Stage 15.11 — базовая геометрия и характеристики
- [x] Stage 15.12 — Turbo / real-time
- [ ] Stage 15.13 — Stimulus / мышь / визуальный выбор
- [ ] Stage 15.14 — Timer
- [ ] Stage 15.15 — waiting / started / finished
- [x] Stage 15.16 — Order / Platoon UI и функциональный HTML vertical slice

### Внутри Stage 15.13

```
15.13.1  Рука
         → завершено и проверено

15.13.2  Выбор карты / объекта
         → завершено

15.13.3  Выбор действия
         → завершено

15.13.4  Выбор клетки / цели
         → следующая задача

15.13.5  Drag & Drop
         → далее
```

### Уже работает в 15.13

Stimulus визуально реагирует на события:

- `technique_moved`
- `technique_attacked`
- `headquarters_attacked`
- `technique_played`
- `order_played`
- `platoon_played`
- `turn_ended`

Существующие flash-анимации должны сохраняться.

Карты в руке:

- отображаются в одну линию;
- имеют рамку;
- имеют hover;
- при hover выходят вперёд;
- при hover увеличиваются;
- hover работает независимо от доступности карты;
- могут быть выбраны кликом;
- после выбора подсвечивают доступные действия на основании AvailableActions.

Выбор:

- карту в руке можно выбрать;
- собственную Technique можно выбрать;
- собственный HQ можно выбрать;
- выбранный элемент получает `game-object--selected`;
- повторный клик снимает выбор;
- выбор другого элемента снимает предыдущий выбор;
- выбор не изменяет GameState.

AvailableActions:

- передаются через VisibleState;
- доступны Stimulus;
- не вычисляются на клиенте;
- используются для подсветки клеток, целей и Platoon slots.

Для Platoon:

- свободные slots подсвечиваются;
- учитывается `player_id`;
- одинаковые номера slots разных игроков не конфликтуют;
- событие `platoon_played` flash'ит правильный slot.

Временные HTML-формы:

- Play;
- Move;
- Attack;
- End Turn

пока сохраняются.

Stimulus не создаёт отдельные дублирующие кнопки действий.

### Текущая незавершённая задача

Stage 15.13.4 — выбор клетки / цели.

Продолжить от уже работающего:

```
выбранная карта / Technique / HQ
        ↓
AvailableActions
        ↓
подсветка доступных клеток / целей / slots
        ↓
клик по доступному элементу
        ↓
подготовка соответствующего Action
        ↓
Controller
        ↓
GameEngine
```

При этом:

- не создавать вторую систему Action-кнопок;
- не дублировать игровые правила в Stimulus;
- не удалять временные HTML-формы раньше времени;
- не изменять GameState из Stimulus;
- не рассчитывать допустимые действия в JavaScript.

## 22. Следующая точка продолжения

Продолжить: Stage 15.13 — Stimulus / mouse interaction.

Следующий шаг: 15.13.4 — выбор клетки / цели.

Уже реализовано серверное определение доступных действий через:

```
GameEngine::AvailableActions
        ↓
VisibleState
        ↓
Stimulus
```

И уже реализована визуальная подсветка:

```
Technique card
    ↓
placement cells

Order
    ↓
targets / field

Platoon
    ↓
player-specific platoon slots

Technique
    ↓
Move cells / Attack targets

HQ
    ↓
Attack targets
```

Теперь необходимо сделать подсвеченные элементы интерактивными.

### 15.13.4 — целевой сценарий

Для Technique card:

```
выбор карты
    ↓
подсветка доступных клеток
    ↓
клик по клетке
    ↓
подготовка play_card
```

Для Technique:

```
выбор Technique
    ↓
подсветка Move / Attack
    ↓
клик по Move cell
    ↓
подготовка move
```

или

```
клик по Attack target
    ↓
подготовка attack
```

Для HQ:

```
выбор HQ
    ↓
подсветка Attack targets
    ↓
клик по target
    ↓
подготовка attack
```

Для Order:

```
выбор Order
    ↓
подсветка target / field
    ↓
клик по target / zone
    ↓
подготовка play_card
```

Для Platoon:

```
выбор Platoon
    ↓
подсветка slots
    ↓
клик по доступному slot
    ↓
подготовка play_card
```

При реализации не переносить игровые проверки в Stimulus.

Stimulus может определить какой UI-элемент был выбран, но не может самостоятельно решить, разрешено ли действие.

Реальный Action должен пройти через:

```
Controller
    ↓
GameEngine
```

После 15.13.4:

```
15.13.5 — Drag & Drop
```

Затем:

- удалить временные HTML-формы;
- проверить основные действия через мышь;
- сохранить Turbo;
- сохранить Stimulus event reactions.

Только после завершения основного Stage 15.13 переходить к Stage 15.14 Timer.

## 23. Общая контрольная точка проекта

Сейчас проект позволяет:

```
открыть игру
    ↓
получить VisibleState
    ↓
увидеть свою руку
    ↓
увидеть только количество карт противника
    ↓
увидеть поле
    ↓
увидеть Platoon
    ↓
завершить ход
    ↓
разыграть Technique
    ↓
разыграть Order
    ↓
разыграть Platoon
    ↓
переместить Technique
    ↓
атаковать Technique
    ↓
атаковать через HQ
    ↓
получить Turbo-обновление второго браузера
    ↓
получить Stimulus-визуальную реакцию на игровые события
    ↓
выбрать карту в руке
    ↓
выбрать собственную Technique
    ↓
выбрать собственный HQ
    ↓
получить серверно рассчитанные AvailableActions
    ↓
увидеть подсветку доступных клеток / целей
    ↓
увидеть подсветку свободных Platoon slots своего игрока
```

Архитектурная граница сохраняется:

```
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

Engine остаётся единственным источником игровых правил.

Последний полный тестовый прогон:

```
311 runs, 851 assertions, 0 failures, 0 errors, 0 skips
```

Текущая контрольная точка:

```
Stage 1–14       завершены
Stage 15.1–12    завершены
Stage 15.16      завершён
Stage 15.13.1    завершён
Stage 15.13.2    завершён
Stage 15.13.3    завершён
Stage 15.13.4    следующая задача
Stage 15.13.5    далее
Stage 15.14      после 15.13
Stage 15.15      после 15.14
```
