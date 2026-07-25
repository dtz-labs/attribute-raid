# Dlaczego cała gra przywleka przy Q + most + czołg + atrakcje

Scenariusz użytkownika: **tryb szybki (Q)**, w pobliżu mostu, czołg brzegowy
strzela, + śmigłowiec/samolot/statki/FUEL/balon. Diagnoza poniżej.

Liczby T-stanów są **statyczne** (zliczone z listingu, bez pomiarów emulatora,
bez kontencji ULA). Budżet ramki 48K: **69 888 T**.

---

## TL;DR — trzy niezależne zjawiska, nie jedno

| # | Zjawisko | Charakter | Wniosek |
|---|---|---|---|
| **A** | **`resolve_fast_speed` kapuje `speed_pixels=1`**, gdy cokolwiek z listy „ciężkich" aktorów jest aktywne. Gracz trzyma Q → oczekuje 1.5 px/ramkę, dostaje 1 px/ramkę. Rzeka wizualnie zwalnia o 33 %. | **Percepcja, nie stutter** | Dominujące odczucie, **nie jest prawdziwym spadkiem ramek** |
| **B** | **Jednoklatkowe hiccough-y**: most się pojawia (16 wierszy bitmapy + atrybuty w jednej ramce) albo most zostaje zniszczony (16× pełna rekonstrukcja świata). | **Prawdziwy stutter (1-2 ramki)** | Rzadkie, ale pokrywa się z momentem, w którym gracz jest „przy moście" |
| **C** | **Koszt steady-state rośnie**: most dodaje +~1 500 T/ramkę, każdy aktor +~500-800 T, a na Timex atrybuty mostu 8×1 to +~3 600 T/ramkę. | **Mniejszy headroom na B i ISR** | Sprawia, że hiccough z B faktycznie przekracza budżet |

Często A + B + C występują jednocześnie, gdy gracz dociera do mostu, bo wtedy:
pojawia się most (B), aktywowany jest tryb cap (A), a stan steady-state z mostem
już trzyma (C). Stąd wrażenie „cała gra przywleka".

---

## A. Speed cap — dominująca przyczyna (percepcja, nie stutter) 🔴

`src/input.asm:75-95` (`resolve_fast_speed`):

```asm
    ld a,(bridge_active)         ; <-- most aktywny
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(destroyed_road_active) ; <-- zniszczona droga aktywna
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(tank_active)           ; <-- czołg brzegowy
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(bridge_tank_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(enemy_plane_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(bullet_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(tank_shell_active)     ; <-- pocisk czołgu w locie
    or a
    jr nz,resolve_heavy_fast_speed
    ; ... tryb 1.5 px/frame (fast_phase 0/1 ↔ 1/2 px)
```

Scenariusz użytkownika uderza w **5 z 7** warunków naraz:
`bridge_active=1` ∨ `destroyed_road_active=1` ∨ `tank_active=1` ∨
`bullet_active=1` ∨ `tank_shell_active=1`. Każdy z nich sam wystarczy.

Efekt: `speed_pixels=1` co ramkę. River widocznie zwalnia z ~1.5 px/ramkę
(tryb fast, średnia) na 1.0 px/ramkę — to **33% redukcji prędkości**.
Dla gracza to wygląda jak lag, ale technicznie **ramek nie brakuje**.

### Dlaczego to jest tak agresywne

Lista jest restrykcyjna, bo kiedyś powodowała prawdziwe przekroczenia budżetu.
Dzisiejszy renderer jest jednak znacznie wydajniejszy (delta terenu,
resident sprites zamiast XOR, dedykowane transition-paths dla statków).
Większość warunków na liście to już **anachronizm** — szczególnie:

- `bullet_active`: bullet to 4 wiersze × 2 piksele. Narzut < 400 T/ramkę.
- `tank_shell_active`: shell to 2 wiersze × 2 piksele. Narzut < 500 T/ramkę
  (patrz `glm-review-1.md` §2 — nawet przez generyczny silnik).
- `tank_active`: czołg ma już dedykowaną, zoptymalizowaną ścieżkę
  `transition_shore_tank_direct` (sprite_renderer.asm:1745).

**Tylko `bridge_active` / `destroyed_road_active` / `bridge_tank_active` mają
realne uzasadnienie** na liście — bo most dodaje verdikt bitmap + atrybutów
co ramkę (patrz §C poniżej).

### Rekomendacja A1 (największy zysk, minimalny wysiłek)

Wyrzucić z listy `bullet_active`, `tank_shell_active` i `tank_active`.
Zostawić mosty i bridge_tank. Po zmianie:

- Gracz trzyma Q przy strzale czołgu → **bez zwolnienia** (pocisk leci, rzeka
  dalej przewija 1.5 px/ramkę).
- Most wciąż kapuje prędkość — to jest realnie potrzebne.
- Po zniszczeniu mostu (`destroyed_road_active`) też kapuje — nadal potrzebne.

Jeśli po zmianie `make profile` pokaże przekroczenie budżetu przy Q + bullet +
shell + brak mostu, wtedy cofnąć jeden z warunków (najpewniej `tank_shell`,
który maSplash przechodzący przez generyczny silnik).

### Rekomendacja A2 (bezpieczniejsza wariant)

Zostawić listę, ale dodawać do niej tylko **faktycznie ciężkie kombinacje**:
np. most + czołg brzegowy naraz (bridge + shore_tank jest rzadkie i wtedy
faktycznie birga o budżet). Wymaga zastąpienia 7 niezależnych testów
pojedynczym sprawdaniem kombinacji. Więcej roboty, mniejszy zysk niż A1.

---

## B. Jednoklatkowe hiccough-y wokół mostu 🔴

Są **dwa** konkretne momenty, w których jedna ramka robi 5-20× więcej pracy
niż zwykle. Obie mają miejsce dokładnie w okolicy mostu.

### B.1 Pojawienie się mostu — `update_bridge` ścieżka `bridge_spawn_pending`

`src/entities.asm:1175-1202`:

```asm
update_bridge:
    call update_destroyed_road
    ld a,(bridge_spawn_pending)
    or a
    jr z,advance_active_bridge
    ; ...
    ld b,16
    ld c,255
    xor a
    call bridge_fill_rows                    ; 16 wierszy × bridge_width bajtów = 0xff
    call bridge_paint_road_attributes        ; atrybuty całego mostu
    call bridge_draw_initial_road_markings   ; 2 środkowe wiersze znaczników
    ret
```

`bridge_fill_rows` (sprite_renderer.asm:2947) maluje 16 wierszy bitmapy.
Przy `bridge_width` rzędu 6-10 bajtów:

- 16 × (~155 T/wiersz dla width=6) ≈ **2 500 T**

`bridge_paint_road_attributes`:

- Standard (main.asm:3140, `bridge_paint_road_attribute_row` × ~2-3 attr rows):
  ~**1 500 T**.
- Timex (sprite_renderer.asm:3281, `timex_bridge_paint_span_row` × 16 skanline):
  16 × ~224 T ≈ **3 600 T**.

**Łącznie pojedyncza ramka spawn-u mostu**: ~4 000 T (standard) /
~6 100 T (Timex) **nad** normalny koszt ramki. Zwykle mieści się w budżecie,
ale jeśli akurat w tej samej ramce wiele aktorów jest aktywnych (C), to
przekroczenie jest realne.

### B.2 Zniszczenie mostu — `destroy_bridge` jest **najdroższą jedną ramką w grze** 🔴

`src/entities.asm:2028-2066`:

```asm
destroy_bridge:
    ; ... add_score, hit_explosion, attrs ...
    ld a,(bridge_y)
    ld (bridge_restore_y),a
    ld a,16
    ld (bridge_restore_rows),a
destroy_bridge_restore:
    ld a,(bridge_restore_rows)
    or a
    jr z,destroy_bridge_done
    ld a,(bridge_restore_y)
    cp PLAYFIELD_BOTTOM
    jr nc,destroy_bridge_done
    ld c,0
    call bridge_fill_full_bitmap_row          ; 32 bajty -> 0
    ld a,(bridge_restore_y)
    call render_full_world_row                ; <-- pełna rekonstrukcja świata!
    ld a,(bridge_restore_y)
    inc a
    ld (bridge_restore_y),a
    ld a,(bridge_restore_rows)
    dec a
    ld (bridge_restore_rows),a
    jr destroy_bridge_restore
```

16 iteracji po:
- `bridge_fill_full_bitmap_row` (sprite_renderer.asm:1526): 32 bajty inline,
  ~**280 T**.
- `render_full_world_row` (course_renderer.asm:596): lewy + prawy bank +
  wyspa, pisze wszystkie 32 bajty. ~**1 000-1 200 T**.

Łącznie samo `destroy_bridge_restore`: **16 × ~1 500 T ≈ 24 000 T w jednej ramce**.
Plus eksplozja, AY, atrybuty, aktualizacja score, `preserve_road_tank_after_bridge`,
`bridge_draw_destroyed_road_markings`. **Całkowity koszt `destroy_bridge`:
~28 000 T**, czyli ~40 % budżetu ramki na jedną akcję.

Jeśli w tej samej ramce gracz ma też śmigłowiec, samolot, statki — transition_*
dla nich też się odpala (kolejne ~5 000 T) → łączna ramka może dobić do
**~50 000 T standard / ~62 000 T Timex**. To **się mieści**, ale jest blisko
granicy. Każde dodatkowe obciążenie (np. wybudowanie dirty rows tej ramki
dla sąsiadujących bloków kursu o nieregularnym kształcie) może przekroczyć.

**Efekt**: gdy gracz strzeli w most, przez jedną ramkę gra tnie. Widać jako
jednorazowy jitter (~1 frame drop), często tuż po nim następuje
`destroyed_road_active` i cap na `speed=1` utrzymuje się przez kolejne
~80 ramek (aż droga nie zejdzie poza ekran).

### B.3 Bridge tank spawn (rzadsze, ale)

`activate_waiting_bridge_tank` (entities.asm:806): ustawia tryb 3→1 i
pozycjonuje czołg. Tani. Ale w tej samej ramce `transition_bridge_tank_direct`
(sprite_renderer.asm:1805) po raz pierwszy wykonuje full redraw
(bo `sprite_old_bridge_tank_active` było 0) → `cleanup_resident_sprite_delta`
robi full rect erase + `draw_current_bridge_tank_direct`. ~1 500 T
jednorazowo. Drobne.

### B.4 Most się kończy (scrolluje poza ekran)

`advance_active_bridge` (entities.asm:1262): gdy `bridge_y + speed >=
PLAYFIELD_BOTTOM`, czyści ostatnie atrybuty (`bridge_clear_road_attributes`)
i dezaktywuje most. ~1 500 T na standard, ~3 000 T Timex. Drobne.

### Rekomendacja B1 — rozbić `destroy_bridge_restore` na 2 ramki

Najprostsza redukcja B.2: nie rekonstruować 16 wierszy w jednej ramce, ale
8 w jednej (ramka n) i 8 w kolejnej (ramka n+1). Wizualnie: pierwsza ramka
pokazuje połowę zniszczonego mostu, druga resztę. ~1/60 s różnicy — dla
oka niewidoczne w ruchu, a ramka n rozładowana o ~12 000 T.

Implementacja: zostawić `bridge_restore_y` i `bridge_restore_rows` jako
**stan między ramkami** (już są w `state.asm:123-124`), dodać flagę
`bridge_destroying: db 0`. W `update_bridge` sprawdzać flagę i dokończyć
połowę pracy.

### Rekomendacja B2 — `bridge_fill_full_bitmap_row` jest tylko `ld (hl),0 × 32`

Funkcja (sprite_renderer.asm:1526) jest naiwnym 32-zapisem zamiast użycia
`fill_uniform_sprite_rect` z value=0 i height=1. Ten drugi używa
SP-as-row-pointer (sprite_renderer.asm:2086-2107) i jest szybszy o ~30 %.
Jednak — `bridge_fill_full_bitmap_row` jest wołany tylko z `destroy_bridge`
(16 razy) i `full_redraw` (152 razy raz przy starcie), więc zysk ~1 000 T
w `destroy_bridge`. Drobny, ale darmowy.

### Rekomendacja B3 — `render_full_world_row` w `destroy_bridge` jest nadmiarowy

Komentarz przy `destroy_bridge` (linia 2053-2055) mówi:
> render_v3_row normally assumes that all bank interiors are already set.
> Road dashes violate that invariant, so clear the complete scanline and
> use the deliberately slower full-row world reconstruction here.

Ale `render_v3_row` (course_renderer.asm:790) pisze **complete edge bytes**
(left_mask, right_mask) + całą wyspę. Jedyną rzeczą której nie robi to
czyszczenie bajtów uważanych za „interior", które `road dashes` mogły
przemalować. Jeśli `render_v3_row` dostałby dodatkowy tryb „najpierw wyzeruj
cały wiersz, potem renderuj", to `destroy_bridge` mógłby użyć szybszej
ścieżki delta-z. Drobny zysk, ale złożony.

---

## C. Steady-state koszt „z mostem" — Compiled budżet 🟠

Tabela: budżet ramki w **worst-case scenie** opisanej przez użytkownika,
przy **`speed_pixels=1`** (bo cap i tak włączy się z mostem):

| Pozycja | Standard | Timex |
|---|---:|---:|
| `render_dirty_rows` (19 wierszy × ~590 T) | ~11 200 | ~11 200 |
| **most — `advance_active_bridge` (steady state)**: 1× `render_v3_row` + 1× `bridge_fill_rows` + `bridge_refresh_edges` (2 wiersze) + `bridge_draw_entering_road_markings` + `bridge_update_attributes` | **~1 500** | **~1 500** |
| **most — atrybuty 8×1 (Timex)** | — | **~3 600** |
| bitmapy sprite'ów — `transition_all_resident_sprites` (gracz, ship0, ship1, heli, plane, fuel, balloon, shore_tank, bridge_tank, bullet, shell) | ~7 000 | ~7 000 |
| `snapshot_resident_sprite_state` | ~1 050 | ~1 050 |
| atrybuty obiektów (4× `STANDARD_ATTR_CHANGED` / Timex `cleanup_timex_*`) | ~500 | ~3 000 |
| logika encji + kolizje (`update_entities` + `check_player_collision`) | ~2 500 | ~2 500 |
| `keep_water_objects_off_bridge` (6× overlap test) | ~300 | ~300 |
| `generate_block` (amortyzowany co 8 ramek) | ~150 | ~150 |
| AY + klawiatura + `profile_*` | ~800 | ~800 |
| ROM ISR (IM1, `KEY-SCAN`) | ~1 500-2 000 | ~1 500-2 000 |
| **Razem steady-state** | **~26 500** | **~33 100** |
| **Budżet ramki** | 69 888 | 69 888 |
| **Headroom na ISR + hiccough** | ~43 000 | ~37 000 |

Steady-state jest w porządku — mieści się z dużym zapasem. **Problem nie jest
tutaj**, tylko w B (jednoklatkowe hiccough) i A (percepcja cap-u).

### Co więcej, `render_dirty_rows` jest najmniej zależne od aktorów

`render_dirty_rows` (course_renderer.asm:711) iteruje **19 wierszy na klasę
residiwu** niezależnie od tego, ile aktorów jest aktywnych. To **najdroższa
pojedyncza pozycja budżetu** (~16 % ramki standard, ~16 % Timex), ale jest
stała. Nie zależy od mostu, śmigłowca, ani niczego.

→ **Opcje przyspieszenia render_dirty_rows są w `review-render-loop.md`
i `review-claude-linia-0brzegowa.md` — tam jest pełna analiza.**

### Subtelność: most dodaje drugi przebieg renderer'a

W `advance_active_bridge` (entities.asm:1246) wołane jest `render_v3_row` dla
odchodzącego wiersza mostu. Ten sam wiersz **był już odwiedzony** przez
`render_dirty_rows` (jeśli jego residiu pasuje do `course_phase`). Efekt:

- dirty_rows pisze delta kursu (kilka bajtów)
- bridge's render_v3_row pisze pełne edge bytes + wyspa (~5 bajtów)

Dla pojedynczego wiersza to ~700 T dodatkowo. Przy `speed_pixels=1`: 1 wiersz.
Przy `speed_pixels=2`: 2 wiersze. **Drobne nakładanie**.

To jest **konieczne** — bez tego bank może mieć pixel z mostu
(0xff zamiast prawidłowego edge mask). Nie da się usunąć.

### Subtelność: `transition_bridge_tank_direct` jest droższy niż zwykły aktor

Bridge tank używa `write_intact_bridge_tank_shifted_2xn` (sprite_renderer.asm:2639),
który musi obsłużyć **dwa specjalne wiersze** (4 i 5) z przerywaną linią środkową
drogi. Każdy wiersz:

- zwykły: load + xor 255 + 2-3 zapisy = ~80 T
- przerywany: dodatkowy test parzystości kolumny + gałęzie = ~140 T

10 wierszy × średnio ~100 T = ~1 000 T. Drobny, ale stały koszt obecności
bridge_tank na mostku.

---

## D. Kolejność zdarzeń w ramce — co gracz widzi a co nie

`main.asm:90-127`:

```asm
main_frame_active:
    call restore_frame_entities       ; snapshot starego stanu
    ; speed_pixels już ustawiony przez read_keyboard wcześniej
    call advance_course_sample       ; aktualizuje course_phase
    call render_dirty_rows           ; <-- 19 wierszy dirty zawsze (lub 38)
    call update_entities             ; <-- TUTAJ most się respawnował / niszczył
    call update_hud_if_dirty
    call draw_frame_entities         ; xor_hit_explosion + atrybuty
    jp main_loop
```

Ważne observacje:

1. **`render_dirty_rows` biegnie zanim `update_entities` zaktualizuje most**.
   Jeśli w tej ramce `bridge_spawn_pending=1`, dirty_rows biegnie po starym
   obrazie (bez mostu), a potem `update_bridge` maluje most od nowa.
   Oznacza to, że **most jest malowany NA STARYM obrazie** — dirty rows
   nie wie o moście. To jest OK, bo most jest bitmap-band和维护any oddzielnie.

2. **`update_entities` jest ciężki tej ramce**, w której most się respawnował
   (~4 000 T over steady). W tej samej ramce `transition_all_resident_sprites`
   biegnie po wszystkim — więc jeśli gracz + śmigłowiec + statki są aktywne,
   transitional bitmap work te~3 000 T się nakłada.

3. **`destroy_bridge` jest wołane z `update_bullet` (bullet-vs-bridge test,
   entities.asm:1658)**. To znaczy, że jeśli gracz zestrzeli most w tej ramce:
   - dirty_rows już się skończył (~11 200 T)
   - update_entities (do destroy_bridge) doszło ~28 000 T
   - transition_all_resident_sprites zaraz bieżnie ~7 000 T
   - **Razem ta ramka: ~46 200 T standard, ~58 000 T Timex**.
   Na Timex jest **blisko granicy**. Na standard — wciąż OK.

### Dlaczego to nie jest realny frame drop (zazwyczaj)

Nawet przy ~46 000 T ramki + ISR ~2 000 T = ~48 000 T, do budżetu brakuje
~22 000 T. To jest ~315 mikrosekund zapasu. **Nie przekracza**.

Więc **gracz prawdopodobnie nigdy nie widzi frame drop w standardowej
rozgrywce na 48K**. To co widzi, to:

- **Percepcja A** — river zwalnia z 1.5 na 1.0 px/ramkę przy moście.
- **Hiccough B** — pojedyncza ramka ~46 000 T bywa blisko, na Timex na
  granicy. Może powodować subtelną niestabilność (1 frame za / 1 frame
  później), ale nie długie lag-i.

---

## E. Rekomendacje uszeregowane według efektywności

| # | Zmiana | Trudność | Zysk |
|---|---|---|---|
| **E1** | Wyrzucić `bullet_active`, `tank_shell_active`, `tank_active` z `resolve_fast_speed` (§A1) | tryvial | **Percepcja lagu przy strzale: zniknie całkowicie przy moście bez mostu; przy moście i tak włączy się warunek `bridge_active`.** Największy zysk psychofizyczny. |
| **E2** | Rozbić `destroy_bridge_restore` na 2 ramki (§B1) | mała | Hiccough zniszczenia mostu: ~12 000 T light. |
| **E3** | `bridge_fill_full_bitmap_row` → użyć `fill_uniform_sprite_rect` (height=1, value=0) (§B2) | tryvial | ~1 000 T w destroy_bridge + ~5 000 T w full_redraw (przy starcie). |
| **E4** | Specjalizacja `transition_shell_direct` / `transition_bullet_direct` — patrz `glm-review-1.md` §§2, 4 | mała | ~450 T gdy shell/bullet aktywne. Pomocnicze wobec E1 (po E1 cap nie włączy się, ale koszt steady-state rośnie). |
| **E5** | Przycięcie `PLAYFIELD_BOTTOM 168 → 160` (`glm-review-1.md` §6) | tryvial | Stałe ~500 T/ramka, więcej headroom na B. |
| **E6** | Rozważyć przyspieszenie `render_dirty_rows` wg `review-render-loop.md` §1 | średnia-trudna | ~2 000-3 000 T/ramka. Największy potencjał ale największa robota. |

### Najmniejszym nakładem najwięcej zyskasz:

**E1 + E3 + E5** to trzy trywialne zmiany (sumarycznie kilkanaście linii),
które:

1. Usuwają **cały** odczuwalny lag przy strzale czołgu **poza** mostem.
2. Skracają hiccough zniszczenia mostu z ~28 000 T do ~26 000 T (E3), a
   rozłożenie na 2 ramki (E2, jeśli zaakceptujesz) daje do ~14 000 T/ramkę.
3. Dają stały zysk ~500 T/ramka z przycięcia (E5).

Po E1 + E5 gra powinna **wizualnie przestać przywlekać** przy Q + strzale +
brak mostu. Przy Q + most + strzale cap nadal włączy się przez
`bridge_active`, ale wtedy faktycznie jest to potrzebne.

---

## F. Testy weryfikujące

1. **`make profile`** z `PROFILE_BORDER=1` + symulacja scenariusza
   (Q wciśnięte, dół rzeki z mostem, śmigłowiec, statki, czołg strzela).
   Zmierzyć długość impulsu border-color. Jeśli ramka stale mieści się w
   69 888 T (granica 1 ramka = ~20 ms PAL), to potwierdza diagnozę:
   **lag jest percepcją, nie frame dropem**.

2. **Test A/B E1**: usunąć warunki z `resolve_fast_speed`, ponownie zmierzyć.
   Jeśli długość impulsu jest stabilna w obu wersjach, E1 jest bezpieczny.

3. **Specyficznie dla mostu**: test scenariusza „gracz trafia most kulą".
   Zmierzyć ramkę zniszczenia — jeśli impuls się przedłuża (border
   rozciąga się poza 1 ramkę), potwierdza hiccough B.2.

`make profile` działa w headless (bez ZEsarUX) — buduje
`build-profile/attribute-raid.tap`. Profilowanie border-a wymaga odpalenia
w emulatorze z widocznym border-em (`make run-profile`).

---

## G. Co **nie** jest winne (a podejrzewane)

- **Renderer delta terenu** — jest już dobrze zoptymalizowany; najdroższy
  stały koszt, ale niezależny od scenariusza użytkownika.
- **Czyszczenie pocisków** (`bullet_active`/`tank_shell_active` state
  machine) — poprawne (patrz `glm-review-1.md` §5), niewielki koszt.
- **AY sound** — tani (~500 T), jednorazowy start dźwięku nie obciąża
  kolejnych ramek.
- **ROM ISR** — stały ~1 500-2 000 T, niezależny od sceny.
- **`keep_water_objects_off_bridge`** — ma wczesny `ret z` na
  `bridge_active`; bez mostu zwraca natychmiast.
- **Atrybuty standard (4× `STANDARD_ATTR_CHANGED`)** — makro jest dobrze
  zraczkowane (dirty-check na 5 poziomach), tani.
