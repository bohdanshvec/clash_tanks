# AGENTS.md

Общаться со мною на русском языке.

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

Не придумывать механики, отсутствующие в GAME_RULES.md.

Новые игровые решения сначала фиксировать в GAME_RULES.md, архитектурные — в AGENTS.md.

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

```ruby
initialize(state, action)
player_exists?
current_player?
player
failure(error)
```

От Base наследуются:

- `Actions::Move`
- `Actions::Attack`
- `Actions::PlayCard`
- `Actions::EndTurn`

Base содержит только техническое устранение дублирования. Игровые правила остаются в соответствующих Actions.

EndTurn получает `current_time`:

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

## 6. Игровое поле

Основное поле: **3 × 5**

- строки: 0..2
- столбцы: 0..4

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

Runtime HQ находится непосредственно в `field`:

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

Runtime Technique находится в `field`:

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

`armor` может быть `nil`, отсутствовать или быть 0. В боевой логике это означает 0.

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

`nation_id` и `name` берутся через Card.

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

TechniqueAbility не используется.

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

### damage_technique

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

- удаляется из `field`;
- помещается в `graveyard` владельца.

### draw_cards

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

Persistent Deck не изменяется во время партии.

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

```json
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
2. Карта удаляется из `hand`.
3. Создаётся runtime Technique.
4. `movement_limit` получает исходный `movement_count`.
5. `movement_count` устанавливается в 0.
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

### HQ firepower

При атаке HQ:

```
HQ firepower + firepower всех активных Platoon
```

После выстрела HQ каждый активный Platoon получает урон, равный собственному firepower.

Уничтоженный Platoon:

- получает HP 0;
- помещается в graveyard;
- его слот становится `nil`;
- остальные слоты не сдвигаются.

### Platoon Armor

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

Если Armor отсутствует, `nil` или 0, Platoon не поглощает урон.

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

Seed является базовым контентом и может быть явно запущен в production. Это не означает автоматический запуск seed при каждом deploy.

## 17. Stage 15 — UI

Stage 15 — функциональный browser vertical slice (браузерный вертикальный срез), а не финальный production UI.

На этом этапе:

- используется обычный HTML;
- Controller передаёт Actions в GameEngine;
- UI не содержит игровых правил;
- основные Actions доступны через браузер;
- визуальная полировка выполняется отдельными этапами;
- Turbo и Stimulus подключаются после завершения базового HTML UI.

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
- [x] 15.11 рефакторинг show, базовая геометрия и отображение характеристик
- [x] 15.16 Order / Platoon UI, единое интерактивное управление и финальная проверка
- [ ] 15.12 Turbo
- [ ] 15.13 Stimulus-подсветка
- [ ] 15.14 Timer
- [ ] 15.15 waiting / started / finished

Практический порядок дальнейшей работы:

```
15.12 Turbo
    ↓
15.13 Stimulus
    ↓
15.14 Timer
    ↓
15.15 waiting / started / finished
```

15.16 был выполнен до Turbo, чтобы завершить базовый HTML vertical slice.

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
redirect
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

и redirect обратно на игру с тем же `player_id`.

Браузерная проверка показала:

- смену текущего игрока;
- изменение номера хода;
- сохранение времени;
- PreparePlayer для нового игрока;
- обязательный Draw.

До Turbo две открытые вкладки не обновляются автоматически.

### 17.6 PlayCard через браузер

15.8 завершён.

Временный HTML UI позволяет разыгрывать все три типа обычных карт.

#### Technique

- выбрать карту;
- выбрать row;
- выбрать column;
- отправить play_card.

#### Order

- выбрать Order;
- выбрать цель для `damage_technique`;
- отправить play_card.

Для `damage_technique` UI показывает только вражеские Technique.

Цель передаётся координатами текущей клетки:

```json
[
  {
    "row": 1,
    "column": 4
  }
]
```

#### Platoon

- выбрать Platoon;
- отправить play_card;
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

После успешного Move:

- исходная клетка становится `nil`;
- Technique переносится в новую клетку;
- `movement_count` уменьшается;
- `Game.state` сохраняется только после успешного Result.

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

Проверяются Engine:

- существование игрока;
- текущий ход;
- корректность координат;
- наличие атакующего;
- принадлежность атакующего;
- наличие цели;
- принадлежность цели;
- дальность;
- специальные правила Technique / SAU / PT-SAU / HQ;
- завершение игры.

Добавлены Controller integration tests для:

- успешной атаки;
- ошибочной атаки;
- запрета атаки для неучастника.

Проверено:

- успешная атака изменяет GameState;
- ошибочная атака возвращает HTTP 422;
- GameState не сохраняется при ошибке;
- неучастник получает HTTP 403;
- UI корректно отправляет Attack Action.

### 17.9 Stage 15.11 — завершён

15.11 завершён.

Выполнен рефакторинг структуры игрового `show.html.erb` и базовой геометрии экрана.

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

Физическое расположение игроков определяется положением их HQ:

- игрок с HQ `[0,4]` находится сверху;
- игрок с HQ `[2,0]` находится снизу.

При этом текущий игрок получает полное содержимое своей руки, а противник — только количество карт.

#### Структура экрана

Реализованы:

- верхняя рука;
- верхнее информационное окно;
- центральное поле 3×5;
- левая планка Platoon;
- правая планка Platoon;
- нижнее информационное окно;
- нижняя рука.

Верхняя и нижняя области используют увеличенную ширину:

```css
width: min(1400px, calc(100% - 40px));
```

и центрируются относительно экрана.

`hand` поддерживает `flex-wrap`, поэтому большое количество карт может занимать несколько строк.

Информационное окно центрировано и находится в одну строку с горизонтальным overflow при необходимости.

#### Поле

Центральное поле реализовано через CSS Grid:

```css
.battlefield {
  width: 100%;
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  grid-template-rows: repeat(3, minmax(0, 1fr));
}

.battlefield__cell {
  aspect-ratio: 1 / 1;
}
```

Игровое поле находится между боковыми планками Platoon.

Основная геометрия экрана считается достаточной для текущего функционального UI. Финальная визуальная полировка не является задачей 15.11.

#### Отображение карт

Название карты отображается всегда:

- в руке;
- на поле;
- на планке Platoon.

**Technique в руке.** Показываются:

- название;
- тип карты;
- Technique type;
- Price;
- HP;
- Firepower;
- Fuel;
- возможность разыграть.

**Order в руке.** Показываются:

- название;
- тип карты;
- Price;
- Ability;
- параметры Ability;
- возможность разыграть.

Для `damage_technique` отображается выбор цели.

**Platoon в руке.** Показываются:

- название;
- тип карты;
- Price;
- HP;
- Firepower;
- Armor;
- Fuel;
- возможность разыграть.

**Technique на поле.** Показываются:

- название;
- Technique type;
- HP;
- Firepower;
- Fuel;
- состояние Attack;
- состояние Counterattack;
- количество оставшихся движений;
- возможность Move;
- возможность Attack.

`movement_count` не используется как характеристика Counterattack.

**Platoon.** Показываются:

- название;
- HP;
- Firepower;
- Armor;
- Fuel.

Platoon остаётся компактным из-за небольшой ширины боковой планки.

**HQ.** Не показываются:

- Type: headquarters;
- отдельная строка Headquarters.

Остаются:

- название HQ;
- HP;
- Firepower;
- Fuel;
- Attack UI для собственного HQ.

**Информационное окно.** Показываются:

- Player;
- Remaining time;
- Resources;
- Deck count;
- Graveyard count;
- End Turn для текущего игрока.

#### Отображение Ability

Для списка Ability в картах руки добавлены отдельные CSS-правила:

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

Это убирает стандартные bullets/отступы и предотвращает переполнение текста Ability в соседние карты.

#### Attack / Counterattack

В ходе 15.11 убран лишний вывод числового `attack_range` как отдельной характеристики UI.

Причина:

- правила Attack определяются Engine;
- `attack_range` не является достаточным описанием фактической возможности атаки;
- UI не должен превращать внутреннее поле runtime state в самостоятельную игровую характеристику.

Не добавлять новые характеристики Attack / Counterattack без необходимости.

### 17.10 Stage 15.12 — следующий этап

Следующая задача: **Turbo**

Цель:

- убрать необходимость полного ручного refresh после Actions;
- подготовить автоматическое обновление игрового экрана;
- сохранить текущую архитектуру Controller → Action → Engine → GameState;
- не переносить игровые правила в Turbo.

Turbo не должен:

- изменять GameState;
- выполнять игровые правила;
- заменять Engine;
- раскрывать скрытый GameState.

Перед началом 15.12 необходимо проверить текущую реализацию show, routes и Controller flow, после чего вносить только необходимые изменения.

### 17.11 Stage 15.13 — Stimulus

Планируется после Turbo.

Цель:

- подсветка доступных элементов;
- более удобное взаимодействие с полем;
- постепенный переход от ручного выбора координат к интерактивному UI.

Stimulus не является источником игровых правил.

### 17.12 Stage 15.14 — Timer

Планируется после Stimulus.

Цель:

- отображение текущего оставшегося времени;
- обновление UI без изменения authoritative GameState;
- корректная работа с уже существующим TurnTimer.

Источник истины по времени остаётся Engine / GameState.

### 17.13 Stage 15.15 — waiting / started / finished

Планируется после Timer.

UI должен различать:

- `waiting`;
- `started`;
- `finished`.

Для `finished` должны отображаться данные `GameState["result"]`.

Не создавать отдельную систему определения победителя в UI.

### 17.14 Stage 15.16 — завершён

15.16 завершён.

Цель этапа была обеспечить полный функциональный HTML UI для основных игровых действий до перехода к Turbo/Stimulus.

Через браузер доступны:

- открытие игры;
- отображение VisibleState;
- End Turn;
- Play Technique;
- Play Order;
- Play Platoon;
- Move Technique;
- Attack Technique;
- Attack HQ.

#### Order UI

Реализовано:

- отображение Order в руке;
- отображение Ability;
- отображение параметров Ability;
- выбор цели для `damage_technique`;
- отправка play_card.

Цели выбираются только среди вражеских Technique.

#### Platoon UI

Реализовано:

- отображение Platoon в руке;
- отображение характеристик;
- кнопка Play Platoon;
- автоматический выбор первого свободного слота Engine.

#### Единое интерактивное управление

На текущем HTML-этапе Actions выполняются через обычные формы:

- PlayCard
- Move
- Attack
- EndTurn

Turbo/Stimulus пока не используются.

#### Финальная проверка 15.16

Проверены:

- Technique;
- Order;
- Platoon;
- Move;
- Attack;
- End Turn;
- ошибочные Actions;
- запрет действий неучастника;
- сохранение state только после успешного Action;
- скрытие информации противника.

Полный тестовый прогон:

```
287 runs, 819 assertions, 0 failures, 0 errors, 0 skips
```

Stage 15.16 считается завершённым.

### 17.15 Controller и UI: границы

Controller может:

- принять HTTP params;
- проверить доступ к Game;
- создать Action;
- передать Action в Engine;
- обработать Result;
- сохранить новый GameState;
- выполнить redirect.

Controller не должен:

- менять HP;
- менять hand;
- размещать Technique;
- рассчитывать Fuel;
- определять победителя;
- менять GameState напрямую;
- обходить Engine.

UI и Stimulus не должны быть источником игровых правил.

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

- PlayCard устанавливает `movement_count` в 0;
- `movement_limit` сохраняет исходное количество движений;
- Move не требует специальных изменений;
- PreparePlayer восстанавливает движение;
- `has_attacked` при выставлении остаётся `false`.

Тесты подтверждают:

- новая Technique получает `movement_count = 0`;
- `movement_limit` сохраняется;
- новая Technique не может двигаться в тот же ход;
- ошибка движения: `No movement remaining`;
- в следующем ходу PreparePlayer восстанавливает движение.

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

Тестовые состояния с JSONB используют строковые `player_id`, так как после сохранения в JSONB идентификаторы представлены строками.

Последний полный зелёный прогон:

```
287 runs, 819 assertions, 0 failures, 0 errors, 0 skips
```

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

- Controllers
- Stimulus
- ActiveRecord models
- UI
- AI

Запрещено:

- изменять GameState напрямую;
- изменять persistent Deck во время партии;
- создавать AR-модели для runtime-объектов без необходимости;
- создавать отдельный Action для Draw без необходимости;
- дублировать механизм Draw;
- создавать TechniqueAbility;
- создавать HeadquartersAbility;
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

- делать Controller или Stimulus источником правил;
- доверять клиентским параметрам без проверки Engine;
- передавать полный скрытый GameState в браузер;
- изменять `Game.state` из JavaScript;
- считать координаты постоянным ID Technique;
- использовать `movement_count` как характеристику Counterattack;
- придумывать UI-характеристики, которых нет в правилах или runtime state.

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

Для Stage 15 работать маленькими шагами и запускать тесты после каждого существенного изменения.

## 21. Текущий статус и контрольная точка

### Завершены

- [x] Stage 1–8
- [x] Stage 9 — PlayCard
- [x] Stage 10 — Resources / Turns
- [x] Stage 11 — Draw / Hand / Graveyard
- [x] Stage 12 — Combat
- [x] Stage 13 — Victory / Defeat
- [x] Stage 14 — Seed / базовый игровой контент
- [ ] Stage 15 — UI, в работе
  - [x] 15.1 Visible State
  - [x] 15.2 dev player identity
  - [x] 15.3 GamesController + GET /games/:id
  - [x] 15.4 минимальная игровая страница
  - [x] 15.5 поле 3×5
  - [x] 15.6 рука игрока
  - [x] 15.7 End Turn
  - [x] 15.8 PlayCard через временный HTML UI
  - [x] 15.9 Move Technique → cell
  - [x] 15.10 Attack Technique → target
  - [x] 15.11 рефакторинг show, базовая геометрия и характеристики
  - [x] 15.16 Order / Platoon UI, единое интерактивное управление и финальная проверка
  - [ ] 15.12 Turbo
  - [ ] 15.13 Stimulus-подсветка
  - [ ] 15.14 Timer
  - [ ] 15.15 waiting / started / finished

### Следующая точка продолжения

**Stage 15.12 — Turbo.**

На момент этой контрольной точки:

- Stage 14 завершён;
- Stage 15.1–15.11 завершены;
- Stage 15.16 завершён;
- базовый HTML vertical slice полностью функционален;
- `show.html.erb` отображает:
  - верхнюю и нижнюю руку;
  - информационные окна;
  - поле 3×5;
  - две планки Platoon;
  - Technique;
  - Order;
  - Platoon;
  - HQ;
  - характеристики карт и объектов;
  - временные формы PlayCard;
  - временные формы Move;
  - временные формы Attack;
  - Attack UI для HQ;
- VisibleState скрывает информацию противника;
- Controller передаёт действия в Engine;
- Engine остаётся единственным арбитром;
- Order и Platoon доступны через браузер;
- новая Technique не может двигаться в ход выставления, но может атаковать;
- полный тестовый прогон зелёный:

```
287 runs, 819 assertions, 0 failures, 0 errors, 0 skips
```

### Следующая задача

Начать **Stage 15.12 — Turbo**.

Основная цель:

```
HTML forms
    ↓
Controller
    ↓
Action
    ↓
Engine
    ↓
GameState
    ↓
Turbo response
    ↓
обновление игрового экрана
```

При этом:

- Engine остаётся единственным источником игровых правил;
- `Game.state` остаётся authoritative snapshot;
- скрытая информация не должна попасть в браузер;
- Turbo не должен содержать игровую логику;
- Stimulus пока не внедрять без необходимости;
- Timer пока не реализовывать;
- состояния waiting / started / finished пока не расширять.

Следовать текущему плану маленькими шагами и после каждого существенного изменения запускать:

```
bin/rails test
```

### Следующие крупные этапы

- Stage 15.12 — Turbo
- Stage 15.13 — Stimulus-подсветка
- Stage 15.14 — Timer
- Stage 15.15 — waiting / started / finished
- Stage 16 — Human vs Human
- Stage 17 — Decision Provider
- Stage 18 — AI
- Stage 19 — Ollama / Qwen3 1.7B
- Stage 20 — AI testing
- Stage 21 — Deck Weight
- Stage 22 — дальнейшее развитие

### Контрольная точка

Проект сейчас находится в следующем состоянии:

```
Stage 1–14     завершены
Stage 15.1–11  завершены
Stage 15.16    завершён
Stage 15.12    следующая задача
```

Браузерный vertical slice позволяет:

- открыть игру;
- видеть VisibleState;
- видеть собственную руку;
- видеть только количество карт противника;
- видеть поле;
- видеть Platoon;
- завершить ход;
- разыграть Technique;
- разыграть Order;
- разыграть Platoon;
- переместить Technique;
- атаковать Technique;
- атаковать через HQ UI.

Последний полный тестовый прогон:

```
287 runs, 819 assertions, 0 failures, 0 errors, 0 skips
```
