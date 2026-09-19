# CARDS.md

> Каталог базовых карт проекта `clash_tanks`.
>
> Этот файл описывает конкретный игровой контент: штабы, Technique, Order и Platoon.
>
> `GAME_RULES.md` описывает правила игры.
> `AGENTS.md` описывает архитектуру и техническую реализацию.
> `CARDS.md` описывает существующие карты и их характеристики.
>
> При изменении характеристик карт этот файл должен обновляться вместе с seed.

---

# 1. Общая информация

В базовом наборе:

- 3 штаба;
- 18 Technique;
- 6 Order;
- 6 Platoon.

Всего:

**33 карты.**

Нации:

- СССР;
- Германия;
- США.

---

# 2. Общие правила характеристик карт

## 2.1. Weight

`weight` — вес карты для колоды.

Он не является стоимостью розыгрыша.

## 2.2. Price

`price` — стоимость розыгрыша карты.

Для штабов `price` отсутствует (`nil`).

## 2.3. Fuel Technique

`fuel` Technique — количество Fuel, которое эта Technique добавляет при расчёте Fuel игрока, когда находится на поле.

Это не стоимость розыгрыша.

## 2.4. Fuel Platoon

`fuel` Platoon также учитывается при расчёте Fuel игрока, когда Platoon находится в активном слоте.

## 2.5. Attack Range

Для всех существующих Technique:

`attack_range = 1`.

Для SAU (`artillery`) дальняя атака является специальным правилом и требует spotting. Она не определяется только значением `attack_range`.

## 2.6. Movement

Базовое соответствие:

| Тип | Движение | Количество |
|---|---|---:|
| Light Tank | orthogonal | 2 |
| Medium Tank | diagonal | 1 |
| Heavy Tank | orthogonal | 1 |
| Tank Destroyer | orthogonal | 1 |
| Artillery | orthogonal | 1 |

---

# 3. Штабы

Штаб является отдельной картой типа `headquarters`.

Для штаба:

- `price = nil`;
- `attack_range` отсутствует;
- `movement` отсутствует;
- штаб размещается на стартовой клетке;
- характеристики HQ становятся runtime-характеристиками штаба.

## 3.1. Германия

### Pz.Kpfw. Headquarters

| Поле | Значение |
|---|---|
| Code | `germany_headquarters` |
| Nation | Германия |
| Type | `headquarters` |
| Weight | 1 |
| Price | nil |
| HP | 16 |
| Firepower | 2 |
| Fuel | 4 |

---

## 3.2. США

### USA Headquarters

| Поле | Значение |
|---|---|
| Code | `usa_headquarters` |
| Nation | США |
| Type | `headquarters` |
| Weight | 1 |
| Price | nil |
| HP | 17 |
| Firepower | 1 |
| Fuel | 6 |

---

## 3.3. СССР

### USSR Headquarters

| Поле | Значение |
|---|---|
| Code | `ussr_headquarters` |
| Nation | СССР |
| Type | `headquarters` |
| Weight | 1 |
| Price | nil |
| HP | 19 |
| Firepower | 1 |
| Fuel | 5 |

---

# 4. Германия

Всего карт Германии: **11**

- 1 штаб;
- 6 Technique;
- 2 Order;
- 2 Platoon.

---

## 4.1. Pz.II Ausf. L «Luchs»

| Поле | Значение |
|---|---|
| Code | `germany_pz_ii_l_luchs` |
| Nation | Германия |
| Type | `technique` |
| Technique Type | `light_tank` |
| Weight | 1 |
| Price | 2 |
| HP | 4 |
| Firepower | 2 |
| Fuel | 2 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 2 |

---

## 4.2. Pz.III Ausf. J

| Поле | Значение |
|---|---|
| Code | `germany_pz_iii_j` |
| Nation | Германия |
| Type | `technique` |
| Technique Type | `medium_tank` |
| Weight | 1 |
| Price | 3 |
| HP | 6 |
| Firepower | 3 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `diagonal` |
| Movement Count | 1 |

---

## 4.3. Pz.IV Ausf. H

| Поле | Значение |
|---|---|
| Code | `germany_pz_iv_h` |
| Nation | Германия |
| Type | `technique` |
| Technique Type | `medium_tank` |
| Weight | 2 |
| Price | 4 |
| HP | 8 |
| Firepower | 4 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `diagonal` |
| Movement Count | 1 |

---

## 4.4. Pz.VI Tiger I

| Поле | Значение |
|---|---|
| Code | `germany_tiger_i` |
| Nation | Германия |
| Type | `technique` |
| Technique Type | `heavy_tank` |
| Weight | 4 |
| Price | 6 |
| HP | 12 |
| Firepower | 5 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |

---

## 4.5. Jagdpanther

| Поле | Значение |
|---|---|
| Code | `germany_jagdpanther` |
| Nation | Германия |
| Type | `technique` |
| Technique Type | `tank_destroyer` |
| Weight | 3 |
| Price | 5 |
| HP | 8 |
| Firepower | 4 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |
| Special | Первый выстрел |

Jagdpanther является PT-SAU.

В бою PT-SAU стреляет первым согласно правилам Stage 12.

---

## 4.6. Hummel

| Поле | Значение |
|---|---|
| Code | `germany_hummel` |
| Nation | Германия |
| Type | `technique` |
| Technique Type | `artillery` |
| Weight | 2 |
| Price | 4 |
| HP | 5 |
| Firepower | 3 |
| Fuel | 2 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |
| Special | Дальняя атака при spotting |

Hummel является SAU.

Для дальней атаки требуется spotting.

Источником spotting может быть:

- союзная Technique;
- наш штаб / штаб атакующего игрока.

---

## 4.7. «Точный выстрел»

| Поле | Значение |
|---|---|
| Code | `germany_tocnyj_vystrel` |
| Nation | Германия |
| Type | `order` |
| Weight | 3 |
| Price | 4 |
| Ability | `damage_technique` |
| Parameters | `damage: 4` |

---

## 4.8. «Радиоперехват»

| Поле | Значение |
|---|---|
| Code | `germany_radioperekhvat` |
| Nation | Германия |
| Type | `order` |
| Weight | 2 |
| Price | 3 |
| Ability | `draw_cards` |
| Parameters | `count: 2` |

---

## 4.9. Гренадёрский взвод

| Поле | Значение |
|---|---|
| Code | `germany_grenaderskij_vzvod` |
| Nation | Германия |
| Type | `platoon` |
| Weight | 2 |
| Price | 3 |
| HP | 6 |
| Firepower | 2 |
| Armor | 0 |
| Fuel | 0 |

---

## 4.10. Расчёт Flak 88

| Поле | Значение |
|---|---|
| Code | `germany_flak_88` |
| Nation | Германия |
| Type | `platoon` |
| Weight | 3 |
| Price | 3 |
| HP | 5 |
| Firepower | 0 |
| Armor | 2 |
| Fuel | 0 |

`Firepower = 0` является допустимым значением.

---

# 5. США

Всего карт США: **11**

- 1 штаб;
- 6 Technique;
- 2 Order;
- 2 Platoon.

---

## 5.1. M3 Stuart

| Поле | Значение |
|---|---|
| Code | `usa_m3_stuart` |
| Nation | США |
| Type | `technique` |
| Technique Type | `light_tank` |
| Weight | 1 |
| Price | 2 |
| HP | 4 |
| Firepower | 2 |
| Fuel | 2 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 2 |

---

## 5.2. M4 Sherman

| Поле | Значение |
|---|---|
| Code | `usa_m4_sherman` |
| Nation | США |
| Type | `technique` |
| Technique Type | `medium_tank` |
| Weight | 2 |
| Price | 4 |
| HP | 6 |
| Firepower | 2 |
| Fuel | 2 |
| Attack Range | 1 |
| Movement Type | `diagonal` |
| Movement Count | 1 |

---

## 5.3. M4A3E8 «Easy Eight»

| Поле | Значение |
|---|---|
| Code | `usa_m4a3e8_easy_eight` |
| Nation | США |
| Type | `technique` |
| Technique Type | `medium_tank` |
| Weight | 3 |
| Price | 5 |
| HP | 8 |
| Firepower | 4 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `diagonal` |
| Movement Count | 1 |

---

## 5.4. M26 Pershing

| Поле | Значение |
|---|---|
| Code | `usa_m26_pershing` |
| Nation | США |
| Type | `technique` |
| Technique Type | `heavy_tank` |
| Weight | 3 |
| Price | 6 |
| HP | 11 |
| Firepower | 4 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |

---

## 5.5. M18 Hellcat

| Поле | Значение |
|---|---|
| Code | `usa_m18_hellcat` |
| Nation | США |
| Type | `technique` |
| Technique Type | `tank_destroyer` |
| Weight | 2 |
| Price | 6 |
| HP | 5 |
| Firepower | 4 |
| Fuel | 2 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |
| Special | Первый выстрел |

M18 Hellcat является PT-SAU.

В бою PT-SAU стреляет первым согласно правилам Stage 12.

---

## 5.6. M7 Priest

| Поле | Значение |
|---|---|
| Code | `usa_m7_priest` |
| Nation | США |
| Type | `technique` |
| Technique Type | `artillery` |
| Weight | 2 |
| Price | 4 |
| HP | 5 |
| Firepower | 2 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |
| Special | Дальняя атака при spotting |

M7 Priest является SAU.

Для дальней атаки требуется spotting.

Источником spotting может быть:

- союзная Technique;
- наш штаб / штаб атакующего игрока.

---

## 5.7. «Ленд-лиз»

| Поле | Значение |
|---|---|
| Code | `usa_lend_liz` |
| Nation | США |
| Type | `order` |
| Weight | 1 |
| Price | 2 |
| Ability | `draw_cards` |
| Parameters | `count: 2` |

---

## 5.8. «Огневой налёт»

| Поле | Значение |
|---|---|
| Code | `usa_ognevoj_nalyot` |
| Nation | США |
| Type | `order` |
| Weight | 1 |
| Price | 2 |
| Ability | `damage_technique` |
| Parameters | `damage: 2` |

---

## 5.9. Инженерный взвод

| Поле | Значение |
|---|---|
| Code | `usa_inzhenernyj_vzvod` |
| Nation | США |
| Type | `platoon` |
| Weight | 3 |
| Price | 4 |
| HP | 5 |
| Firepower | 0 |
| Armor | 3 |
| Fuel | 0 |

`Firepower = 0` является допустимым значением.

---

## 5.10. Взвод базукометчиков

| Поле | Значение |
|---|---|
| Code | `usa_vzvod_bazukometchikov` |
| Nation | США |
| Type | `platoon` |
| Weight | 3 |
| Price | 4 |
| HP | 4 |
| Firepower | 2 |
| Armor | 0 |
| Fuel | 1 |

---

# 6. СССР

Всего карт СССР: **11**

- 1 штаб;
- 6 Technique;
- 2 Order;
- 2 Platoon.

---

## 6.1. Т-70

| Поле | Значение |
|---|---|
| Code | `ussr_t_70` |
| Nation | СССР |
| Type | `technique` |
| Technique Type | `light_tank` |
| Weight | 1 |
| Price | 2 |
| HP | 5 |
| Firepower | 1 |
| Fuel | 2 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 2 |

---

## 6.2. Т-34

| Поле | Значение |
|---|---|
| Code | `ussr_t_34` |
| Nation | СССР |
| Type | `technique` |
| Technique Type | `medium_tank` |
| Weight | 2 |
| Price | 4 |
| HP | 7 |
| Firepower | 2 |
| Fuel | 2 |
| Attack Range | 1 |
| Movement Type | `diagonal` |
| Movement Count | 1 |

---

## 6.3. Т-34-85

| Поле | Значение |
|---|---|
| Code | `ussr_t_34_85` |
| Nation | СССР |
| Type | `technique` |
| Technique Type | `medium_tank` |
| Weight | 3 |
| Price | 6 |
| HP | 8 |
| Firepower | 3 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `diagonal` |
| Movement Count | 1 |

---

## 6.4. ИС-2

| Поле | Значение |
|---|---|
| Code | `ussr_is_2` |
| Nation | СССР |
| Type | `technique` |
| Technique Type | `heavy_tank` |
| Weight | 3 |
| Price | 6 |
| HP | 12 |
| Firepower | 3 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |

---

## 6.5. СУ-100

| Поле | Значение |
|---|---|
| Code | `ussr_su_100` |
| Nation | СССР |
| Type | `technique` |
| Technique Type | `tank_destroyer` |
| Weight | 3 |
| Price | 5 |
| HP | 6 |
| Firepower | 3 |
| Fuel | 1 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |
| Special | Первый выстрел |

СУ-100 является PT-SAU.

В бою PT-SAU стреляет первым согласно правилам Stage 12.

---

## 6.6. СУ-26

| Поле | Значение |
|---|---|
| Code | `ussr_su_26` |
| Nation | СССР |
| Type | `technique` |
| Technique Type | `artillery` |
| Weight | 2 |
| Price | 6 |
| HP | 7 |
| Firepower | 2 |
| Fuel | 2 |
| Attack Range | 1 |
| Movement Type | `orthogonal` |
| Movement Count | 1 |
| Special | Дальняя атака при spotting |

СУ-26 является SAU.

Для дальней атаки требуется spotting.

Источником spotting может быть:

- союзная Technique;
- наш штаб / штаб атакующего игрока.

---

## 6.7. «Залп „Катюши“»

| Поле | Значение |
|---|---|
| Code | `ussr_zalp_katyushi` |
| Nation | СССР |
| Type | `order` |
| Weight | 2 |
| Price | 3 |
| Ability | `damage_technique` |
| Parameters | `damage: 3` |

---

## 6.8. «Пополнение»

| Поле | Значение |
|---|---|
| Code | `ussr_popolnenie` |
| Nation | СССР |
| Type | `order` |
| Weight | 2 |
| Price | 2 |
| Ability | `draw_cards` |
| Parameters | `count: 1` |

---

## 6.9. Стрелковый взвод

| Поле | Значение |
|---|---|
| Code | `ussr_strelkovyj_vzvod` |
| Nation | СССР |
| Type | `platoon` |
| Weight | 2 |
| Price | 3 |
| HP | 5 |
| Firepower | 1 |
| Armor | 0 |
| Fuel | 0 |

---

## 6.10. Взвод ПТР

| Поле | Значение |
|---|---|
| Code | `ussr_vzvod_ptr` |
| Nation | СССР |
| Type | `platoon` |
| Weight | 3 |
| Price | 4 |
| HP | 6 |
| Firepower | 1 |
| Armor | 2 |
| Fuel | 0 |

---

# 7. Сводная таблица Technique

| Nation | Card | Type | Weight | Price | HP | Firepower | Fuel | Movement |
|---|---|---|---:|---:|---:|---:|---:|---|
| Германия | Pz.II Ausf. L «Luchs» | LT | 1 | 2 | 4 | 2 | 2 | 2 orthogonal |
| Германия | Pz.III Ausf. J | ST | 1 | 3 | 6 | 3 | 1 | 1 diagonal |
| Германия | Pz.IV Ausf. H | ST | 2 | 4 | 8 | 4 | 1 | 1 diagonal |
| Германия | Pz.VI Tiger I | TT | 4 | 6 | 12 | 5 | 1 | 1 orthogonal |
| Германия | Jagdpanther | PT-SAU | 3 | 5 | 8 | 4 | 1 | 1 orthogonal |
| Германия | Hummel | SAU | 2 | 4 | 5 | 3 | 2 | 1 orthogonal |
| США | M3 Stuart | LT | 1 | 2 | 4 | 2 | 2 | 2 orthogonal |
| США | M4 Sherman | ST | 2 | 4 | 6 | 2 | 2 | 1 diagonal |
| США | M4A3E8 «Easy Eight» | ST | 3 | 5 | 8 | 4 | 1 | 1 diagonal |
| США | M26 Pershing | TT | 3 | 6 | 11 | 4 | 1 | 1 orthogonal |
| США | M18 Hellcat | PT-SAU | 2 | 6 | 5 | 4 | 2 | 1 orthogonal |
| США | M7 Priest | SAU | 2 | 4 | 5 | 2 | 1 | 1 orthogonal |
| СССР | Т-70 | LT | 1 | 2 | 5 | 1 | 2 | 2 orthogonal |
| СССР | Т-34 | ST | 2 | 4 | 7 | 2 | 2 | 1 diagonal |
| СССР | Т-34-85 | ST | 3 | 6 | 8 | 3 | 1 | 1 diagonal |
| СССР | ИС-2 | TT | 3 | 6 | 12 | 3 | 1 | 1 orthogonal |
| СССР | СУ-100 | PT-SAU | 3 | 5 | 6 | 3 | 1 | 1 orthogonal |
| СССР | СУ-26 | SAU | 2 | 6 | 7 | 2 | 2 | 1 orthogonal |

---

# 8. Сводная таблица Order

| Nation | Card | Weight | Price | Ability | Parameter |
|---|---|---:|---:|---|---:|
| Германия | «Точный выстрел» | 3 | 4 | damage_technique | damage: 4 |
| Германия | «Радиоперехват» | 2 | 3 | draw_cards | count: 2 |
| США | «Ленд-лиз» | 1 | 2 | draw_cards | count: 2 |
| США | «Огневой налёт» | 1 | 2 | damage_technique | damage: 2 |
| СССР | «Залп „Катюши“» | 2 | 3 | damage_technique | damage: 3 |
| СССР | «Пополнение» | 2 | 2 | draw_cards | count: 1 |

---

# 9. Сводная таблица Platoon

| Nation | Card | Weight | Price | HP | Firepower | Armor | Fuel |
|---|---|---:|---:|---:|---:|---:|---:|
| Германия | Гренадёрский взвод | 2 | 3 | 6 | 2 | 0 | 0 |
| Германия | Расчёт Flak 88 | 3 | 3 | 5 | 0 | 2 | 0 |
| США | Инженерный взвод | 3 | 4 | 5 | 0 | 3 | 0 |
| США | Взвод базукометчиков | 3 | 4 | 4 | 2 | 0 | 1 |
| СССР | Стрелковый взвод | 2 | 3 | 5 | 1 | 0 | 0 |
| СССР | Взвод ПТР | 3 | 4 | 6 | 1 | 2 | 0 |

---

# 10. Сводная таблица HQ

| Nation | Code | Weight | HP | Firepower | Fuel |
|---|---|---:|---:|---:|---:|
| Германия | `germany_headquarters` | 1 | 16 | 2 | 4 |
| США | `usa_headquarters` | 1 | 17 | 1 | 6 |
| СССР | `ussr_headquarters` | 1 | 19 | 1 | 5 |

---

# 11. Abilities

В базовом наборе используются две универсальные способности.

## 11.1. damage_technique

Наносит указанное количество урона Technique.

Параметр:

```text
damage
```

Используют:

- Германия — «Точный выстрел»: 4;
- США — «Огневой налёт»: 2;
- СССР — «Залп „Катюши“»: 3.

## 11.2. draw_cards

Выполняет дополнительный Draw указанного количества карт.

Параметр:

```text
count
```

Используют:

- Германия — «Радиоперехват»: 2;
- США — «Ленд-лиз»: 2;
- СССР — «Пополнение»: 1.

## 12. Специальные характеристики Technique

### Light Tank

Все Light Tank:

- movement type: `orthogonal`;
- movement count: `2`.

Карты:

- Pz.II Ausf. L «Luchs»;
- M3 Stuart;
- Т-70.

### Medium Tank

Все Medium Tank:

- movement type: `diagonal`;
- movement count: `1`.

Карты:

- Pz.III Ausf. J;
- Pz.IV Ausf. H;
- M4 Sherman;
- M4A3E8 «Easy Eight»;
- Т-34;
- Т-34-85.

### Heavy Tank

Все Heavy Tank:

- movement type: `orthogonal`;
- movement count: `1`.

Карты:

- Pz.VI Tiger I;
- M26 Pershing;
- ИС-2.

### Tank Destroyer / PT-SAU

Все PT-SAU:

- movement type: `orthogonal`;
- movement count: `1`;
- имеют правило первого выстрела.

Карты:

- Jagdpanther;
- M18 Hellcat;
- СУ-100.

### Artillery / SAU

Все SAU:

- movement type: `orthogonal`;
- movement count: `1`;
- могут использовать дальнюю атаку при наличии spotting;
- дальняя атака не вызывает counterattack.

Карты:

- Hummel;
- M7 Priest;
- СУ-26.

## 13. Важные ограничения

- Не создавать новые карты без изменения этого файла и соответствующего seed.
- Не менять характеристики карт только в seed без обновления `CARDS.md`.
- `Card.code` должен оставаться стабильным после создания карты.
- Изменение `name` не должно создавать новую карту.
- `price` и `weight` не следует путать.
- `Technique.fuel` и `Platoon.fuel` являются характеристиками карты/runtime-объекта, а не стоимостью розыгрыша.
- Technique не имеет Armor.
- Platoon может иметь `firepower = 0`.
- HQ не имеет `price`.
- SAU не получает отдельную Ability для spotting.
- PT-SAU не получает отдельную Ability для первого выстрела.
- Специальные боевые правила реализуются игровым движком, а не через Ability без необходимости.

## 14. Контрольное количество

Ожидаемое количество записей после seed:

```text
Nations:       3
Abilities:     2
Cards:        33
Headquarters:  3
Techniques:   18
Orders:        6
Platoons:      6
CardAbilities: 6
```

Разбивка по Nation:

```text
Германия: 11 карт
США:      11 карт
СССР:     11 карт
```

Всего:

```text
33 карты
```
