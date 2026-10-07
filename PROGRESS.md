# PROGRESS.md

## Текущая контрольная точка

Завершены:

- Stage 1–14;
- Stage 15.1–15.17;
- Stage 16 — Players;
- Stage 17 — Deck UI;
- Stage 18 — Waiting / Started.

Последний проверенный результат:

```text
bin/rails test
448 runs, 1491 assertions, 0 failures, 0 errors, 0 skips

bin/rails test test/controllers/games_controller_test.rb
35 runs, 282 assertions, 0 failures, 0 errors, 0 skips

bin/rails test test/services/matchmaking/cleanup_stale_waiting_games_test.rb
6 runs, 8 assertions, 0 failures, 0 errors, 0 skips

Stage 18 закрыт после завершения автоматических проверок и полного browser lifecycle.

Реализованные игровые и технические основы
Engine с Action/Result, immutable GameState, VisibleState и server-side AvailableActions.
StartGame, Draw, turns, Fuel, timer, PlayCard, Move, Attack, HQ/Platoon, FinishGame и Surrender.
Hidden information, события Engine и визуальные Turbo/Stimulus реакции.
Seed базового контента: 3 Nation, 2 Ability, 33 Card, 18 Technique, 6 Platoon, 3 Headquarters, 6 CardAbility.
Browser UI: selection, Drag & Drop, player perspective, finished UI, timer и Turbo updates.
Account/guest identity на Player и session-based authentication.
Stage 16 — Players

Stage 16 завершён.

Реализованы:

Player как account и игровая сущность;
registration;
login;
logout;
has_secure_password;
current_player;
session-based identity;
header;
публичные страницы;
зарегистрированный /statistics;
development command bin/rails dev:create_game.

Отдельная модель User и Devise не используются.

Stage 17 — Deck UI

Stage 17 завершён.

Реализованы:

Deck;
DeckCard;
Deck Weight;
Headquarters;
StarterDecks::Create;
starter Deck при регистрации;
starter Deck при создании гостя;
публичный каталог Cards;
/decks;
список и preview Deck;
editor;
quantity и валидации;
create/edit/destroy;
тесты;
browser UI.

/decks — только управление колодами. Кнопки «В бой» на этой странице нет.

Запуск игры с полной Deck выполняется через /play.

Гость может просматривать starter Deck, но не может управлять Deck.

Stage 18 — Waiting / Started

Stage 18 завершён.

/play и matchmaking

Реализованы:

/play;
выбор полной Deck;
PvP;
UI-кнопка AI;
создание waiting Game;
создание первого GamePlayer;
Matchmaking::FindOpponent;
точный Weight;
диапазон Weight ±15%;
ближайший Weight;
oldest tie-break;
self exclusion;
исключение started/finished/two-player games;
Matchmaking::Join;
row lock через with_lock;
второй GamePlayer;
StartGame;
переход waiting → started;
защита от повторного Join;
cancel waiting.
Game lifecycle

Проверен полный путь:

Player/Guest
  → /play
  → complete Deck
  → PvP
  → FindOpponent
  → waiting
  → heartbeat
  → Join
  → StartGame
  → started
  → first Action

После Join проверяются:

Game.status;
Game.state;
количество GamePlayer;
Player;
Nation;
Deck;
Headquarters;
структура начального GameState;
стартовый Fuel;
current player;
turn information;
field;
HQ;
hand;
deck;
graveyard;
platoons;
resources;
remaining time.
VisibleState

Проверено, что каждый игрок получает:

собственную hand;
доступную ему информацию о состоянии игры;

и не получает:

hidden hand противника;
содержимое deck противника;
порядок deck противника;
hidden graveyard information противника.
Controller boundary

Для waiting + state == nil проверены controller Actions.

Участник waiting game получает 422, посторонний игрок — 403.

Waiting game не передаётся в GameEngine как обычная started game.

Finished state

Проверены причины завершения:

headquarters_destroyed;
time_expired;
empty_deck_damage;
surrender.

Проверяются:

Game.status == finished;
winner;
loser;
reason;
пустой AvailableActions;
запрет следующих Actions;
неизменность результата;
отсутствие раскрытия hidden information.
Waiting heartbeat и cleanup

Реализован heartbeat waiting room:

первый heartbeat при подключении;
последующие heartbeat каждые 10 секунд;
остановка heartbeat при disconnect Stimulus controller;
session-based request;
CSRF token.

Controller-тестами проверены:

успешное обновление Game.last_seen_at;
heartbeat чужой игры — 403;
heartbeat started game — 422;
heartbeat без authentication — 401.

Matchmaking::CleanupStaleWaitingGames:

удаляет stale waiting games;
сохраняет fresh waiting games;
сохраняет started games;
сохраняет finished games;
сохраняет waiting games с last_seen_at == nil;
отправляет Turbo refresh оставшимся waiting rooms после удаления stale game.
Turbo

Проверены Turbo refresh при:

Join;
создании waiting game;
cleanup stale waiting game.

При Join:

waiting room соперника получает refresh;
другие waiting rooms получают refresh;
joined game становится started.
Guest lifecycle

Реализован единый guest lifecycle через Player.

Гость:

создаётся при входе в /play, если нет current player;
получает временный Player;
получает ровно три starter Deck;
сохраняет identity в session;
повторный /play использует существующего guest Player;
может участвовать в guest vs guest;
может участвовать в guest vs registered;
использует тот же GameEngine, что и registered Player.

Гость не может:

управлять Deck;
использовать /statistics.

Простой просмотр /decks не создаёт guest Player.

Guest cleanup

Реализован cleanup неактивных гостей:

threshold — 24 часа;
cleanup запускается при создании нового guest;
существующий current guest повторно не создаётся;
guest с active waiting/started game не удаляется;
stale guest без active game удаляется;
starter Deck удаляются вместе с guest Player;
finished GamePlayer удаляются перед удалением guest Player;
историческая Game сохраняется.

Guest browser lifecycle проверен вручную.

Browser lifecycle

Полный lifecycle проверен в двух независимых browser sessions:

Deck
→ waiting
→ Join
→ started
→ first Action

Проверены:

guest;
registered Player;
guest vs guest;
guest vs registered;
waiting room;
Join;
started game;
perspectives;
hidden information;
Actions;
surrender;
HQ destruction.

Browser disconnect не определяется напрямую. Waiting activity определяется через heartbeat, stale last_seen_at и cleanup.

Повторять этот browser lifecycle перед закрытием Stage 18 не требуется.

Архитектурные границы

Основной поток:

UI → Stimulus → Controller → Action → GameEngine → GameState → VisibleState → Turbo → Stimulus

Identity:

browser session → current_player → GamePlayer → Action.player_id → GameEngine

Decision Provider:

VisibleState → Decision Provider → Action → GameEngine → GameState

GameEngine остаётся единственным арбитром игровых правил.

Controllers, UI, JavaScript, Stimulus, Turbo и AI не изменяют GameState напрямую и не дублируют игровые правила.

Event propagation:

Engine operation
→ Result.events
→ nested operation
→ Result.events
→ Controller
→ Turbo
→ Stimulus visual reaction

События UI не являются источником игровых правил.

Следующий этап
Stage 19 — Human vs Human

Цель — довести полноценную PvP-партию двух Human Player от выбора Deck через waiting/started и Turbo до полного завершения партии.

Не дублировать уже реализованные matchmaking, waiting, StartGame и guest infrastructure.


После замены этих двух файлов Stage 18 документально закрыт, а следующей рабочей точкой становится **Stage 19 — Human vs Human**.
