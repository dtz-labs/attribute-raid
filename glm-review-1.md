# Code review — główna pętla, hot path, pocisk czołgu

Zakres: `src/main.asm`, `src/entities.asm`, `src/sprite_renderer.asm`,
`src/course_renderer.asm`, `src/input.asm`, `src/state.asm`.

Liczby T-stanów są **statyczne** (zliczone z listingu), niezmierzone. Budżet
ramki 48K: **69 888 T**. Scena odniesienia: `speed_pixels=1`, gracz + ship0 +
helikopter + FUEL + balon + czołg brzegowy; bez mostu, bez pocisków.

> Uwzględniam **główną odpowiedź na odczucie użytkownika** w §1 — objaw
> „przywlecka gdy czołg strzela" jest w 90% celową redukcją prędkości
> przewijania, a nie faktycznym spadkiem ramek.

---

## TL;DR

| # | Znalezisko | Wpływ | Trudność |
|---|---|---:|---|
| 1 | `resolve_fast_speed` kapuje `speed_pixels=1`, gdy pocisk czołgu aktywny — **percepcja zwolnienia** | 🔴 duży | trywialna (1 instrukcja) |
| 2 | `transition_shell_direct` używa generycznego `cleanup_resident_sprite_delta` zamiast dedykowanej ścieżki jak statki | 🟠 średni | mała |
| 3 | `write_water_projectile_2xn` liczy `calc_screen_line_addr` co wiersz zamiast inkrementować adres | 🟡 mały | trywialna |
| 4 | `transition_bullet_direct` — always-non-overlap (Δ=6 > h=4) — można w całości zastąpić dwoma prostymi paskami | 🟡 mały | mała |
| 5 | Przycięcie obszaru gry z 152 → 144 linii (PLAYFIELD_BOTTOM 168 → 160) | 🟡 stały ~600 T/ramka | trywialna |
| 6 | `snapshot_resident_sprite_state` — zrzut ~40 bajtów RAM co ramkę, niewarunkowo | 🟡 ~500 T | średnia |
| 7 | Drobne: kolejność `update_entities`, API `(hl)` w transition_* | 🟢 | — |

**Czyszczenie pocisków jest zrobione poprawnie** — patrz §3. Tam jest za to
jeden subtelny *visual glitch* (1-klatkowe prześwity), bez wpływ na wydajność.

---

## 1. Percepcja „przywlecania" przy strzale czołgu — PRAWDZIWA PRZYCZYNA 🔴

`src/input.asm:75-114` (`resolve_fast_speed`):

```asm
resolve_fast_speed:
    ld a,(bridge_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(destroyed_road_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(tank_active)            ; czołg brzegowy → kap
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(bridge_tank_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(enemy_plane_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(bullet_active)          ; pocisk gracza → kap
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(tank_shell_active)      ; <-- pocisk czołgu → kap
    or a
    jr nz,resolve_heavy_fast_speed
    ; ... tryb 1.5 px/frame
```

Kiedy gracz trzyma `Q` (tryb szybki ~1.5 px/frame), a czołg odda strzał,
`speed_pixels` zostaje **zredukowane z 2 do 1 w fazie 1** i utrzymywane na 1
aż do zniknięcia pocisku. Rzeka widocznie zwalnia o ~33 %. To jest **celowa
ochrona przed spadkiem ramek**, ale z perspektywy gracza wygląda jak lag.

### Dlaczego akurat `tank_shell` jest na liście

Prawdopodobnie dlatego, że łamie symetrię „każdy typ obiektu ma swój transition
path" — przejście shell→splash i splash→nic kosztuje więcej niż zwykły ruch.
Lista jest jednak **nadgorliwa**:

- `bullet_active` i `tank_shell_active` to obiekty 2-pikselowe / 4-wierszowe.
  Ich rzeczywisty narzut bitmapowy to < 400 T/ramkę (patrz §2, §4).
- Sam czołg brzegowy (`tank_active`) ma już dedykowaną, zoptymalizowaną
  ścieżkę `transition_shore_tank_direct` (sprite_renderer.asm:1745), która
  przy scrollu robi **jeden** `fill_uniform_sprite_rect` + jeden
  `draw_current_shore_tank_direct`. Tani.

### Rekomendacja 1a (trywialna, duża zmiana odczuć)

Wyrzucić `bullet_active` i `tank_shell_active` z `resolve_fast_speed`:

```asm
    ; te typy mają tani transition path i mieszczą się w budżecie 2 px
    ; ld a,(bullet_active)
    ; or a
    ; jr nz,resolve_heavy_fast_speed
    ; ld a,(tank_shell_active)
    ; or a
    ; jr nz,resolve_heavy_fast_speed
```

Zmiana usuwa **cały** odczuwalny lag przy strzale czołgu o ile reszta sceny
nie jest równocześnie ciężka (`bridge_active` / `destroyed_road_active` /
`bridge_tank_active` / `enemy_plane_active` wciąż kapują). Pozwala też graczowi
strzelać w trybie Q bez spowolnienia.

### Rekomendacja 1b (bezpieczniejsza)

Zostawić warunek, ale dotyczyć tylko przejścia `tank_shell_active: 1 → 2`
(shell staje się splashem, height rośnie z 2 do 6, wymaga pełnego
`cleanup_resident_sprite_delta` + przepisania 6 wierszy). Wtedy zwykły lot
pocisku (1 → 1) nie kapałby prędkości. Wymaga dodania flagi
`shell_just_landed` ustawianej w `land_tank_shell` (entities.asm:1125) i
zerowanej po jednej ramce.

### Weryfikacja

`make profile` + ZEsarUX z `PROFILE_BORDER=1`. Bez zmiany powinno pokazać
pełną ramkę w trakcie lotu shell-a (nie przekracza budżetu). Jeśli test
wykaże, że przy `speed_pixels=2` + shell ramka faktycznie przekracza 69 888 T,
wrócić do 1a bez `tank_shell` ale z `bullet` (lub odwrotnie).

---

## 2. Hot path: `transition_shell_direct` przez generyczny silnik 🟠

`src/sprite_renderer.asm:1890-1919`:

```asm
transition_shell_direct:
    ld a,(sprite_old_shell_active)
    ld b,a
    ld a,(tank_shell_active)
    or b
    ret z
    call prepare_old_shell_geometry
    ...
transition_shell_same_kind:
    call prepare_new_shell_geometry
    call cleanup_resident_sprite_delta   ; <-- generyk dla height=2
    jp draw_current_shell_direct
```

Dla porównania `transition_ship0_direct` (sprite_renderer.asm:1237) przy
zwykłym scrollu robi:

```asm
    ld b,a               ; speed_pixels
    ld a,(timex_bitmap_ship0_x)
    ld c,a
    and 7
    ld d,4
    jr z,...
    inc d
    ...
    ld a,(timex_bitmap_ship0_y)
    ld e,0
    call fill_uniform_sprite_rect   ; JEDEN caller, JEDEN SP-swap
    jp draw_current_ship0_direct
```

Statki mają **własną** ścieżkę scroll-only: jeden fill paska odkrytych wierszy
+ jeden draw. Shell tepa do `cleanup_resident_sprite_delta` (linia 475), który
dla height=2 z ΔY∈{0,1,2} wybiera jedną z gałęzi, ale i tak finalnie woła
`fill_water_rect_preserve_bridge` (linia 619) — a ten **woła
`fill_uniform_sprite_rect` osobno dla każdego wiersza**:

```asm
fill_water_transition_row:
    ; ... check bridge_active ...
fill_water_transition_write:
    ld a,(transition_fill_col)
    ld c,a
    ld a,(transition_fill_width)
    ld d,a
    ld a,(transition_fill_y)
    ld b,1              ; <-- height=1 per call!
    ld e,0
    call fill_uniform_sprite_rect   ; di / ld sp / pop / ... / ei  ← za każdy wierszem
fill_water_transition_next:
    ...
```

Koszt `fill_uniform_sprite_rect` dla height=1, width=1 to ok. **95 T narządu**
(di, ld (sprite_saved_sp),sp; ld sp,hl; pop hl; ...; ld sp,(sprite_saved_sp);
ei; ret) + ok. 30 T użytecznej pracy. Dla shell-a (height=2) to ok. **2×95 T
narządu = 190 T zmarnowanych**. Dla bullet-a (height=4) ok. **380 T**. Co
ramkę, gdy pocisk żyje.

### Rekomendacja 2 — specjalizacja `transition_shell_direct`

Steady-state pocisku (shell→shell, oba height=2, ΔX=±4, ΔY=speed_pixels∈{1,2})
ma bardzo ograniczony zestaw przypadków. Proponowane ciało:

```asm
transition_shell_direct:
    ld a,(sprite_old_shell_active)
    ld b,a
    ld a,(tank_shell_active)
    or b
    ret z
    cp b
    jr nz,transition_shell_generic    ; różne fazy → stary silnik

    ; --- steady state: both active=1, height=2 ---
    ; 1) wymazać stary prostokąt (2 wiersze × 1-2 bajty), bez bridge checka
    ;    (pocisk czołgu zawsze nad wodą)
    ld a,(sprite_old_shell_y)
    ld b,2                            ; height
    ld a,(sprite_old_shell_x)
    call prepare_transition_old_projectile_x
    ; ... inkrementalny erase bez fill_water_transition_row ...

    ; 2) narysować nowy
    jp draw_current_shell_direct

transition_shell_generic:
    ; stara implementacja: splash landings, deactivation, etc.
    call prepare_old_shell_geometry
    ...
```

Kluczowe pomysły:

- **Pominąć `fill_water_rect_preserve_bridge`** — pocisk czołgu zawsze leci nad
  wodą (cel jest w poprzedwie wybranym, bezpiecznym paśmie wody).
  `tank_attributes_overlap_road` i `object_overlaps_bridge` w `fill_water_*`
  są tu martwym narzutem.
- **Jeden `fill_uniform_sprite_rect` na cały stary pasek** (height=2, 1 wywołanie
  zamiast 2 wywołań height=1). Oszczędność: ~95 T/ramkę gdy shell aktywny.
- **Ewentualnie całkowicie zinline'ować erase** dla width=1 (common case):
  2× `calc_screen_line_addr` (lub inkrement jak w §3) + 2× `ld (hl),0`.

Analogiczna specjalizacja dla `transition_bullet_direct` — patrz §4.

---

## 3. `write_water_projectile_2xn` — `calc_screen_line_addr` co wiersz 🟡

`src/sprite_renderer.asm:2766-2812`:

```asm
write_water_projectile_row:
    ld a,(world_write_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr        ; <-- co wiersz
    ld a,(world_write_col)
    add a,l
    ld l,a
    ld a,(world_write_byte_0)
    ld (hl),a
    ld a,(world_write_byte_1)
    or a
    jr z,write_water_projectile_skip_spill
    inc l
    ld (hl),a
write_water_projectile_skip_spill:
    ld a,(world_write_y)
    inc a
    ld (world_write_y),a
    ld a,(world_write_rows)
    dec a
    ld (world_write_rows),a
    jr nz,write_water_projectile_row
```

`calc_screen_line_addr` (course_renderer.asm:1203) kosztuje ok. 60 T na wywołanie
(2× `add a,a` + 2× odczyt tablicy + `ex de,hl`). Dla bullet-a (4 wiersze) =
~240 T, dla shell-a (2 wiersze) = ~120 T — **tylko po to, by dostać adres
wiersza Y+1, który różni się od Y o stałą deltę**:

- Wewnątrz trzeciej części obrazu (Y%64 ∈ {0..55}): **adres += 32 bajty**.
- Przy przekroczeniu granicy (Y%64 == 56): **adres += 32 - 1792 + 256 = -1536**,
  co w praktyce oznacza `H += 8; L -= 0xe0`.

`render_dirty_rows` (course_renderer.asm:733-778) już to robi ręcznie:

```asm
    ld a,e
    add a,32
    ld e,a
    jr nc,dirty_screen_row_ready
    ld a,d
    add a,8
    ld d,a
dirty_screen_row_ready:
```

`fill_uniform_sprite_rect` (sprite_renderer.asm:2086-2107) robi to jeszcze
lepiej przez SP-as-row-pointer. `write_water_projectile_2xn` jest jedynym
writerem, który tego nie wykorzystuje.

### Rekomendacja 3

Dla małych wysokości (2-4) zinline'ować krok Y bez `calc_screen_line_addr`.
Początkowy adres policzyć raz, potem:

```asm
write_water_projectile_2xn:
    ; ... raz: call calc_screen_line_addr -> HL ...
    ld (proj_screen_addr),hl
    ; ... pętla po wierszach: inkrement HL o +32 / +8 crossing ...
```

Oszczędność ok. **40-50 T/wiersz** → do ~200 T/ramkę przy aktywnym bullet+shell.

---

## 4. `transition_bullet_direct` — przewidywalny przypadek nie-Overlap 🟡

`src/entities.asm:1593` przesuwa bullet o `sub 6`, a bullet ma height=4
(sprite_renderer.asm:1230, 851). Zatem `ΔY=6 > height=4` zawsze, co oznacza że
**ścieżka `cleanup_resident_sprite_delta` zawsze wybiera
`fill_transition_old_rect`** (sprite_renderer.asm:583). Mimo to przechodzi
przez pełną maszynerię:

- liczenie `ΔY` (sprite_renderer.asm:487-494)
- porównanie z `transition_height` (496-499)
- skok do `fill_transition_old_rect` (566-593)
- `dispatch_transition_fill` (595-617)
- `fill_water_rect_preserve_bridge` (619-670) z per-row `fill_uniform_sprite_rect`

Kiedy bullet żyje (do ~25 ramek na strzał), płaci się ten łańcuch co ramkę.

### Rekomendacja 4

W `transition_bullet_direct` (sprite_renderer.asm:1201) rozważyćkrótką
specjalizację:

```asm
transition_bullet_direct:
    ld a,(sprite_old_bullet_active)
    ld b,a
    ld a,(bullet_active)
    or b
    ret z

    ; przypadek A: bullet właśnie zniknął -> erase old 4 rows (już prawie OK)
    ; przypadek B: bullet live -> erase old 4 rows + draw new 4 rows
    ; (oba przypadki wymagają pełnego erase old, bo ΔY > height zawsze)

    ; Specjalizacja pomija cleanup_resident_sprite_delta + fill_water_transition
    ; i robi bezpośrednio 4 jednobajtowe zapisy = 0 w stare Y,
    ; potem draw_current_bullet_direct (już zoptymalizowane).
```

Bullet zawsze nad wodą (gracz musi być nad wodą, by strzelać), więc
`fill_water_rect_preserve_bridge` to overkill — wystarczy 4× `ld (hl),0` po
starym paśmie. Oszczędność ok. **300 T/ramkę** gdy bullet active.

---

## 5. Czyszczenie pocisków — poprawność ✅ (plus jedno zastrzeżenie)

Logika maszyn stanów pocisków jest poprawna. Auditorium:

| Akcja | `bullet_active` / `tank_shell_active` | Snapshot `sprite_old_*_active` | `transition_*_direct` efekt |
|---|---|---|---|
| Trafienie / koniec życia | 1 → 0 ((entities.asm:1783, 1807, …)) | 1 (zapisany w `restore_frame_entities`) | `transition_new_active=0` → `fill_transition_old_rect` wymazuje stary prostokąt |
| Shell ląduje (1 → 2) | 1 → 2 (entities.asm:1132) | 1 | `cp b` nie-zero → `xor a; ld (transition_new_active),a; cleanup; draw splash` |
| Splash kończy (2 → 0) | 2 → 0 (entities.asm:1150) | 2 | jak wyżej, wymazuje prostokąt splash (height=6) |
| Crash (entities.asm:1247-1250) | oba = 0 natychmiast | zależy | `restore_frame_entities` działa na starym stanie z przed-crash |

`begin_crash` (main.asm:1236-1259) poprawnie zeruje `bullet_active`,
`tank_shell_active`, `fire_pending`, `hit_explosion_active` — więc po crashu
nie zostają śmieci na ekranie.

### Zastrzeżenie wizualne (nie wydajnościowe)

`fill_water_rect_preserve_bridge` pisze literał `0` (woda) także tam, gdzie
w bitmapie rezyduje statek, helikopter czy fuel (rezydentne sprite'y).
Porządek w `transition_all_resident_sprites` (sprite_renderer.asm:1921-1935):

```
player → bullet → shell → ship0 → ship1 → balloon → fuel →
enemy_plane → helicopter → shore_tank → bridge_tank
```

Kiedy shell leci poziomo nad rzeką i mija np. statycznego ship0, zdarza się:

1. `transition_shell_direct` wymazuje stare piksele shell — i **przy okazji**
   pisze `0` nad rezydentnym statkiem (bo oba są nad wodą, w tym samym paśmie).
2. `transition_ship0_direct` woła tylko `fill_uniform_sprite_rect` dla
   **odkrytego paska górnego** (1-2 wiersze). Reszta statku nie jest przerysowana.
3. Efekt: 1-klatkowa dziura w statku tam, gdzie shell wymazał.

To **nie jest wada czyszczenia pocisków** — to konsekwencja kolejności:
shell jest czyszczony *zanim* statek dorysuje się na nowo. Naprawa: albo
shell powinien używać maski XOR (jak eksplozje), albo `transition_ship*` po
zmianie ΔX≠0 powinien wymuszać pełen redraw jak w `transition_player_changed`.

W praktyce: shell jest 2 piksele szeroki, statek to 32 piksele — wizualnie
jest to absolutnie marginalne i rzadkie. Nie polecam naprawiać, chyba że
wymaga tego graż.

---

## 6. Przycięcie obszaru gry (PLAYFIELD_BOTTOM) 🟡

`tools/build.py:763`: `PLAYFIELD_BOTTOM = 168`. Kontrakt ekranu
(main.asm:14-21):

```
Y=0..15     czarny margines górny (2 wiersze attr)
Y=16..167   playfield (152 linie = 19 bloków × 8)
Y=168..175  separator
Y=176..183  HUD (LIVES/FUEL/SCORE)
Y=184..191  stopka
```

`render_dirty_rows` iteruje **19 wierszy na klasę residiwu** (course_renderer.asm:731).
Przy `speed_pixels=1` renderuje 19 wierszy (~9 700 T), przy `speed_pixels=2`
— 38 wierszy (~19 400 T).

### Opcja A — zmniejszenie o 1 blok (PLAYFIELD_BOTTOM = 160)

- Playfield: Y=16..159 (144 linie = 18 bloków).
- render_dirty_rows: 18 zamiast 19 wierszy/klasa → **~510 T mniej** przy
  `speed=1`, **~1 020 T** przy `speed=2`.
- HUD + separator przesuwają się o 8 linijek w górę (kosmetyka, layout
  `update_hud_if_dirty` i `clear_hud_row` korzystają z `PLAYFIELD_BOTTOM`
  pośrednio przez `cp 192` — trzeba by zmienić na 184).
- Wpływ na gameplay: minimalny (gra i tak widzi tylko fragment rzeki).
- **Polecam**, jeśli celem jest odzyskanie stałego budżetu.

### Opcja B — zmniejszenie o 2 bloki (PLAYFIELD_BOTTOM = 152)

- 17 wierszy/klasa → **~1 020 T** przy `speed=1`, **~2 040 T** przy `speed=2`.
- Playfield dalej wystarczający (136 linii), ale ekran zaczyna wyglądać
  „przytłoczony" interfejsem.

### Opcja C — przycięcie z góry (START = 24 zamiast 16)

Bez sensu — wszystkie aktualne czeków (`cp 16`, `cp PLAYFIELD_BOTTOM`,
`add a,16` w `dirty_first_y`) są rozsiane po codebase, a zysk jest taki sam
jak opcja A. Lepiej ciąć z dołu.

### Wniosek

Przycięcie **nie naprawi** lagu przy strzale czołgu (to variable cost + speed
cap). Daje za to **stałą** oszczędność, która pozwala zostawić `speed=2` w
więcej scenariuszach. Jeśli zależy Ci na „wyduszeniu cykli", zrób opcję A:
jednolinijkowa zmiana w `tools/build.py`, modyfikacja kilku `cp 192` / `cp 184`
w main.asm i po sprawie.

---

## 7. Inne obserwacje (niski priorytet)

### 7a. `snapshot_resident_sprite_state` (sprite_renderer.asm:137-216)

Zapisuje ~40 bajtów RAM co ramkę, niewarunkowo (`sprite_old_player_x`,
`sprite_old_player_y`, `timex_bitmap_ship0_*`, …). Nawet przy nieaktywnych
aktorach. Koszt ~1 050 T (zostało to już policzone w `review-render-loop.md`).

**Możliwa oszczędność:** dzielić na bloki i wykonywać tylko gdy dany aktor
był w poprzedniej ramce aktywny. Trudność: średnia (trzeba by znać stary
stan w momencie snapshota). Realny zysk ~500 T w lekkich scenach.

### 7b. Kolejność w `update_entities` (entities.asm:5-29)

```asm
    call update_player
    call update_hit_explosion
    call advance_ship0
    ...
    call update_tank
    call update_bridge_tank
    call update_tank_shell
    ; ...
    call update_bridge
    call reset_world_background_cache
    call update_bullet
    call keep_water_objects_off_bridge
    call transition_all_resident_sprites
    jp check_player_collision
```

`update_tank_shell` jest wołany **przed** `update_bridge`. Komentarz mówiący o
kolejności jest w `keep_water_objects_off_bridge` (entities.asm:2150+), ale sam
shell nie jest tam sprawdzany. Wygląda spójnie, choć `update_bullet` po
`update_bridge` oznacza, że pocisk gracza sprawdza kolizję z mostem już po
jego aktualizacji — poprawne.

Brak politics; nic do zmiany.

### 7c. `transition_all_resident_sprites` (sprite_renderer.asm:1921)

12 niewarunkowych `call`. Każdy z nich na początku robi load+test+ret, ale to
łączny narzut ~12 × (10 T ld + 5 T or + 5 T ret z) ≈ 240 T czystego narzędu
dla nieaktywnych typów. Drobny, ale stały. Rozwiązanie: bit-maska „co się
zmieniło w tej ramce" ustawiana w `update_entities` i sprawdzana raz. Trudność
większa niż zysk — **nie polecam**.

### 7d. Drobne: `transition_shell_direct` liczy `transition_height` dwa razy

`prepare_old_shell_geometry` i `prepare_new_shell_geometry` obydwie piszą
`transition_height`. W steady-state (same kind) drugi zapis jest zbędny
(overwrite tą samą wartością). Koszul, ~7 T. Ignorować.

---

## 8. Sugerowana kolejność wdrożeń

1. **(§1a)** Usunąć `bullet_active` i/lub `tank_shell_active` z
   `resolve_fast_speed`. Testować `make profile`, czy ramka mieści się
   w 50 Hz przy `speed=2` + pociski. **Największy odczuwalny zysk**,
   najmniejszy wysiłek.
2. **(§5)** Przyciąć `PLAYFIELD_BOTTOM` z 168 → 160. Stała oszczędność ~500 T.
3. **(§3)** Zinline'ować krok Y w `write_water_projectile_2xn`. ~200 T gdy
   pociski aktywne.
4. **(§2)** Dedykowana ścieżka `transition_shell_direct` dla steady-state.
   ~150 T gdy shell aktywny.
5. **(§4)** Dedykowana ścieżka `transition_bullet_direct` (zawsze non-overlap).
   ~300 T gdy bullet aktywny.

Po krokach 1-5 gracz nie powinien już odczuwać *żadnego* zwolnienia przy
strzale czołgu, a ramka zyska zapas pozwalający na dłuższą ekspozycję
ciężkich scen (most + helikopter + bridge_tank jednocześnie) bez kapa.

---

## 9. Pominięte celowo

- `render_dirty_rows` / delty terenu — obszerne w `review-render-loop.md`
  i `review-claude-linia-0brzegowa.md`.
- Atrybuty Timex 8×1 — obszerne w `review-render-loop.md` §1.
- AY sound, klawiatura, profilowanie border — poza zakresem tego zgłoszenia.
