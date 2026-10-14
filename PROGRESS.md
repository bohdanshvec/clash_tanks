# PROGRESS.md

## Текущая контрольная точка

Завершены Stage 1–20: фундамент и Engine, UI, Players, Deck UI, Waiting / Started, Human vs Human и Decision Provider.

**Stage 21 — AI в игровом процессе — НЕ завершён.** Рабочая ветка `feature/ai`.

Основной AI-контур реализован; в текущей итерации завершена и проверена **пошаговая отправка Turbo-обновлений после каждого успешного действия AI**. Пользователь провёл полную браузерную партию с реальным Groq: AI разыгрывал карты, атаковал, завершал ходы; все действия отображались последовательно. Партия закончилась при обязательном взятии карты из пустой колоды: урон штабу вызвал поражение. Это подтверждает проверенный сценарий, но не все варианты `/play`, гостевого входа или сетевых сбоев.

Последние подтверждённые тесты:

```text
bin/rails test test/services/games/run_ai_turns_test.rb
11 runs, 61 assertions, 0 failures, 0 errors, 0 skips

bin/rails test test/controllers/games_controller_ai_test.rb
3 runs, 58 assertions, 0 failures, 0 errors, 0 skips

bin/rails test test/controllers/games_controller_test.rb
35 runs, 361 assertions, 0 failures, 0 errors, 0 skips

bin/rails test
529 runs, 2008 assertions, 0 failures, 0 errors, 0 skips
```

Целевой `GroqAdapterTest` ранее проходил: 20 runs, 49 assertions, 0 failures; в данной итерации адаптер не изменялся. Результаты не подтверждают будущие изменения кода. Не дублировать уже покрытые тесты.

## Завершённые этапы

### Stage 16 — Players

Player одновременно account и игровая сущность. Регистрация, вход/выход, `has_secure_password`, `current_player`, session identity, header, публичные страницы, `/statistics` для зарегистрированных, `bin/rails dev:create_game`. Отдельные User/Devise не используются.

### Stage 17 — Deck UI

`Deck`, `DeckCard`, Deck Weight, Headquarters, `StarterDecks::Create`, стартовые колоды, каталог Cards, `/decks`, preview/editor, quantity, валидации, CRUD и браузерный UI. Гость просматривает starter Deck, но не управляет Deck.

### Stage 18 — Waiting / Started

`/play`, выбор полной Deck, PvP UI, waiting Game и первый GamePlayer, `Matchmaking::FindOpponent`, безопасный Join, StartGame, cancel waiting, heartbeat, stale cleanup, guest lifecycle, VisibleState boundary и Turbo refresh. Проверен Player/Guest → `/play` → waiting → Join → StartGame → started → first Action.

### Stage 19 — Human vs Human

Полный PvP lifecycle проверен в двух браузерах. Move, Attack, PlayCard, EndTurn, Surrender проходят Controller/Engine. `GameActionRunner` сохраняет только успешное. Turbo каждому игроку отправляет свой VisibleState. Проверены завершение, пустые AvailableActions после окончания и защита скрытых данных.

### Stage 20 — Decision Provider

`DecisionProviders::Base`, Context, Human, AI, `GameEngine::Action`, `GameActionRunner`, VisibleState, Groq/OpenAI adapters. Проверка формата AI-ответа, нормализация JSON payload, ограниченные попытки. Автотесты не вызывают реальные API. `AI_PROVIDER` по умолчанию groq, модель `openai/gpt-oss-20b`; OpenAI adapter — альтернатива. Ключи — в окружении, не в Git.

## Stage 21 — AI в игровом процессе (НЕ завершён)

### 1. База, модели и постоянный AI-игрок

- Режимы `Game`: `pvp`, `ai`; `Player#ai?`; частичный уникальный индекс для одного постоянного AI-игрока.
- `AiPlayers::Setup` идемпотентно находит/создаёт `ai@clash-tanks.local`.
- `AiPlayers::DecksSetup` идемпотентно создаёт три полные колоды по 10 карт с допустимыми копиями:

| Колода | Нация | Вес |
|---|---|---:|
| ИИ — США: лёгкая техника | США | 13 |
| ИИ — СССР: средняя техника | СССР | 22 |
| ИИ — Германия: тяжёлая техника | Германия | 28 |

Игрок и колоды повторно используются между партиями; постоянные Deck не изменяются в процессе игры.

### 2. Подбор совместимой колоды

`Matchmaking::AiDeckSelector` ищет полную AI-колоду в диапазоне ±10% веса, при нескольких совпадениях выбирает ближайшую. Целочисленные диапазоны человеческого веса: 12–14 (AI 13), 20–24 (AI 22), 26–30 (AI 28).

### 3. AI-решение и безопасное выполнение Action

- `DecisionProviders::AI` получает разрешённый Context, проверяет ответ, нормализует ключи payload, допускает максимум три попытки некорректного решения.
- Источник решений подменяется в тестах; реальный API из тестов не вызывается.
- `GameActionRunner` под блокировкой сверяет `expected_state_digest`, вызывает Engine и сохраняет только успешный state. Устаревший/отклонённый Action не изменяет игру.
- Тесты покрывают успешное сохранение, отказ Engine, waiting, stale digest и актуальный digest.

### 4. Автоматический AI-цикл

`Games::RunAiTurns` (`app/services/games/run_ai_turns.rb`):

- максимум 20 AI-действий за запуск;
- PostgreSQL advisory lock предотвращает параллельные циклы одной игры, независимые игры не блокируются;
- максимум три stale-state retry;
- перед решением перечитывает игру и проверяет статус, активного игрока и лимит;
- прекращает цикл при смене хода, завершении игры, ошибке или лимите;
- сохраняет уже выполненные действия при последующей ошибке и возвращает результат/события/число действий;
- **новое:** принимает необязательный `on_action` и вызывает его с событиями каждого успешного действия после сохранения state.

Тесты покрывают lock, конкурентные/независимые игры, исключение provider, невалидное действие, частичный результат, лимит, stale retry, завершение/смену хода. Обновлённый тест проверяет, что `on_action` получает отдельные события и видит уже сохранённое состояние.

### 5. GamesController и пошаговый Turbo — завершено и проверено

**До изменения:** контроллер накапливал события AI и отправлял итоговое обновление после завершения всего цикла.

**После изменения:**

1. `GamesController#process_game_action` применяет человеческий Action, перечитывает игру и немедленно отправляет `broadcast_game_update(human_events)`.
2. Затем вызывает `run_ai_turns_if_needed(broadcast_each_action: true)`.
3. `Games::RunAiTurns` после каждого успешного AI Action вызывает `on_action(action_events)`.
4. Callback контроллера делает `@game.reload` и `broadcast_game_update(action_events)`.
5. Каждый broadcast формирует собственный `VisibleState` для каждого участника; скрытая рука противника не раскрывается.
6. `GamesController#show` запускает AI с таким же пошаговым broadcast, когда страницу открывают во время хода AI.
7. Ошибка provider не отменяет сохранённое человеческое действие или уже выполненные AI-действия. Повторный заход может повторно запустить оставшийся ход AI.

Обновлены тесты `run_ai_turns_test.rb`, `games_controller_ai_test.rb` и код `games_controller.rb`, `run_ai_turns.rb`. Контроллерный тест проверяет **4 broadcasts для 2 AI-действий × 2 игроков**, разные события/состояния `attack` и `end_turn`, скрытую информацию. Исправлена устаревшая ссылка на `ai_result` в `show`.

**Браузер:** пользователь подтвердил последовательное отображение действий реального AI в полноценной партии. Победа/поражение от урона пустой колоды также проверена вручную. Это не подтверждает отдельные сценарии гостя, первого хода AI или обработки сетевых сбоев.

### 6. Актуальный GroqAdapter

Основной адаптер — Groq, модель `openai/gpt-oss-20b`. Модель выбирает `action_index` из индексируемых `legal_actions`; адаптер проверяет индекс и возвращает исходное действие. `available_actions` не дублируется в `game_state`.

Текущая конфигурация после выполненной ранее работы:

- Structured Outputs со строгой JSON-схемой `action_index` вместо прежнего свободного JSON-режима;
- `reasoning_effort=low`;
- `max_completion_tokens=512`;
- логи prompt/completion/reasoning/total tokens, `finish_reason`, HTTP-ошибок и rate-limit headers;
- ограниченные повторы HTTP 429 при распознаваемой положительной задержке;
- подменяемый HTTP transport для тестов.

**Исторические проблемы:** HTTP 429 из-за TPM, HTTP 400 `json_validate_failed` при прежнем JSON-режиме, высокий расход completion tokens. В ранней диагностической выборке из восьми успешных запросов: 10 627 prompt, 4 289 completion, 14 916 total tokens; это не расход за минуту и не показатели текущей конфигурации.

В последней реальной партии показанные успешные ответы имели `finish_reason="stop"`; отдельные запросы использовали примерно 1200–2000 total tokens. Это подтверждает работоспособность в проверенной партии, но не гарантирует отсутствие будущих HTTP 429/timeout или успешное восстановление при недоступности API.

Устаревшие утверждения «нет max_completion_tokens» и «всё ещё используется прежний JSON-режим» больше не актуальны. Причину прежнего HTTP 400 не следует объявлять окончательно установленной без отдельного подтверждения.

### 7. Что осталось сделать

1. **Следующий приоритет — надёжность Groq:** проверить текущую обработку HTTP 429, timeout, недоступности API, исчерпания повторов и восстановление партии без потери сохранённых действий. Не добавлять дублирующие тесты, сначала прочитать актуальный адаптер и тесты.
2. `/play`: проверить `PagesController#play`, `play.html.erb`, `pages_controller_test.rb`. AI-кнопка только для совместимой полной колоды; сообщение при отсутствии совместимости; PvP всегда доступен.
3. Гость/starter Deck: `ensure_guest_player!`, параметры формы, соответствие выбранного идентификатора `@ai_decks_by_deck_id`; не предполагать, что starter deck всегда объект Deck с `id`.
4. Серверный AI create path: режим, identity, принадлежность и полнота Deck, совместимость, GamePlayer/Nation/Deck, StartGame, отсутствие побочных эффектов при отказе.
5. Оставшиеся браузерные сценарии: зарегистрированный и гость через `/play`, первый ход AI, несовместимые колоды, PvP-регрессии и скрытые данные. Полная партия с пошаговым AI и окончанием от пустой колоды **уже проверена**.
6. После изменений выполнить целевые и полный набор тестов, обновить документацию. Не закрывать Stage 21 до проверки всех обязательных сценариев.

## Архитектурные границы

```text
Decision Provider → Action → GameActionRunner → GameEngine → GameState
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

GameEngine — единственный арбитр правил; Controller организует процесс и Turbo; AI выбирает Action; GameActionRunner безопасно применяет; VisibleState ограничивает данные. AI не мутирует state и не получает скрытые данные противника.
