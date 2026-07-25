# Review (Fable) — główna pętla, hot path, czyszczenie pocisków, przycięcie pola gry

Zakres: `main.asm` (pętla główna), `entities.asm` (pociski/kolizje),
`sprite_renderer.asm` (kompozytor rezydentny), `course_renderer.asm`
(dirty-row pass), `input.asm`, `render_timex.asm`. Liczby to statyczne
szacunki T-stanów (nie pomiary) — arbitrem pozostaje `make run-profile-timex`
i pasek bordera. Budżet ramki: ~69 888 T (48K/TC2068 @ 50 Hz), ale uwaga:
**TS2068 to 60 Hz → tylko ~59 000 T na ramkę** — decyzje o limitach trzeba
walidować na najciaśniejszej maszynie.

---

## 1. TL;DR

1. **„Przywlekanie" przy pocisku czołgu to prawie na pewno nie przekroczenie
   budżetu ramki, tylko celowy limiter szybkiego scrolla** w
   `resolve_fast_speed` (`input.asm:70`). Lista „ciężkiej sceny" zawiera
   `tank_active`, `tank_shell_active` i `bullet_active` — a czołg po
   pierwszym strzale strzela **łańcuchowo bez przerwy** (timer stoi na 0,
   dopóki pocisk leci; entities.asm:1000–1008), więc pocisk wisi w powietrzu
   niemal ciągle. Trzymając Q / joystick w górę widzisz spadek z ~1,5 px/ramkę
   do 1 px — to −33% prędkości, odbierane jako lag. Bonus pogarszający
   wrażenie: dźwięk silnika używa `requested_speed` (nie `speed_pixels`),
   więc **silnik dalej brzmi „szybko", choć świat zwolnił** — mózg
   interpretuje to jako ścinanie, nie jako design.
2. **Czyszczenie pocisków jest geometrycznie poprawne** (wszystkie
   przejścia stanów sprawdzone — patrz §3), ale ma jedną realną wadę:
   założenie „cały bajt to woda". Rysowanie i sprzątanie pocisku/splasha
   potrafi **wyciąć piksele brzegu/wyspy w tym samym bajcie** i te nacięcia
   **potrafią zostać na ekranie na długo**, bo delta-replay odświeża tylko
   bajty różniące się między sąsiednimi blokami (na prostych odcinkach —
   nigdy). To może być źródło wrażenia „coś jest nie tak z czyszczeniem".
3. **Przycinanie pola gry od góry/dołu nie ma sensu wydajnościowo**:
   8 linii mniej to ~1 wiersz delta-passu na residue, czyli ~300–900 T
   (<1,5% budżetu). Za to są tańsze, konkretne oszczędności (§4) rzędu
   **5–8k T** w ramkach z pociskami.

---

## 2. Mechanizm postrzeganego spowolnienia

`input.asm:70–114` (`resolve_fast_speed`): tryb szybki (Q / Kempston góra)
daje naprzemiennie 1/2 px (średnio 1,5), **chyba że** aktywne jest cokolwiek
z listy: `bridge_active`, `destroyed_road_active`, `tank_active`,
`bridge_tank_active`, `enemy_plane_active`, `bullet_active`,
`tank_shell_active` → wtedy sztywno 1 px.

Sekwencja zdarzeń, którą widzisz:

- czołg wjeżdża od góry (`tank_active=1`) → limit już działa;
- po 72 ramkach strzela; po wylądowaniu pocisku **następny strzał pada
  natychmiast** (`tank_fire_timer_elapsed`, entities.asm:1000–1008 —
  timer zostaje na 0 podczas lotu pocisku, refire w pierwszej wolnej
  ramce) → `tank_shell_active` jest ustawione niemal bez przerw;
- pocisk jest najbardziej rzucającym się w oczy nowym elementem, więc
  spowolnienie kojarzy się z nim.

Realny koszt tych aktorów na ramkę (statycznie):

| element | koszt/ramkę | uwagi |
|---|---|---|
| czołg brzegowy (transition + draw 10×2 B + atrybuty Timex) | ~1,5–2k T | sprite_renderer.asm:1745, render pass przyrostowy |
| pocisk czołgu w locie (transition + 2 wiersze draw) | ~1–1,5k T | sprite_renderer.asm:1890 |
| pocisk gracza w locie | ~4–5k T | z czego ~3,5–4k to `bullet_hits_background` — patrz §4.1 |

Razem ~7k T ≈ 10% budżetu — **to nie uzasadnia cięcia scrolla o 33%**,
zwłaszcza po optymalizacji z §4.1.

**Rekomendacja:**
1. Zbuduj `make run-profile-timex`, przytrzymaj Q przy czołgu+pocisku i
   zmierz realny pasek bordera (najlepiej też na maszynie TS2068 / 60 Hz).
2. Jeśli zapas się potwierdzi (spodziewam się ~50% wolnego), usuń
   `tank_active`, `tank_shell_active` i `bullet_active` z listy ciężkiej
   sceny. Zostaw `bridge_active`/`destroyed_road_active` (band-restore +
   38-wierszowy pass przy 2 px naprawdę się sumują) i zmierz osobno
   `enemy_plane_active` (kompozycja world-triplet na 8 wierszach).
3. Opcja pośrednia zamiast zrzutu do 1 px: cykl 1,1,2 (średnio 1,33 px) —
   łagodniejszy stopień między 1,5 a 1,0.

---

## 3. Czyszczenie pocisków — werdykt

### 3.1 Logika przejść: poprawna

Prześledziłem `transition_bullet_direct` (sprite_renderer.asm:1201) i
`transition_shell_direct` (:1890) przez wszystkie przejścia stanów:

- pocisk gracza: spawn (old=0→draw), lot (delta > wysokość → pełny
  restore starego prostokąta), śmierć od aktora/tła/topu (old→water,
  nowy nierysowany) — OK; refire w tej samej ramce niemożliwy
  (`bullet_active` sprawdzane przy strzale);
- pocisk czołgu: 1→1 (restore górnych wierszy + kolumny bocznej), 1→2
  (zmiana rodzaju → pełny restore starego, potem splash), 2→2 (scroll),
  2→0 / 1→0 (pełny restore) — OK; refire zawsze w następnej ramce, bo
  `maybe_fire_tank` biegnie przed `update_tank_shell`;
- pas mostu: pocisk gracza ginie zanim jego prostokąt wejdzie w band
  (swept test), pocisk czołgu jest do niego przyklejony światowo
  (oba scrollują o `speed_pixels`), więc `fill_water_rect_preserve_bridge`
  nigdy nie musi ratować sytuacji w praktyce.

Nic nie przecieka, nie zostają „duchy" prostokątów. Tu jest czysto.

### 3.2 Realna wada: założenie „cały bajt = woda"

`write_water_projectile_2xn` (sprite_renderer.asm:2766) **zapisuje bajt
maski wprost**, zerując pozostałe 6 bitów bajtu, a sprzątanie
(`transition_background=0` → `fill_water_rect_preserve_bridge`) wypełnia
stary prostokąt **wodą (0)**. Test kolizji z tłem (entities.asm:1705)
gwarantuje wodę tylko pod **dwoma pikselami maski**, nie pod całym bajtem.

Konsekwencje (wszystkie osiągalne):

- **Pocisk gracza przy brzegu**: gracz może lecieć skrzydłem nad lądem
  (kolizja liczy rdzeń 6×6), pocisk startuje z x+7/x+8 — bajt pocisku
  może zawierać piksele krawędzi banku. Przelot zostawia 4-wierszowe
  nacięcia w linii brzegowej.
- **Splash pocisku czołgu**: cel jest klamrowany do `[d+8, e+8]`
  (entities.asm:1047–1080), a splash rysowany jest 16 px od `tank_shell_x`
  (`draw_current_splash_direct`, sprite_renderer.asm:865, przez
  `write_water_sprite_2xn`, które też zapisuje zera źródła). Przy
  `target = e+8` prawy bajt splasha to **bajt krawędzi prawego banku**
  (kolumna `right_col`), a w lewej odnodze forka — **pierwszy, pełny bajt
  wyspy** (`island_left`). Splash wycina tam dziury, a sprzątanie
  zostawia wodę.
- **Trwałość**: `render_v3_row_delta_prepared` odtwarza wyłącznie bajty
  różniące się między blokiem i jego poprzednikiem. Na prostym odcinku
  (identyczne bloki, delta count 0) uszkodzony bajt **nie zostanie nigdy
  naprawiony**, dopóki zakręt nie zmieni tej kolumny.

**Naprawa (rekomendowana):** potraktować pociski jak sprite'y
mixed-terrain, którymi już umiesz zarządzać:

1. rysowanie: pobrać tło (`load_world_background_triplet` /
   `get_world_background_byte`) i zapisać `tło OR maska` zamiast samej maski;
2. sprzątanie: `transition_background=1` dla bullet/shell/splash →
   `fill_world_background_rect` odtworzy prawdziwe bajty świata zamiast
   zakładać wodę (dla tych obiektów pas mostu jest nieosiągalny, więc
   brak skip-a mostowego nie szkodzi).

Koszt: ~+600 T na ramkę na aktywny pocisk — pomijalny. Alternatywa
minimalna (tylko splash): doklamrować `tank_shell_target_x` o dodatkowe
8 px z obu stron, żeby 16-pikselowy splash nie dotykał bajtów krawędzi —
ale to nie naprawia nacięć od pocisku gracza.

---

## 4. Hot path — gdzie realnie wydusić cykle

Posortowane wg (zysk / ryzyko):

### 4.1 `bullet_hits_background` — z ~3,5–4k T do ~0,5k T

entities.asm:1705–1759: pętla 10 wierszy × 2 wywołania
`get_world_background_byte`, a cache indeksu bloku jest kluczowany
**dokładnym Y** (sprite_renderer.asm:2154), więc każdy wiersz to miss i
pełne `get_block_index_for_y` (~90 T) + `block_bitmap_address`.

Kluczowa obserwacja: `block_bitmap_rows` trzyma **jeden 32-bajtowy wiersz
na blok** (state.asm:326) — wszystkie 8 scanlinii bloku ma identyczne
bajty świata. 10-wierszowy swept test dotyka najwyżej **3 bloków**, czyli
sprowadza się do ≤3 par testów `AND maska`. Wzorzec do skopiowania już
istnieje w tym samym pliku: `player_world_prepare`/`player_world_row`
(entities.asm:2404) — jednorazowy indeks + residuum niesione przez pętlę.

To największa pojedyncza oszczędność w ramkach z pociskiem gracza i
czyni bezpiecznym zdjęcie `bullet_active` z listy ciężkiej sceny.

### 4.2 `render_dirty_rows` — księgowość w rejestrach (~2–3k T @1 px, podwójnie @2 px)

course_renderer.asm:733–778: na każdy z 19 wierszy przypada ~150–200 T
czystej księgowości na zmiennych w RAM (`dirty_rows_remaining`,
`dirty_y`, `row_block_index`, `dirty_delta_ptr`) plus ponowne ładowanie
tych samych wartości w `render_v3_row_delta_prepared`. Przepisanie pętli
na rejestry (B=licznik, C=indeks bloku, HL=wskaźnik delty, DE=adres
ekranu, jak już częściowo jest) tnie stały koszt passu o ~jedną trzecią.
Uwaga: `dirty_y` jest potrzebne tylko ścieżce fallback (count=255) —
można je wyliczać dopiero tam.

### 4.3 Przyrostowy cache Y→indeks bloku (~0,5–1k T przy aktywnym samolocie)

Wszyscy wielowierszowi klienci `load_world_background_triplet` (samolot
8 wierszy, czołg mostowy, dirty-rows gracza) missują cache co wiersz.
Wystarczy zapamiętać obok `background_cache_y` również residuum: przy
zapytaniu o `Y = cache_y+1` inkrementować residuum i podbijać indeks
tylko przy przejściu przez 0 — bez `get_block_index_for_y`.

### 4.4 `fill_water_rect_preserve_bridge` — jedna blitka zamiast per-wiersz (~kilkaset T)

sprite_renderer.asm:637–670: gdy `bridge_active=0` (zdecydowana większość
czasu) pętla i tak woła `fill_uniform_sprite_rect` osobno dla każdego
wiersza, płacąc pełny narzut DI/zapis SP/EI (~150 T) przy 1–2-bajtowym
fillu. Test mostu raz na wejściu: brak mostu → jedno wywołanie na cały
prostokąt. Ta ścieżka biegnie co ramkę przy każdym locie pocisku.

### 4.5 `snapshot_resident_sprite_state` — LDIR (~0,5k T)

sprite_renderer.asm:137–216: ~40 par `ld a,(nn)/ld (nn),a` ≈ 1k T co
ramkę. Po przegrupowaniu żywych pól stanu w jeden ciągły blok i
zbudowaniu cienia w tej samej kolejności — jeden LDIR. Zysk umiarkowany,
ryzyko refaktoru średnie (kolejność pól musi się zgadzać z konsumentami
`timex_attr_*`), dlatego na końcu listy.

---

## 5. Przycięcie pola gry od góry/od dołu — nie warto

Koszty skalujące się z wysokością pola to praktycznie tylko dirty-pass:
19 wierszy na residue przy 152 liniach. Każde odcięte 8 linii = 1 wiersz
mniej na residue ≈ ~300–450 T @1 px, ~600–900 T @2 px — **poniżej 1,5%
budżetu ramki**, przy zauważalnym koszcie graczowym (krótsza droga
reakcji na wszystko, co wjeżdża od góry). Sprite'y, atrybuty i kolizje
nie zależą od wysokości pola.

Jeśli mimo to zechcesz przyciąć — pułapki, które dziś na to nie pozwalają
„jednym define'em":

- `PLAYFIELD_BOTTOM` (tools/build.py:763) **nie jest pełną gałką**:
  liczba wierszy passu jest zahardkodowana jako `ld a,19`
  (course_renderer.asm:731), a ścieżka delta-replay **nie ma klipu
  dolnego** (ufa liczbie 19) — zmiana samego define'a bez korekty licznika
  pisze po wierszach HUD;
- literały `168` w `update_hud_if_dirty` (main.asm:468) oraz wiersze
  tekstu 176/184 — do uzależnienia od `PLAYFIELD_BOTTOM`;
- górny margines `16` jest rozsiany literałami po wszystkich plikach
  (spawny, klipy, `add a,16` w dirty-pass) — przycięcie od góry to
  duża, ryzykowna zmiana przy zerowym zysku.

Rekomendacja: zostawić wymiary, headroom wziąć z §4 i z poluzowania
limitera z §2.

---

## 6. Drobiazgi / martwy kod

- `get_course_background_byte_indexed` (course_renderer.asm:362),
  `calc_river_center_col` (course_renderer.asm:1118),
  `timex_next_attribute_row` (render_timex.asm:124 — duplikat
  `timex_advance_object_row_fast`) — nigdzie nie wołane; do usunięcia.
- `spawn_tank` (entities.asm:955): martwe `xor a` bezpośrednio przed
  `ld a,1`.
- `prepare_transition_old_projectile_x` (sprite_renderer.asm:765) robi
  `and 7` dwa razy z przeplotem skoków — do uproszczenia (czytelność,
  cykle pomijalne).

---

## 7. Jak to zweryfikować

1. `make run-profile-timex` → pasek bordera w scenie: czołg + pocisk +
   pocisk gracza + Q. Jeśli pasek nie zbliża się do pełnej ramki,
   limiter z §2 jest nadgorliwy dla tych flag.
2. Powtórka na `run-ts2068` (60 Hz, ~59k T budżetu) — to tam limit
   pęknie najszybciej.
3. Test wady §3.2 bez emulatora czasu: leć przy samym brzegu, strzelaj
   serią, obserwuj linię brzegową za pociskiem na prostym odcinku rzeki —
   nacięcia zostają do najbliższego zakrętu.
