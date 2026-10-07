# DEVELOPMENT.md

## Порядок работы

Перед изменением кода прочитать `AGENTS.md` и этот файл; затем — документы по задаче из таблицы в `AGENTS.md`. Существенные изменения предварительно обсуждать с пользователем. Вносить только необходимые изменения, добавлять или обновлять тесты и после завершения существенного этапа запускать:

```bash
bin/rails test
```

Для UI работать маленькими шагами и после существенных UI-изменений проверять результат непосредственно в браузере. После значимого этапа делать Git commit. Без явной команды пользователя не изменять файлы проекта.

## Seed и базовый контент

Seed расположен в:

```text
db/
├── seeds.rb
└── seeds/
    ├── nations.rb
    ├── abilities.rb
    ├── cards.rb
    └── card_abilities.rb
```

Seed создаёт только базовый игровой контент: `Nation`, `Ability`, `Card`, `Technique`, `Platoon`, `Headquarters`, `CardAbility`. Он идемпотентен.

Не изменять через seed `Player`, `Deck`, `DeckCard`, `Game` и `GamePlayer`; не применять `destroy_all` или `delete_all` к пользовательским данным. Текущий базовый контент: 3 Nation, 2 Ability, 33 Card, 18 Technique, 6 Platoon, 3 Headquarters и 6 CardAbility; nations: `ussr`, `germany`, `usa`.

## Обязательные технические запреты

- Не переносить игровую логику в Controllers, ActiveRecord, UI, Stimulus/JavaScript, Turbo/Action Cable или AI.
- Не мутировать исходный `GameState`, не хранить его в session/cookies и не сохранять каждое промежуточное изменение.
- Не изменять persistent Deck во время партии, не хранить runtime Platoon в `field` и не уплотнять Platoon slots.
- Не создавать `TechniqueAbility`, `HeadquartersAbility`, отдельный HQ level, отдельную систему spotting для HQ, Draw Action, отдельную систему победы или surrender.
- Не раскрывать hidden information через `VisibleState`; не вычислять `AvailableActions` в Stimulus; CSS и JavaScript не являются механизмами безопасности.
- Не использовать `?player_id=` или dev-player ID для пользовательской идентификации.
- Не считать координаты постоянным ID Technique, визуальный порядок клеток — логическими координатами, либо `movement_count` — counterattack.
- Не передавать Platoon slot из UI в `play_card`; Drag & Drop не является отдельной системой правил.
- Не менять логические координаты ради перспективы, не использовать `transform: rotate(180deg)` и не дублировать перспективу в Stimulus.
- Не создавать AI-соперника автоматически в PvP; не превращать список waiting players в ручной выбор комнаты.
- Не хранить matchmaking metadata в `GameState`, не считать `Game.last_seen_at` игровой механикой, не удалять `started`/`finished` games waiting-cleanup.
- Не создавать отдельный Engine или отдельную игровую систему для гостей.

Игровые запреты и точные правила дополнительно определяются `GAME_RULES.md`; архитектурная мотивация — `ARCHITECTURE.md`.
