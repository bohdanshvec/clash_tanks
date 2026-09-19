# AGENTS.md

> Общаться со мною на русском языке.

## 1. Проект

**clash_tanks** — учебная браузерная пошаговая карточная стратегия про танки. Проект вдохновлён WoT: Generals, но использует собственные названия, правила, карты и материалы.

### Стек

- Ruby 3.4.10
- Rails 8.1.3.1
- PostgreSQL
- Hotwire / Turbo / Stimulus
- RVM
- Ubuntu 22.04
- запуск: `bin/dev`

Текущее подключение Rails к development БД проверено через ActiveRecord: PostgreSQL, порт **5432**, БД `clash_tanks_development`.

PostgreSQL 12 и 14 **не изменять и не удалять** без явного указания.

## 2. Источники истины

- **GAME_RULES.md** — ЧТО делает игра: правила и механики.
- **AGENTS.md** — КАК это реализуется: архитектура, технические решения и состояние разработки.

Старые чаты не имеют приоритета при противоречии с этими файлами.

Не придумывать механики, отсутствующие в `GAME_RULES.md`.

Новые игровые решения сначала фиксировать в `GAME_RULES.md`, архитектурные — в `AGENTS.md`.

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

Decision Provider может быть человеком, локальным AI, внешним API или другим источником.

Game Engine — единственный арбитр игры.

AI, контроллеры и клиентский JavaScript не изменяют GameState напрямую.

### Action

`GameEngine::Action` содержит:

- `player_id`;
- `type`;
- `payload`.

Action только описывает намерение и не изменяет state.

### Result

`GameEngine::Result` содержит:

- успех или ошибку;
- новый GameState;
- события.

Исходный state не мутируется. При ошибке новый state не возвращается.

### Engine

`GameEngine::Engine` маршрутизирует Action:

```ruby
ACTIONS = {
  "move" => Actions::Move,
  "attack" => Actions::Attack,
  "play_card" => Actions::PlayCard,
  "end_turn" => Actions::EndTurn
}.freeze
```

Engine централизованно:

- проверяет истечение времени текущего игрока;
- запрещает Actions после завершения игры.

При:

```ruby
state["status"] == "finished"
```

известные Actions отклоняются с:

```
Game is already finished
```

Механизм Draw не является Action. Он используется внутренними сервисами.

## 4. Game и GameState

`Game.state` — authoritative snapshot (основной снимок состояния) партии, хранится в PostgreSQL JSONB.

После успешного Action сохраняется новый state.

GameState не обращается к ActiveRecord.

### Основные поля

- `status`
- `turn_number`
- `current_player_id`
- `turn_started_at`
- `players`
- `field`
- `result`

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

Игровые операции создают новый state, обычно через `deep_dup`.

Исходный GameState не изменяется.

## 5. Скрытая информация

Игрок и AI получают только разрешённую правилами информацию.

Нельзя раскрывать:

- руку противника;
- содержимое и порядок колоды противника;
- скрытое кладбище противника;
- другие запрещённые данные.

Клиентский интерфейс не является механизмом защиты.

События также не должны раскрывать скрытое содержимое карт.

## 6. Игровое поле

Основное поле:

```
3 × 5
строки:    0..2
столбцы:   0..4
```

HQ:

```
Player 1 → [2][0]
Player 2 → [0][4]
```

На одной клетке находится один объект.

На основном поле находятся:

- HQ;
- Technique.

Platoon находится отдельно от основного поля.

За каждым HQ существует линия из 4 Platoon-слотов:

```ruby
[nil, nil, nil, nil]
```

После уничтожения слот становится `nil` и не уплотняется.

## 7. Runtime GameState

### HQ

HQ создаётся при StartGame из `GamePlayer.headquarters_card`.

Runtime HQ находится непосредственно в `field`:

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
  "has_attacked" => false,
  "has_counterattacked" => false,
  "abilities" => []
}
```

`hp`, `firepower`, `fuel` — текущие характеристики партии.

Отдельный `level` не используется: уровень HQ определяется `Card.weight`.

### Technique

Runtime Technique находится в `field`:

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

На поле не хранятся `price`, `weight`, `card_type` и вложенный объект `technique`.

`movement_count` — оставшиеся движения.

`movement_limit` — максимальное количество движений для восстановления в начале хода.

### Platoon

Runtime Platoon хранится только здесь:

```
state["players"][player_id]["platoons"]
```

Пример:

```ruby
[
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

Одновременно допускается до 4 активных Platoon.

Runtime Platoon может иметь `armor == 0`, `nil` или отсутствующий ключ. В боевой логике это означает `armor = 0`.

## 8. ActiveRecord-модели

Основные модели:

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

### Card

Допустимые типы:

```
headquarters
technique
order
platoon
```

Основные поля:

- `code`
- `name`
- `nation`
- `card_type`
- `weight`
- `price`

`code` — стабильный уникальный машинный идентификатор карты.

`name` — отображаемое название и может изменяться.

Seed ищет карты по `code`.

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

```
light_tank
medium_tank
heavy_tank
tank_destroyer
artillery
```

Типы движения:

```
orthogonal
diagonal
```

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

```
Game + Player + Nation + Deck
```

Уникальная пара:

```
game_id + player_id
```

Также хранит выбранную `headquarters_card`.

## 9. Ability

Используется единая система:

```
Card
 ↓
CardAbility
 ↓
Ability
```

`TechniqueAbility` не используется.

### Ability

Имеет:

- `code`
- `name`

`code` уникален.

### CardAbility

Имеет:

- `card_id`
- `ability_id`
- `parameters`

Пара `card_id + ability_id` уникальна.

В GameState способность сериализуется без `name`:

```ruby
{
  "code" => "damage_technique",
  "damage" => 3
}
```

### Executor

Реализован:

```
GameEngine::Abilities::Executor
```

Текущие способности:

```
damage_technique
draw_cards
```

Выбор обработчика выполняется по `Ability.code`.

Новая способность добавляется отдельным handler (обработчиком).

### draw_cards

Использует:

```
Abilities::DrawCards
        ↓
Cards::Draw
```

Обязательный Draw и Draw через Ability используют один механизм.

## 10. Колоды

`Deck` — постоянная колода игрока.

`DeckCard` хранит количество копий.

Ограничения:

- максимум 3 копии одной карты;
- уникальность `deck_id + card_id`;
- карта и колода принадлежат одной Nation.

Persistent Deck не изменяется во время партии.

### StartGame

При старте:

1. проверяются два GamePlayer;
2. берутся их Deck;
3. `GameState.cards_from_deck` создаёт полные карты;
4. колоды перемешиваются;
5. оба игрока получают по 6 карт;
6. выбирается первый игрок;
7. создаётся GameState;
8. создаются оба runtime HQ;
9. игра становится `started`;
10. для первого игрока рассчитывается стартовый Fuel.

Первый игрок не получает дополнительный Draw при StartGame.

Следующий обязательный Draw выполняется при начале следующего хода через PreparePlayer.

## 11. Draw / Hand / Graveyard

Stage 11 завершён.

### Draw

Реализован:

```
GameEngine::Cards::Draw
```

Он получает:

```
state
player_id
count
```

Каждая попытка обрабатывается отдельно:

```
Deck = [A]
Draw 2

A → Hand
пустая Deck → empty-deck damage
```

При успешном Draw создаётся:

```ruby
{
  type: "card_drawn",
  player_id: player_id
}
```

Содержимое карты в событии не раскрывается.

### Empty Deck

У игрока:

```ruby
"empty_deck_draw_attempts" => 0
```

Каждая попытка Draw из пустой колоды:

```
counter += 1
HQ HP -= counter
```

Например:

```
1-я → 1 урон
2-я → 2 урона
3-я → 3 урона
```

Событие:

```ruby
{
  type: "empty_deck_draw_attempt",
  player_id: player_id,
  damage: damage
}
```

Если HQ уничтожен, используется `GameEngine::FinishGame` с причиной:

```
empty_deck_damage
```

HP не уменьшается ниже 0.

### Graveyard

Каждый игрок имеет:

```ruby
"graveyard" => []
```

Туда попадают:

- разыгранные Order;
- уничтоженные Technique;
- уничтоженные Platoon;
- карты, сброшенные игровыми эффектами.

При обычном розыгрыше Technique или Platoon карта в graveyard не попадает.

Восстановление карт текущими правилами не предусмотрено.

## 12. Timer / Resources / Turns

### TurnTimer

Реализован:

```
GameEngine::TurnTimer
```

Начальное время каждого игрока:

```ruby
10.minutes.to_i
```

GameState содержит:

```
turn_started_at
remaining_time
```

Время списывается только у текущего игрока.

Перед Action Engine проверяет истечение времени.

При истечении:

```
FinishGame
reason = time_expired
```

Текущий игрок проигрывает.

### FuelCalculator

Реализован:

```
GameEngine::Resources::FuelCalculator
```

Fuel текущего игрока:

```
HQ
+
собственные Technique
+
собственные Platoon
```

`nil`-слоты Platoon игнорируются.

Неиспользованный Fuel автоматически не переносится.

### PreparePlayer

Реализован:

```
GameEngine::Turns::PreparePlayer
```

При начале хода:

```
PreparePlayer
├── восстановление movement_count
├── сброс attack flags Technique
├── сброс attack flags HQ
├── пересчёт Fuel
└── обязательный Draw 1
```

Изменяется только состояние нового текущего игрока.

EndTurn напрямую Draw не вызывает.

## 13. PlayCard

Stage 9 завершён.

Реализованы:

- `Card.price`;
- Technique;
- Platoon;
- Headquarters;
- Deck / DeckCard;
- Ability / CardAbility;
- `damage_technique`;
- `draw_cards`;
- Technique PlayCard;
- Order PlayCard;
- Platoon PlayCard;
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

- списывается price;
- удаляется одна копия карты;
- создаётся runtime Technique;
- `movement_limit` получает исходный `movement_count`;
- создаётся `technique_played`.

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

После полного успеха:

- списывается price;
- Order удаляется из hand;
- Order помещается в graveyard.

### Platoon

Platoon размещается в первый свободный слот линии из 4.

При заполненной линии розыгрыш отклоняется.

При успешном розыгрыше:

- списывается price;
- удаляется одна карта из hand;
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

Attack:

- проверяет текущий ход;
- проверяет координаты;
- проверяет атакующего и цель;
- проверяет принадлежность;
- проверяет дальность и специальные правила;
- создаёт новый state;
- после успешной атаки устанавливает `has_attacked = true`.

### Technique → Technique

Обычная атака:

- наносит урон;
- уничтоженная Technique удаляется из field;
- полный runtime-объект попадает в graveyard;
- выжившая соседняя Technique может контратаковать.

### PT-SAU

`tank_destroyer` стреляет первым.

Если атакующая Technique уничтожена первым выстрелом PT-SAU, её собственный выстрел не выполняется.

### SAU / Spotting

`artillery` может атаковать на дальней дистанции только при spotting.

Источником spotting может быть:

- союзная Technique;
- наш штаб / штаб атакующего игрока.

Для дальней атаки SAU по Technique требуется источник spotting рядом с целью.

SAU может атаковать HQ на расстоянии при соответствующем spotting.

Дальняя атака не вызывает counterattack.

Не создавать отдельную систему spotting для HQ.

### HQ

Поддерживаются:

```
Technique → HQ
SAU → HQ
HQ → HQ
HQ → Technique
```

HQ не контратакует HQ.

При дальней атаке HQ или SAU counterattack цели не выполняется.

### HQ firepower

При атаке HQ:

```
HQ firepower
+
firepower всех активных Platoon
```

После выстрела HQ каждый активный Platoon получает урон, равный собственному firepower.

Уничтоженный Platoon:

- получает HP 0;
- попадает в graveyard;
- его слот становится `nil`;
- остальные слоты не сдвигаются.

### Platoon Armor

Входящий урон по HQ сначала проходит через Platoon:

```
slot 0
 ↓
slot 1
 ↓
slot 2
 ↓
slot 3
 ↓
HQ
```

Для Platoon:

```ruby
armor = platoon["armor"].to_i
```

Поглощается:

```
min(remaining_damage, armor)
```

Если Platoon уничтожен, оставшийся урон идёт дальше.

Если Armor отсутствует, равен `nil` или 0, Platoon не поглощает урон.

### Победа через Combat

При HQ `hp <= 0`:

```
Attack
 ↓
FinishGame
```

Причина:

```
headquarters_destroyed
```

## 15. Victory / Defeat

Stage 13 завершён.

Единый сервис:

```
GameEngine::FinishGame
```

Принимает:

```
state
winner_id
loser_id
reason
```

Допустимые причины:

```
headquarters_destroyed
empty_deck_damage
time_expired
```

При успехе:

```ruby
new_state["status"] = "finished"

new_state["result"] = {
  "winner_id" => winner_id,
  "loser_id" => loser_id,
  "reason" => reason
}
```

Создаётся:

```ruby
{
  type: "game_finished",
  winner_id: winner_id,
  loser_id: loser_id,
  reason: reason
}
```

FinishGame проверяет:

- игра ещё не завершена;
- winner существует;
- loser существует;
- winner и loser различаются;
- reason допустим.

Повторное завершение запрещено.

Исходный state не изменяется.

Все способы окончания партии используют FinishGame:

```
HQ destroyed
empty deck damage
time expired
```

## 16. Seed / базовый игровой контент

Stage 14 завершён.

Цель seed — создать только базовый игровой контент и быть безопасным для повторного запуска.

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

`db/seeds.rb`:

```ruby
load Rails.root.join("db/seeds/nations.rb")
load Rails.root.join("db/seeds/abilities.rb")
load Rails.root.join("db/seeds/cards.rb")
load Rails.root.join("db/seeds/card_abilities.rb")
```

Seed работает с:

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

Не использовать:

- `destroy_all`
- `delete_all`

для удаления пользовательских данных.

### Идемпотентность

Для базовых записей используется принцип:

```ruby
find_or_initialize_by(stable_key)
assign_attributes(...)
save!
```

Повторный запуск seed не создаёт дубликаты.

### Nations

Созданы:

```
ussr    → СССР
germany → Германия
usa     → США
```

### Abilities

Созданы:

```
damage_technique
draw_cards
```

### Cards

Seed содержит:

```
3 HQ
18 Technique
6 Order
6 Platoon
----------------
33 cards
```

Существующие Nation:

```
СССР
Германия
США
```

`Card.code` является стабильным ключом seed.

### Card.code

Для Card добавлено поле:

```
code
```

и уникальный индекс.

Названия карт можно изменять без создания новой записи.

`code` не добавляется в runtime GameState, так как для runtime используется `card_id` и сериализованные характеристики карты.

### CardAbility

Seed создаёт 6 связей:

```
Germany:
Точный выстрел    → damage_technique
Радиоперехват      → draw_cards

USA:
Ленд-лиз          → draw_cards
Огневой налёт      → damage_technique

USSR:
Залп «Катюши»      → damage_technique
Пополнение         → draw_cards
```

### Runtime / Seed

После seed проверено:

```
Nations:       3
Abilities:     2
Cards:        33
Techniques:   18
Platoons:      6
Headquarters:  3
CardAbilities: 6
```

Пользовательские данные seed не создаёт и не удаляет.

## 17. AI

Планируется заменяемый Decision Provider.

Возможный локальный AI:

```
Ollama
Qwen3 1.7B
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

AI не должен:

- изменять GameState напрямую;
- видеть скрытую информацию;
- обходить проверки Engine;
- создавать зависимость Engine от Ollama.

## 18. Что не делать

Не переносить игровую логику в:

- Controllers;
- Stimulus;
- ActiveRecord models;
- UI;
- AI.

Не:

- изменять GameState напрямую;
- изменять persistent Deck во время партии;
- создавать отдельные AR-модели для runtime-объектов без необходимости;
- создавать отдельный Action для Draw без необходимости;
- дублировать механизм Draw;
- создавать TechniqueAbility;
- создавать отдельную HeadquartersAbility;
- создавать отдельный level для HQ;
- создавать отдельный nation_id в Headquarters;
- создавать отдельный runtime Platoon на основном field;
- уплотнять Platoon после уничтожения;
- создавать отдельную систему spotting для HQ;
- переносить победу/поражение обратно в Combat;
- создавать отдельную систему завершения игры внутри Actions;
- дублировать `status`, `result` и `game_finished` в разных местах;
- выдумывать игровые механики;
- использовать cookies как основное хранилище GameState;
- сохранять каждое промежуточное изменение GameState.

## 19. Порядок работы

Для каждого этапа:

1. Прочитать актуальные `AGENTS.md` и `GAME_RULES.md`.
2. Проверить существующую реализацию.
3. Обсудить значительные изменения до написания кода.
4. Внести только необходимые изменения.
5. Добавить/обновить тесты.
6. Выполнить:

```
bin/rails test
```

7. Проверить соответствие `GAME_RULES.md`.
8. Обновить `AGENTS.md`.
9. При необходимости обновить `GAME_RULES.md`.
10. После значимого этапа сделать отдельный Git commit.

**Без явной команды пользователя не изменять файлы проекта.**

## 20. Тесты и текущий статус

Stage 1–14 завершены.

Последний полный зелёный прогон после Stage 14:

```
272 tests
776 assertions
0 failures
0 errors
0 skips
```

Отдельные актуальные проверки Stage 14:

```
9 seed tests
25 assertions
0 failures
0 errors
0 skips
```

Seed проверен:

- на чистой test БД;
- повторным запуском;
- без изменения пользовательских данных.

Test БД:

```
clash_tanks_test
```

Production-like локальная проверка подключения не завершена из-за текущей конфигурации PostgreSQL-аутентификации production:

```
clash_tanks_production
user: clash_tanks
```

Локальный production runner получил:

```
PG::ConnectionBad
Peer authentication failed for user "clash_tanks"
```

Production-конфигурацию и PostgreSQL-роли ради Stage 14 не изменяли.

Seed считается готовым для production, но реальное production-подключение к БД должно быть настроено отдельно при deployment (развёртывании).

## 21. Контрольная точка

```
Stage 1–8   — завершены
Stage 9     — PlayCard — завершён
Stage 10    — Resources / Turns — завершён
Stage 11    — Draw / Hand / Graveyard — завершён
Stage 12    — Combat — завершён
Stage 13    — Victory / Defeat — завершён
Stage 14    — Seed / базовый игровой контент — завершён
Stage 15    — UI — следующий
Stage 16    — Human vs Human
Stage 17    — Decision Provider
Stage 18    — AI
Stage 19    — Ollama / Qwen3 1.7B
Stage 20    — AI testing
Stage 21    — Deck Weight
Stage 22    — дальнейшее развитие
```

Следующий рабочий этап:

**Stage 15 — UI.**

Основной принцип:

```
GAME_RULES.md = ЧТО
AGENTS.md     = КАК

Decision Provider → Action → GameEngine → GameState
```

Game Engine остаётся единственным арбитром игры.
