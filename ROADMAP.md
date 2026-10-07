# ROADMAP.md

## Текущий этап: Stage 19 — Human vs Human

Stage 18 — **завершён**.

### Stage 19 — Human vs Human

Довести реальную PvP-партию от выбора Deck через waiting/started и Turbo до полного завершения партии.

Основные задачи:

- проверить полноценную игру двух Human Player через существующий GameEngine;
- использовать существующий путь:
  `Player → /play → Deck → waiting/started → Action → GameEngine`;
- не дублировать matchmaking, StartGame, guest lifecycle и waiting infrastructure;
- обеспечить корректную работу всех существующих игровых Actions через два браузерных клиента;
- проверить синхронизацию состояния между двумя игроками через Turbo;
- проверить смену хода и timer в двух браузерных клиентах;
- проверить корректность VisibleState для каждого игрока после игровых действий;
- проверить hidden information на протяжении всей партии;
- довести PvP до всех существующих вариантов завершения:
  `headquarters_destroyed`,
  `time_expired`,
  `empty_deck_damage`,
  `surrender`;
- проверить, что после завершения партии оба клиента получают finished state и дальнейшие Actions запрещены;
- не переносить игровые правила в Controller, Stimulus или Turbo.

### Stage 20 — Decision Provider

Создать абстракцию Decision Provider для:

- Human;
- AI;
- External API;
- Local model;
- Other provider.

Provider работает только с `VisibleState` и выдаёт `Action`.

GameEngine остаётся единственным арбитром правил.

### Stage 21 — AI

Подключить AI через Decision Provider.

AI:

- получает только разрешённый `VisibleState`;
- не получает hidden information;
- не изменяет `GameState`;
- не применяет игровые правила самостоятельно;
- выдаёт только `Action`;
- проходит через тот же GameEngine, что и Human Player.

### Stage 22 — Ollama / Qwen3 1.7B

Планируемая локальная интеграция Ollama/Qwen3 1.7B только на уровне Decision Provider.

GameEngine не должен зависеть от Ollama.

### Stage 23 — AI testing

Проверить:

- валидность `Action`;
- ограничения `VisibleState`;
- запрещённые Actions;
- ошибки Decision Provider;
- отсутствие hidden information;
- невозможность прямой мутации `GameState`;
- корректное поведение при недоступности или ошибке AI provider.

### Stage 24 — дальнейшее развитие

Новые игровые механики, UI, карты, баланс, AI и другие возможности определяются после завершения предыдущих этапов.

---

## Завершённые этапы

Stage 1–14  
Stage 15.1–15.17  
Stage 16 — Players  
Stage 17 — Deck UI  
Stage 18 — Waiting / Started
