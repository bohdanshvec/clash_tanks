# PROGRESS.md

## Текущая контрольная точка

**Stage 1–21 завершены.** Рабочая ветка: `feature/ai`.

Stage 21 — AI в игровом процессе — принят как завершённый по решению пользователя. Основной AI-контур реализован, автоматические тесты проходят, пошаговый Turbo broadcast проверен, полноценная браузерная партия с реальным Groq сыграна. Возможные будущие доработки не являются незакрытыми блокерами этапа.

В проверенной браузерной партии AI разыгрывал карты, атаковал и завершал ходы; действия отображались последовательно. Партия закончилась поражением от урона штабу при обязательном взятии карты из пустой колоды. Это подтверждает данный сценарий, но не гарантирует отсутствие любых сетевых ошибок или проблем при всех возможных условиях.

Последние подтверждённые тесты:

```text
bin/rails test test/services/decision_providers/groq_adapter_test.rb
23 runs, 62 assertions, 0 failures, 0 errors, 0 skips

bin/rails test
534 runs, 2029 assertions, 0 failures, 0 errors, 0 skips
```

## Завершённые этапы

### Stage 16 — Players

Player одновременно account и игровая сущность. Регистрация, вход/выход, `has_secure_password`, `current_player`, session identity, header, публичные страницы, `/statistics` для зарегистрированных, `bin/rails dev:create_game`. Отдельные User/Devise не используются.

### Stage 17 — Deck UI

Deck, DeckCard, Deck Weight, Headquarters, StarterDecks::Create, стартовые колоды, каталог Cards, `/decks`, preview/editor, quantity, валидации, CRUD и браузерный UI. Гость просматривает starter Deck, но не управляет Deck.

### Stage 18 — Waiting / Started

`/play`, выбор полной Deck, PvP UI, waiting Game и первый GamePlayer, Matchmaking::FindOpponent, безопасный Join, StartGame, cancel waiting, heartbeat, stale cleanup, guest lifecycle, VisibleState boundary и Turbo refresh. Проверен Player/Guest → `/play` → waiting → Join → StartGame → started → first Action.

### Stage 19 — Human vs Human

Полный PvP lifecycle проверен в двух браузерах. Move, Attack, PlayCard, EndTurn, Surrender проходят Controller/Engine. GameActionRunner сохраняет только успешное. Turbo каждому игроку отправляет свой VisibleState. Проверены завершение, пустые AvailableActions после окончания и защита скрытых данных.

### Stage 20 — Decision Provider

DecisionProviders::Base, Context, Human, AI, GameEngine::Action, GameActionRunner, VisibleState, Groq/OpenAI adapters. Проверка формата AI-ответа, нормализация JSON payload, ограниченные попытки. Автотесты не вызывают реальные API. AI_PROVIDER по умолчанию groq, модель `openai/gpt-oss-20b`; OpenAI adapter — альтернатива. Ключи — в окружении, не в Git.

## Stage 21 — AI в игровом процессе (ЗАВЕРШЁН)

### 1. База, модели и постоянный AI-игрок

- Режимы Game: `pvp`, `ai`; `Player#ai?`; частичный уникальный индекс для одного постоянного AI-игрока.
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
- GameActionRunner под блокировкой сверяет `expected_state_digest`, вызывает Engine и сохраняет только успешный state. Устаревший/отклонённый Action не изменяет игру.
- Проверки покрывают успешное сохранение, отказ Engine, waiting, stale digest и актуальный digest.

### 4. Автоматический AI-цикл

`Games::RunAiTurns` (`app/services/games/run_ai_turns.rb`):

- максимум 20 AI-действий за запуск;
- PostgreSQL advisory lock предотвращает параллельные циклы одной игры, независимые игры не блокируются;
- максимум три stale-state retry;
- перед решением перечитывает игру и проверяет статус, активного игрока и лимит;
- прекращает цикл при смене хода, завершении игры, ошибке или лимите;
- сохраняет уже выполненные действия при последующей ошибке и возвращает результат/события/число действий;
- принимает необязательный `on_action` и вызывает его с событиями каждого успешного действия после сохранения state.

Тесты покрывают lock, конкурентные/независимые игры, исключение provider, невалидное действие, частичный результат, лимит, stale retry, завершение/смену хода. Тест callback проверяет отдельные события и то, что состояние уже сохранено к моменту вызова.

### 5. GamesController и пошаговый Turbo — завершено и проверено

1. `GamesController#process_game_action` применяет человеческий Action, перечитывает игру и немедленно отправляет `broadcast_game_update(human_events)`.
2. Затем вызывает `run_ai_turns_if_needed(broadcast_each_action: true)`.
3. `Games::RunAiTurns` после каждого успешного AI Action вызывает `on_action(action_events)`.
4. Callback контроллера делает `@game.reload` и `broadcast_game_update(action_events)`.
5. Каждый broadcast формирует собственный VisibleState для каждого участника; скрытая рука противника не раскрывается.
6. `GamesController#show` запускает AI с таким же пошаговым broadcast, когда страницу открывают во время хода AI.
7. Ошибка provider не отменяет сохранённое человеческое действие или уже выполненные AI-действия. Повторный заход может повторно запустить оставшийся ход AI.

Контроллерный тест проверяет **4 broadcasts для 2 AI-действий × 2 игроков**, разные события/состояния attack и end_turn, скрытую информацию. Исправлена устаревшая ссылка на ai_result в show.

**Браузер:** пользователь подтвердил последовательное отображение действий реального AI в полноценной партии. Партия закончилась от урона штабу при обязательном взятии карты из пустой колоды.

### 6. Актуальный GroqAdapter

Основной адаптер — Groq, модель `openai/gpt-oss-20b`. Модель выбирает `action_index` из индексируемых `legal_actions`; адаптер проверяет индекс и возвращает исходное действие. `available_actions` не дублируется в `game_state`.

Текущая конфигурация:

- Structured Outputs со строгой JSON-схемой `action_index`;
- `reasoning_effort=low`;
- `max_completion_tokens=512`;
- логи prompt/completion/reasoning/total tokens, `finish_reason`, HTTP-ошибок и rate-limit headers;
- ограниченные повторы HTTP 429 при распознаваемой положительной задержке;
- ограниченная обработка временных сетевых ошибок;
- подменяемый HTTP transport для тестов;
- при единственном `legal_action` API-вызов пропускается, действие возвращается напрямую.

Системная инструкция `INSTRUCTIONS` **оставлена без сокращения** по решению пользователя.

Исторически наблюдались HTTP 429 из-за TPM, HTTP 400 `json_validate_failed` в прежнем JSON-режиме и высокий расход completion tokens. В проверенной браузерной партии успешные ответы имели `finish_reason="stop"`; отдельные запросы в показанных логах использовали примерно 1200–2000 total tokens. Это не гарантирует отсутствия будущих HTTP 429 или timeout.

Временное development-логирование полного `REQUEST PAYLOAD` следует удалить, если оно всё ещё присутствует: оно печатает полное состояние запроса, включая руку AI и legal actions. Для диагностики достаточно usage-метрик и HTTP/rate-limit сведений.

### 7. Контрольные тесты при закрытии этапа

```text
GroqAdapterTest: 23 runs, 62 assertions, 0 failures, 0 errors, 0 skips
Full suite:      534 runs, 2029 assertions, 0 failures, 0 errors, 0 skips
```

Эти результаты отражают последнюю предоставленную пользователем проверку. Не приписывать им проверку изменений, которые будут внесены позднее.

## Архитектурные границы

```text
Decision Provider → Action → GameActionRunner → GameEngine → GameState
browser session → current_player → GamePlayer → Action.player_id → GameEngine
```

GameEngine — единственный арбитр правил; Controller организует процесс и Turbo; AI выбирает Action; GameActionRunner безопасно применяет; VisibleState ограничивает данные. AI не мутирует state и не получает скрытые данные противника.

## Дальнейшая работа

Stage 21 закрыт. При необходимости к вопросам устойчивости Groq, расхода токенов, качества стратегии или дополнительных браузерных сценариев можно вернуться отдельно. Следующие этапы и их содержание определяются `ROADMAP.md`.
