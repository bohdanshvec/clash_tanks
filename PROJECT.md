# PROJECT.md

## Назначение

**clash_tanks** — учебная браузерная пошаговая карточная стратегия про танки. Проект вдохновлён WoT: Generals, но использует собственные названия, правила, карты и материалы.

Стек: Ruby 3.4.10, Rails 8.1.3.1, PostgreSQL, Hotwire/Turbo/Stimulus, RVM и Ubuntu 22.04.

Запуск разработки:

```bash
bin/dev
```

PostgreSQL 12 и 14 не изменять и не удалять без явного указания.

## Структура репозитория

```text
clash_tanks/
├── app/
│   ├── controllers/           # HTTP-границы и вызов Action/Engine
│   ├── javascript/controllers/# Stimulus: отображение и ввод пользователя
│   ├── models/                # ActiveRecord-модели и persistent-данные
│   ├── services/
│   │   ├── game_engine/       # Engine, state, actions, rules и abilities
│   │   ├── matchmaking/       # waiting room и поиск соперника
│   │   ├── guest_players/     # создание временного игрока
│   │   └── starter_decks/     # единый источник starter Deck
│   └── views/                 # ERB, Turbo и игровые представления
├── config/                    # Rails-конфигурация и маршруты
├── db/
│   ├── migrate/               # миграции
│   ├── seeds.rb               # вход в базовый игровой seed
│   └── seeds/                 # nations, abilities, cards, card_abilities
├── test/                      # model, service и controller tests
├── GAME_RULES.md              # правила игры
├── CARDS.md                   # каталог карт
├── ARCHITECTURE.md            # устройство приложения
├── DEVELOPMENT.md             # правила разработки
├── PROGRESS.md                # реализованное состояние
├── ROADMAP.md                 # дальнейшая работа
└── AGENTS.md                  # краткая точка входа для AI
```

## Границы документов

| Файл | Содержит | Не содержит |
|---|---|---|
| `GAME_RULES.md` | Правила, победу, ход, бой, ресурсы, скрытую информацию. | Детали Rails-реализации. |
| `CARDS.md` | Существующие карты и их характеристики. | Новые непроверенные карты. |
| `ARCHITECTURE.md` | Техническую реализацию и инварианты приложения. | Альтернативные игровые правила. |
| `DEVELOPMENT.md` | Процесс, тесты, seed и запреты. | Статус этапов как источник истины. |
| `PROGRESS.md` | То, что уже реализовано и проверено. | Планируемую работу. |
| `ROADMAP.md` | Незавершённые задачи и критерии готовности. | Утверждение, что задача уже сделана. |
| `AGENTS.md` | Минимальные обязательные инструкции и маршрутизацию по документации. | Подробное описание всего проекта. |
