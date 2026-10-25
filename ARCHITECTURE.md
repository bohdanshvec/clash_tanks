# ARCHITECTURE.md

## Основной поток

```text
Decision Provider → Action → GameActionRunner → GameEngine → GameState

Browser → Controller → Decision Provider → Action → GameActionRunner → GameEngine → GameState
                                                                         ↓
Browser ← Stimulus ← Turbo ← VisibleState ← сохранённый GameState
```

GameEngine — единственный арбитр игровых правил.

`GameEngine::Action` содержит:

- `player_id`;
- `type`;
- `payload`.

`GameEngine::Result` содержит результат выполнения, новое состояние и events.

Engine работает с копией GameState.

При ошибке новое состояние не сохраняется.

Человек использует `DecisionProviders::Human`.

AI использует `DecisionProviders::AI`.

Любое действие проходит через GameActionRunner и GameEngine.

---

## Язык пользовательского интерфейса

Основной язык UI — украинский.

Украинскими должны быть:

- заголовки;
- кнопки;
- подписи;
- сообщения об ошибках;
- инструкции;
- другой текст для игрока.

Техническая документация может оставаться на русском.

---

## Game и GameState

`Game.state` — authoritative JSONB snapshot.

Основные поля:

- `status`;
- `turn_number`;
- `current_player_id`;
- `turn_started_at`;
- `players`;
- `field`;
- `result`.

Состояние игрока:

- `nation_id`;
- `hand`;
- `deck`;
- `graveyard`;
- `platoons`;
- `resources`;
- `remaining_time`;
- `empty_deck_draw_attempts`.

GameState не обращается к ActiveRecord.

Постоянная Deck не меняется во время партии.

Для waiting:

`Game.state == nil`

AI-игра создаётся сразу в started.

### Игровое поле

`field` содержит HQ и Technique.

Platoon хранится в:

`state["players"][player_id]["platoons"]`

Четыре слота сохраняют пустые позиции после уничтожения.

Логические координаты не зависят от визуальной перспективы.

DOM использует:

`data-position="row,column"`

### Runtime Technique

Содержит:

- тип;
- идентификаторы;
- имя;
- характеристики;
- флаги атаки;
- счётчики движения.

Не содержит `price`, `weight`, `card_type` или вложенный `technique`.

У Technique нет Armor.

### Runtime Platoon

Содержит:

- `firepower`;
- `hp`;
- `armor`;
- `fuel`.

Правила определяются `GAME_RULES.md`.

---

## Decision Provider

Provider выбирает намерение, но не применяет игровые правила.

### Base и Context

`DecisionProviders::Base` задаёт интерфейс `call`.

`DecisionProviders::Context` формирует:

- `player_id`;
- `visible_state`;
- available actions.

Контекст рекурсивно заморожен.

Provider не получает полный скрытый state.

### Human

`DecisionProviders::Human` преобразует:

- `move`;
- `attack`;
- `play_card`;
- `end_turn`;
- `surrender`.

Результат — `GameEngine::Action`.

Controller передаёт действие в GameActionRunner.

### AI

`DecisionProviders::AI` проверяет ответ, нормализует ключи JSON и создаёт Action.

При некорректном формате допускается до трёх попыток.

Формат не заменяет проверку Engine.

### Groq и OpenAI

`DecisionProviders::GroqAdapter` использует Groq Chat Completions API.

Модель по умолчанию:

`openai/gpt-oss-20b`

Модели передаются:

- разрешённое состояние;
- серверные `legal_actions`.

Модель возвращает:

`action_index`

Адаптер проверяет индекс и выбирает исходное разрешённое действие.

Требования:

- Structured Outputs;
- строгая JSON-схема;
- `reasoning_effort=low`;
- подменяемый HTTP transport;
- token usage и диагностические метрики;
- ограниченные повторы HTTP 429;
- обработка временных сетевых ошибок;
- пропуск API при одном допустимом действии.

Не логировать полные request payload и скрытые данные.

`DecisionProviders::OpenAiAdapter` — альтернативный адаптер.

`AI_PROVIDER` выбирает провайдера.

По умолчанию используется Groq.

Автотесты не вызывают реальные API.

---

## Action и GameActionRunner

`GameEngine::Action` содержит:

- `player_id`;
- `type`;
- `payload`.

Вложенные Hash/Array копируются и замораживаются.

GameActionRunner:

1. Блокирует игру.
2. Проверяет digest.
3. Вызывает Engine.
4. Сохраняет только успешный результат.

Отказанный или устаревший Action не должен менять state.

AI не может изменять GameState напрямую.

---

## VisibleState и AvailableActions

`GameEngine::VisibleState` — разрешённая граница данных UI/AI.

Игрок видит свою руку.

Противник видит только разрешённую публичную информацию и количества карт.

Содержимое чужих hand/deck/graveyard скрыто.

`GameEngine::AvailableActions` формирует серверные подсказки для:

- перемещений;
- атак;
- размещения техники;
- размещения взводов;
- приказов.

Эти подсказки не заменяют проверку Engine.

---

## Attack и контратака

Боевая механика разделена между Action, Rules и Attacks.

### GameEngine::Actions::Attack

Файл:

`app/services/game_engine/actions/attack.rb`

Отвечает за:

- проверку действия;
- выбор сценария;
- запуск исполнения;
- события;
- завершение партии.

### GameEngine::Rules::CombatType

Файл:

`app/services/game_engine/rules/combat_type.rb`

Сценарии:

- `:ranged`;
- `:normal`;
- `:ptsau_first`.

Определяет сценарий, но не исполняет выстрелы.

### GameEngine::Rules::Counterattack

Файл:

`app/services/game_engine/rules/counterattack.rb`

Проверяет допустимость контратаки.

Не наносит урон и не изменяет GameState.

### GameEngine::Attacks::CombatExecutor

Файл:

`app/services/game_engine/attacks/combat_executor.rb`

Исполняет:

- дальний бой;
- обычный бой;
- специальный сценарий ПТ-САУ;
- выстрелы;
- разрешённые контратаки.

### GameEngine::Attacks::HeadquartersCombat

Файл:

`app/services/game_engine/attacks/headquarters_combat.rb`

Отвечает за:

- огневую мощь штаба;
- повреждения взводов;
- поглощение урона бронёй;
- уничтожение взводов;
- graveyard;
- сохранение пустых слотов;
- урон штабу.

### Правила, которые необходимо сохранять

- Дальний бой не вызывает контратаку.
- В обычном бою атакующий стреляет первым.
- Выживший защитник может ответить при соблюдении условий.
- В специальном сценарии ПТ-САУ стреляет первой.
- Уничтоженный атакующий не выполняет ответный выстрел.
- Контратака штаба против штаба не выполняется.
- Повторная контратака ограничена правилами.
- Флаг контратаки устанавливается только при выполненном выстреле.
- Уничтоженный объект не стреляет.
- Огневая мощь штаба учитывает взводы.
- Взводы получают повреждения после выстрела штаба.
- Броня взводов поглощает входящий урон.
- Уничтоженные взводы отправляются в graveyard.
- Пустые слоты не уплотняются.
- Уничтожение штаба завершает партию через `GameEngine::FinishGame`.

### Границы ответственности

```text
Actions::Attack
    ├── Rules::CombatType
    ├── Attacks::CombatExecutor
    │       ├── Rules::Counterattack
    │       └── Attacks::HeadquartersCombat
    └── GameEngine::FinishGame
```

Не менять механику без согласования.

---

## Модели, Deck и Ability

Модели:

- Game;
- Player;
- GamePlayer;
- Nation;
- Card;
- Headquarters;
- Technique;
- Platoon;
- Ability;
- CardAbility;
- Deck;
- DeckCard.

Player использует `has_secure_password`.

Отдельные User/Devise отсутствуют.

Game поддерживает:

- waiting;
- started;
- finished.

Режимы:

- pvp;
- ai.

GamePlayer связывает игру, игрока, нацию, колоду и штаб.

DeckCard хранит quantity.

Вес Deck вычисляется по весам карт.

Способности:

```text
Card → CardAbility → Ability → GameEngine::Abilities::Executor
```

Не создавать TechniqueAbility или HeadquartersAbility.

---

## Карты, штаб и колоды

Каталог определяется seed-файлами.

Характеристики документируются в `CARDS.md`.

Сиды обновляют существующие карты по стабильному `code`.

Каждый штаб имеет уникальный код.

Коды синхронизируются с:

- `StarterDecks::Create`;
- `AiPlayers::DecksSetup`.

`Deck::DECK_SIZE` определяет размер колоды.

Вес вычисляется из веса карт и количества копий.

Штаб не входит в обычную сумму веса колоды.

---

## Постоянный AI-игрок и колоды

`AiPlayers::Setup` создаёт или находит единственного AI-игрока.

Email:

`ai@clash-tanks.local`

Частичный уникальный индекс не допускает второго AI-игрока.

`AiPlayers::DecksSetup` создаёт постоянные колоды.

Колоды используются повторно.

При изменении состава существующих AI-колод учитывать, что сервис не обязательно пересоздаёт сохранённый состав.

`Matchmaking::AiDeckSelector` выбирает совместимую колоду в пределах ±10% веса.

---

## Engine, events и timers

Основные сервисы:

- StartGame;
- Draw;
- Turns::PreparePlayer;
- Resources::FuelCalculator;
- Move;
- Attack;
- PlayCard;
- EndTurn;
- Surrender;
- FinishGame.

События сохраняются в `Result.events`.

TurnTimer и TurnTimerForTurn отвечают за время.

Сервер проверяет timeout.

Клиентский `game_timer_controller.js` отображает время.

---

## Games::RunAiTurns

Файл:

`app/services/games/run_ai_turns.rb`

Ограничения:

- максимум 20 действий;
- PostgreSQL advisory lock;
- до трёх stale-state retry;
- перечитывание Game;
- остановка при смене хода;
- остановка при завершении;
- сохранение частичных результатов.

`on_action` вызывается после сохранения успешного действия.

Callback не изменяет state.

---

## UI, Turbo и перспектива

Каждый игрок подписан на:

`[game, current_player_id]`

`GamesController#broadcast_game_update(events)` формирует отдельный VisibleState.

Скрытый полный state не передаётся браузеру.

Пошаговый AI broadcast:

```text
Human Action
  → GameActionRunner
  → save
  → broadcast human events
  → RunAiTurns
      → AI Action
      → GameActionRunner
      → save
      → broadcast AI events
      → next AI Action
```

Не возвращаться к накоплению всех AI-событий в один broadcast.

Controller организует рассылку.

Engine отвечает за правила.

---

## Графическое отображение игровых объектов — Stage 24

### Общий принцип

Игровые объекты отображаются многослойными HTML/CSS-компонентами.

Статические графические ресурсы отделены от динамических характеристик.

Источник характеристик — `GameEngine::VisibleState`.

UI не изменяет GameState.

### Штабы

Реализован общий компонент `headquarters-field` для:

- USA;
- СССР;
- Германии.

Структура:

```text
headquarters-field
├── headquarters-field__illustration
│   └── изображение штаба
├── headquarters-field__frame
│   └── прозрачная национальная рамка
└── headquarters-field__stats
    ├── headquarters-field__stat--firepower
    ├── headquarters-field__stat--hp
    └── headquarters-field__stat--fuel
```

Иллюстрация располагается под рамкой.

CSS обрезает изображение по форме рамки.

Характеристики находятся поверх рамки.

### Графические ресурсы штабов

Каталог:

`app/assets/images/headquarters/`

Шаблоны имён:

```text
{nation}_field_picture_headquarters.png
{nation}_field_border_headquarters.png
```

Поддерживаемые значения:

- `usa`;
- `ussr`;
- `germany`.

Размер:

1024 × 1024 px.

Для всех трёх наций используется единый ERB-шаблон.

Числовые характеристики не встраиваются в изображения.

### Динамические характеристики

На нижней панели:

- `firepower`;
- `hp`;
- `fuel`.

Значения поступают из текущего `VisibleState`.

Обновление выполняется существующим механизмом Turbo.

### Цветовая индикация огневой мощи

Во время хода владельца:

```ruby
firepower_available = !cell["has_attacked"]
```

Во время хода противника:

```ruby
firepower_available = !cell["has_counterattacked"]
```

Если `firepower_available == true`, значение красное.

Если `false`, используется стандартный цвет.

CSS-класс:

`headquarters-field__stat--ready`

Индикация не гарантирует допустимость атаки.

GameEngine остаётся единственным арбитром правил.

### Игровое поле и DOM-якоря

Видимые координаты клеток удалены.

Надписи `Empty` внутри пустых клеток удалены.

Сохраняется:

```html
data-position="row,column"
```

Логические координаты не изменены.

DOM-якоря используются для:

- выбора объектов;
- перемещения;
- атак;
- размещения карт;
- будущих анимаций.

Слоты взводов остаются отдельными элементами.

Номера и обозначения пустых слотов сохранены.

### Планируемое отображение техники

Для техники предусматривается многослойный компонент.

Целевая структура:

```text
technique-field
├── illustration
├── frame
├── technique-type-symbol
├── movement-indicators
├── stats
│   ├── firepower
│   ├── hp
│   └── fuel
└── effects
```

Это план, а не описание реализованного компонента.

Национальная рамка и иллюстрация остаются отдельными ресурсами.

Обозначение типа техники размещается в верхнем правом углу.

Планируется использовать масштабируемые SVG-символы.

### Индикаторы движения

Количество индикаторов определяется:

`movement_limit`

Использованные перемещения определяются:

`movement_count`

Во время хода владельца красным цветом показываются неиспользованные перемещения.

Для одного перемещения:

```text
movement_count = 0 → 1 красный индикатор
movement_count = 1 → 0 красных индикаторов
```

Для двух перемещений:

```text
movement_count = 0 → 2 красных индикатора
movement_count = 1 → 1 красный индикатор
movement_count = 2 → 0 красных индикаторов
```

Во время хода противника все индикаторы стандартного цвета.

Красный индикатор не гарантирует наличие допустимого маршрута.

### Индикация атаки техники

Используется тот же принцип, что и для штабов:

- `has_attacked` в ход владельца;
- `has_counterattacked` в ход противника.

Цветовая индикация не заменяет `AvailableActions`.

### Будущие игровые эффекты

Предусматривается отдельный слой.

Источник событий:

`GameEngine::Result.events`

Планируемые реакции:

- выстрел;
- контратака;
- попадание;
- повреждение техники;
- повреждение штаба;
- повреждение взвода;
- уничтожение техники;
- уничтожение взвода;
- урон от приказа;
- урон при пустой колоде.

Эффекты не должны изменять характеристики или повторно применять урон.

### Архитектурные ограничения

1. GameEngine остаётся единственным арбитром правил.
2. VisibleState является границей данных UI.
3. ERB формирует отображение.
4. CSS отвечает за внешний вид.
5. Stimulus обрабатывает взаимодействия и эффекты.
6. Turbo обновляет интерфейс.
7. Изображения не содержат динамических характеристик.
8. DOM-якоря сохраняются.
9. Графика не изменяет игровую механику.

---

## Редактор колод

Редактор использует ERB и Stimulus.

Текущие решения:

- создание рядом с заголовком;
- сохранение и отмена в верхней области;
- сортировка по типу, весу и названию;
- перенос карточек по строкам;
- украинские надписи.

Изменения оформления не меняют правила Deck.

---

## Authentication и matchmaking

```text
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

Гость создаётся при `/play`.

Получает три starter Deck.

Переиспользуется в сессии.

PvP matchmaking использует совместимость веса ±15%.

`Matchmaking::Join` применяет блокировку.

`CleanupStaleWaitingGames` очищает устаревшие waiting games.

---

## Статус Stage 21 и Stage 22

Stage 21 завершён.

Пошаговый Turbo broadcast и полноценная партия с Groq проверены.

Stage 22 завершён.

Исторический результат:

```text
534 runs, 2031 assertions, 0 failures, 0 errors, 0 skips
```

---

## Статус Stage 23

Stage 23 завершён.

Обновлены:

- каталог карт;
- характеристики;
- стартовые колоды;
- постоянные колоды AI;
- редактор колод.

Подробности должны соответствовать `CARDS.md` и актуальному коду.

---

## Статус Stage 24

Stage 24 находится в работе.

Выполнено:

- подготовка боевых событий;
- тематическое разделение CSS;
- общая визуальная тема;
- статичный фон;
- оформление основных страниц;
- модальный просмотр колод;
- графическое отображение штабов трёх наций;
- динамическая индикация огневой мощи штабов;
- очистка игрового поля от видимых координат и надписей пустых клеток.

Следующая основная задача:

**Графическое оформление техники, обозначения типов, индикаторы движения и огневой мощи.**

После этого — игровые эффекты.

---

## Тестирование AI

Использовать fake/mock источники решений и HTTP transport.

Проверять:

- скрытые данные;
- правильный `player_id`;
- отсутствие прямой мутации state;
- отказ Engine;
- stale state;
- ошибки provider;
- сохранение частичных результатов;
- остановку цикла;
- advisory lock;
- отдельный broadcast после каждого действия.

Реальный API — только при отдельной ручной проверке.