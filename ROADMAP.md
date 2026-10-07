# ROADMAP.md

## Текущий этап: Stage 18 — Waiting / Started

Stage 18 **не завершён**. Matchmaking уже работает, но завершением считается только проверенный целостный lifecycle, а не наличие UI или количество тестов.

### Обязательные проверки lifecycle

1. Добавить полный integration/controller сценарий: Player A создаёт waiting через `/play`, Player B находит его, Join запускает StartGame, игра становится started и открывается через `GET /games/:id`.
2. После Join проверить базу: `Game.status == "started"`, `state != nil`, ровно два GamePlayer; принадлежность Player, Nation, Deck и HQ правильна.
3. Закрепить структуру GameState после StartGame: status, turn number, current player, turn start, players, field, оба HQ, hand/deck/graveyard/platoons/resources/remaining time и стартовый Fuel первого игрока.
4. Проверить VisibleState каждого игрока: своя hand видна, чужие hand/deck/graveyard и порядок deck скрыты.
5. Проверить все доступные controller Actions для `waiting + state == nil`: доступ проверяется до waiting boundary; чужой игрок получает 403, участник — 422; Engine не вызывается.

### Finished state

Проверить все причины: `headquarters_destroyed`, `time_expired`, `empty_deck_damage`, `surrender`. Для каждой: `Game.status == finished`, корректные winner/loser/reason в `state["result"]`, пустой AvailableActions, запрет следующих Actions, неизменность результата и отсутствие раскрытия hidden information в VisibleState/UI.

### Matchmaking, waiting и Turbo

- FindOpponent: exact Weight, обе границы ±15%, выход за пределы, минимальная разница, oldest tie-break, self exclusion, exclusion started/finished/two-player games.
- Join: success, второй GamePlayer, StartGame, repeat Join, started game, game with two players, join by current participant и race-condition protection `with_lock`.
- Cleanup: stale удаляется; fresh, started, finished и `last_seen_at == nil` сохраняются.
- Browser lifecycle в двух независимых browser sessions: Deck → waiting → Join → started → first Action; проверить perspectives и hidden information.
- Зафиксировать browser disconnect через отсутствие heartbeat, stale `last_seen_at` и Cleanup; не пытаться определять закрытие браузера напрямую.
- Проверить Turbo refresh при create waiting, Join и cleanup: waiting game исчезает из других waiting rooms, участники получают started game.

### Guest lifecycle

Проверить создание и повторное использование guest Player, ровно три starter Deck, отсутствие гостя после простого `/decks`, guest waiting/Join, guest vs guest, guest vs registered, запрет Deck/statistics, cleanup гостя и защиту активных waiting/started games. Не создавать отдельный Engine и не использовать `?player_id=` или session как GameState.

### Критерий закрытия Stage 18

Все пункты выше покрыты тестами; полный lifecycle проверен в двух browser sessions; `bin/rails test` завершается без failures/errors; `PROGRESS.md` обновлён новым проверенным checkpoint.

## Следующие этапы

### Stage 19 — Human vs Human

Довести реальную PvP-партию от выбора Deck через waiting/started и Turbo до полного завершения. Не дублировать уже существующий matchmaking.

### Stage 20 — Decision Provider

Создать абстракцию Human, AI, External API, Local model и Other provider. Provider работает только с VisibleState и выдаёт Action.

### Stage 21 — AI

Подключить AI через Decision Provider без доступа к hidden information и без прямого изменения GameState или дублирования правил.

### Stage 22 — Ollama / Qwen3 1.7B

Планируемая локальная интеграция Ollama/Qwen3 1.7B только на уровне Decision Provider. GameEngine от Ollama не зависит.

### Stage 23 — AI testing

Проверить валидность Action, ограничения VisibleState, запрещённые actions, ошибки provider, отсутствие hidden information и невозможность прямой мутации GameState.
