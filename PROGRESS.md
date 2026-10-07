# PROGRESS.md

## Текущая контрольная точка

Завершены Stage 1–14, Stage 15.1–15.17, Stage 16 и Stage 17. Stage 18 находится в процессе: основная waiting → started инфраструктура реализована и проверялась в браузере, но этап не закрыт до завершения integration coverage и проверок границ.

Последний зафиксированный (исторический) результат до дальнейшего расширения Stage 18:

```text
bin/rails test
417 runs, 1256 assertions, 0 failures, 0 errors, 0 skips

bin/rails test test/controllers/games_controller_test.rb
23 runs, 121 assertions, 0 failures, 0 errors, 0 skips
```

Это checkpoint, а не замена повторному запуску тестов после новых изменений.

## Реализованные игровые и технические основы

- Engine с Action/Result, immutable GameState, VisibleState и server-side AvailableActions.
- StartGame, Draw, turns, Fuel, timer, PlayCard, Move, Attack, HQ/Platoon, FinishGame и Surrender.
- Hidden information, события Engine и визуальные Turbo/Stimulus реакции.
- Seed базового контента: 3 Nation, 2 Ability, 33 Card, 18 Technique, 6 Platoon, 3 Headquarters, 6 CardAbility.
- Browser UI: selection, Drag & Drop, player perspective, finished UI, timer и Turbo updates.
- Account/guest identity на Player и session-based authentication.

## Stage 16 — Players

Stage 16 завершён: registration, login, logout, `has_secure_password`, `current_player`, header, публичные страницы, зарегистрированный `/statistics` и development command `bin/rails dev:create_game`.

## Stage 17 — Deck UI

Stage 17 завершён. Реализованы Deck/DeckCard/Deck Weight/HQ, `StarterDecks::Create`, starter Deck при регистрации и создании гостя, публичный каталог Cards, `/decks`, список и preview Deck, editor, quantity/валидации, create/edit/destroy, тесты и browser UI.

`/decks` — только управление колодами: кнопки «В бой» на нём нет. Запуск с полной Deck выполняется только через `/play`. Гость может просматривать starter Deck, но не может управлять Deck.

## Реализованная часть Stage 18

- `/play`, выбор полной Deck, PvP и UI-кнопка AI (сам AI пока не реализован).
- Создание waiting Game и первого GamePlayer.
- `Matchmaking::FindOpponent`: Weight ±15%, ближайший Weight, oldest tie-break, self exclusion, только waiting one-player games.
- `Matchmaking::Join`: row lock, второй GamePlayer, StartGame, переход waiting → started.
- Cancel waiting, heartbeat и stale waiting cleanup.
- Turbo refresh waiting rooms и started game.
- Guest creation, guest starter Deck, guest PvP, guest vs guest, guest vs registered, Deck restrictions.
- Controller boundary для `waiting + state == nil`.
- Browser-проверки guest `/play`, waiting room, guest/registered combinations, surrender и HQ destruction.

Текущий PvP lifecycle:

```text
Player/Guest → /play → complete Deck → PvP
  ├── FindOpponent → Join → StartGame → started
  └── no opponent → waiting Game → heartbeat/cancel → Join → StartGame
```

## Текущее состояние guest mode

Гостевой игровой вход реализован: `/play` создаёт временного Player, три starter Deck и сохраняет identity в session. Engine не различает guest/registered. Гость может иметь несколько игр, участвовать в guest vs guest и guest vs registered; публичный `/decks` его не создаёт.

`Player.last_seen_at` обновляется для гостя. Отдельная реализация и тесты cleanup гостей, а также защита активных waiting/started games от такого cleanup требуют финальной проверки и остаются в `ROADMAP.md`; не считать их подтверждённо завершёнными.

## Реализованные архитектурные границы

```text
UI → Stimulus → Controller → Action → GameEngine → GameState → VisibleState → Turbo → Stimulus

browser session → current_player → GamePlayer → Action.player_id → GameEngine

VisibleState → Decision Provider → Action → GameEngine → GameState
```

Event propagation: Engine operation → `Result.events` → nested operation → `Result.events` → Controller → Turbo → Stimulus visual reaction. События UI не являются источником правил.
