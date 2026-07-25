# Review pętli rysowania — gdzie realnie idzie czas ramki

Statyczne zliczenia T-stanów na typowych ścieżkach (nie pomiary emulatora,
bez kontencji ULA). Budżet ramki 48K: **69 888 T**. Scena odniesienia:
`speed_pixels=1`, aktywne: gracz (nie steruje), ship0, helikopter, FUEL, balon,
czołg brzegowy; bez mostu, bez pocisków.

> `review-main-loop.md` jest w większości nieaktualny: §1 (delta bloku)
> i §6a (podwójny odczyt `0xfbfe`) są **zrobione**, a plik opisuje jeszcze
> jednoplikowy `main.asm`. To jest jego następca.
>
> Osobna analiza samej aktualizacji brzegów rzeki (czy delta jest minimalna,
> martwy kod obsługi wyspy, podejrzenie dziury w przęśle mostu przy dryfie
> brzegu): `review-claude-linia-0brzegowa.md`.

---

## Odpowiedź na pytanie o „wolniejszy niż XOR”

Ta teza nie broni się w liczbach. Silnik rezydentny płaci narzut
(`snapshot_resident_sprite_state` ~1 050 T + logika `transition_*` ~1 500 T +
odtwarzanie pasków ~750 T ≈ **3 300 T**), ale oszczędza całą fazę kasowania:
przy tej scenie same bloki sprite'ów to ~9 400 T, więc odpowiednik XOR-owy
(erase + draw, przy czym XOR to read-modify-write, czyli droższy bajt)
kosztowałby ~19 000 T zamiast ~12 700 T. **Metoda rysowania sprite'ów jest
tutaj szybsza, nie wolniejsza.**

Jeśli poprzedni silnik faktycznie był szybszy, to nie z powodu XOR-a, tylko
dlatego, że robił mniej: dzisiejsza ramka ma dodatkowo pas atrybutów obiektów,
delty terenu z wyspami, most/drogę i pełny Timex 8×1. Poniżej trzy miejsca,
w których ten dodatkowy koszt jest w większości **narzutem, a nie pracą**.

---

## Budżet ramki (szacunek, speed = 1)

| Pozycja | standard | Timex |
|---|---:|---:|
| `render_dirty_rows` (19 wierszy) | ~9 700 | ~9 700 |
| bitmapy sprite'ów (`transition_all_resident_sprites`) | ~9 400 | ~9 400 |
| **atrybuty** | ~5 000 śr. (~8 400 gdy dirty) | **~16 000** |
| `snapshot_resident_sprite_state` | ~1 050 | ~1 050 |
| logika encji + kolizje | ~2 500 | ~2 500 |
| `generate_block` (amortyzacja co 8 ramek) | ~1 250 | ~1 250 |
| AY + klawiatura + `profile_*` | ~800 | ~800 |
| ROM ISR (IM1, `KEY-SCAN`) | ~1 000–2 000 | ~1 000–2 000 |
| **razem** | **~31 000** | **~42 000** |

Przy `speed_pixels=2` dochodzi drugie ~9 700 T na `render_dirty_rows`
i podwaja się częstość `generate_block`.

---

## 1. Timex: pas atrybutów 8×1 — ~16 000 T/ramkę (23 % ramki) 🔴

`timex_paint_object_rows` (`src/render_timex.asm:50`) kosztuje **224 T na wiersz,
w którym zapisuje 1–2 bajty**. Dedykowana pętla FUEL
(`src/render_timex.asm:132`) to **234 T/wiersz × 32 wiersze = 7 500 T** — na
jeden zapisany bajt atrybutu przypada 234 T narzutu.

Rozbicie na wiersz (`timex_paint_object_row`, width = 1):

| fragment | T |
|---|---:|
| `object_attr_width/value` z RAM | 34 |
| właściwy zapis + `djnz` | 24 |
| `object_attr_y` / `object_attr_rows` przez RAM | 60 |
| test dolnej granicy | 25 |
| `call timex_next_attribute_row` | 56 |
| `jr` + korekta `l` | 24 |

Suma per ramkę: helikopter 10×224 + czołg 10×224 + balon 20×~210 + FUEL
32×234 ≈ **16 200 T**, i to **bezwarunkowo w każdej ramce** —
`update_frame_object_attributes` (`src/main.asm:139`) woła wszystkie cztery
`paint_*` nawet gdy `speed_pixels = 0` i nic się nie ruszyło.

### Co zrobić

**(a) Pętla na rejestrach** — adres, kolor i licznik trzymane w HL/C/B,
inkrementacja adresu inline (`H`+1 wewnątrz pasma, co ósmy wiersz `L`+32),
przycięcie do `PLAYFIELD_BOTTOM` policzone **raz przed pętlą**:

```asm
; HL = adres atrybutu 8x1, B = liczba wierszy (już przycięta), C = kolor
timex_attr_row:
    ld (hl),c            ; 7
    ld a,h               ; 4
    and 7                ; 7
    cp 7                 ; 7
    jr z,timex_attr_band ; 7      (1 na 8 wierszy)
    inc h                ; 4
    djnz timex_attr_row  ; 13   => 49 T/wiersz
```

16 200 T → ~3 500 T. **Zysk ~12 700 T/ramkę.**

**(b) Malować tylko wiersze wchodzące.** Dla obiektów jednokolorowych
(helikopter, czołg) przesunięcie o 1 px w dół nie zmienia koloru 9 z 10 wierszy —
`cleanup_timex_saved_*` już czyści wiersz odchodzący, więc `paint_*` wystarczy,
żeby domalował `speed_pixels` wierszy wchodzących. Dla FUEL/balonu pasy kolorów
są liczone względem topu obiektu, więc zmieniają się tylko wiersze przy 3–4
granicach pasów + wiersze wchodzące. 72 wiersze/ramkę → ~10.

**(c) `ret z` gdy `speed_pixels = 0` i geometria obiektu bez zmian** —
w trybie wolnym (`A`) co druga ramka nie wymaga żadnej pracy nad atrybutami.

Razem (a)+(b): pas atrybutów Timeksa spada z ~16 000 T do ~1 000 T.

---

## 2. Standard: cztery obiekty przemalowywane, gdy ruszy się jeden — ~5 000 T/ramkę 🔴

`update_standard_object_attributes` (`src/main.asm:193`) testuje cztery
obiekty, ale przy **dowolnej** zmianie skacze do
`standard_object_attributes_dirty` (`src/main.asm:203`), który robi
`restore` + `paint` **wszystkich czterech**.

Koszt jednego przebiegu:

- `restore_standard_saved_object_attributes` — dla każdego obiektu 6 par
  `ld a,(nn)/ld (nn),a` plus `push af`/`pop af` na podmianę geometrii:
  ~236 T narzutu × 4 ≈ 950 T,
- `paint_object_attribute_row` (`src/main.asm:1029`) — **~208 T na wiersz**
  przy 2–3 zapisanych bajtach (113 T samego bookkeepingu `object_attr_row` /
  `object_attr_rows` przez RAM),
- ~14 wierszy restore + ~14 wierszy paint ≈ 5 800 T,
- FUEL ma dodatkowo własny painter (`src/main.asm:693`) ~150 T/wiersz.

**Razem ~8 400 T na przemalowanie.**

Częstość: makro `STANDARD_ATTR_CHANGED` (`src/main.asm:149`) porównuje
`old_y & 0xfc` z `y & 0xfc`, czyli wyzwala się **co 4 piksele scrolla** na
obiekt. Przy 1 px/ramkę to ~34 % ramek na obiekt; przy czterech aktywnych
obiektach ≈ **80 % ramek** robi pełny przebieg → **~6 700 T średnio na ramkę**.

### Co zrobić

1. **Per-obiekt dirty**: każde `@STANDARD_ATTR_CHANGED` niech skacze do
   `restore+paint` *tego jednego* obiektu, nie do wspólnego bloku. Sam ten
   podział to ~4× mniej pracy.
2. **`and 0xf8` zamiast `and 0xfc`** dla helikoptera i czołgu — one mają
   jednolity kolor, więc zbiór komórek zmienia się dopiero co 8 pikseli.
   Test 4-pikselowy jest potrzebny wyłącznie FUEL-owi i balonowi, które
   wybierają pas koloru po pozycji w komórce. Połowa wyzwoleń znika.
3. **Pominąć `restore`, gdy nowy prostokąt pokrywa stary** (typowe przy ruchu
   o 1 wiersz w dół — do odtworzenia jest jeden wiersz u góry, nie cały
   prostokąt). Ścieżka Timeksa robi dokładnie to (`cleanup_*_delta`).
4. **`paint_object_attribute_cells` na rejestrach** — 208 T/wiersz → ~50 T.

Po tym: ~6 700 T → poniżej 1 000 T średnio.

---

## 3. `render_dirty_rows` — 390 T narzutu na 124 T użytecznej pracy 🟠

Delta bloku (§1 starego review) jest zrobiona i działa, ale **pętla wokół niej
kosztuje więcej niż sama delta**. Na wiersz (`src/course_renderer.asm:642`,
`:693`):

| fragment | T |
|---|---:|
| `dirty_row_loop` (`dirty_y`, `row_block_index` przez RAM) | 113 |
| `call calc_screen_line_addr` | 73 |
| `call block_delta_address` + `push/pop bc` | 118 |
| odczyt `block_delta_count` + testy | 43 |
| **narzut razem** | **~390** |
| pętla `render_v3_delta_byte`, 62 T × 2–4 zmienione bajty | 124–248 |

**~511 T × 19 wierszy = 9 700 T** (speed 1), **19 400 T** przy speed 2 — 28 %
ramki na wpisanie ~76 bajtów.

Kluczowe: wszystkie trzy drogie elementy są **inkrementalne**, bo kolejne
brudne wiersze różnią się dokładnie o 8 linii i o −1 na indeksie bloku:

- adres ekranu: `L += 32`, przy przeniesieniu `H += 8` → **~22 T** zamiast 73,
- rekord delty: sąsiedni blok to `−32 bajty` (8 rekordów na stronę) → **~25 T**
  zamiast 118,
- liczba wierszy jest **stała i wynosi 19** dla każdej fazy
  (`y ∈ 16..23`, `ceil((168−y)/8) = 19`), więc `cp PLAYFIELD_BOTTOM` w pętli
  jest zbędne — wystarczy licznik w `AF'`.

### Szkic docelowy

Scal `block_delta_count` z `block_delta_ops` w jeden 32-bajtowy rekord na blok
(`[count][col,val]…`, limit 15 par zamiast 16) — jeden wskaźnik obsłuży
i licznik, i operacje. Jeśli w rekordzie zapiszesz **różnice kolumn** zamiast
kolumn bezwzględnych, znika też przywracanie `E` w każdej iteracji:

```asm
; HL = rekord delty, DE = początek wiersza na ekranie, C = młodszy bajt bazy
    ld e,c               ; 4
    ld a,(hl)            ; 7   licznik
    inc hl               ; 6
    cp 255               ; 7   blok złożony -> stary renderer
    jr z,delta_complex   ; 7
    or a                 ; 4
    jr z,delta_next_row  ; 7
    ld b,a               ; 4
delta_op:
    ld a,(hl)            ; 7   przyrost kolumny
    inc hl               ; 6
    add a,e              ; 4
    ld e,a               ; 4
    ld a,(hl)            ; 7   wartość
    inc hl               ; 6
    ld (de),a            ; 7
    djnz delta_op        ; 13  => 54 T/bajt (dziś 62)
delta_next_row:
    ld a,l               ; 4   następny rekord: zaokrąglij w górę do 32
    and 0xe0             ; 7
    add a,32             ; 7
    ld l,a               ; 4
    jr nc,$+3            ; 7
    inc h                ; 4
    ; adres ekranu: c += 32, przy przeniesieniu d += 8
```

Szacunek: **~210 T/wiersz** → 4 000 T (speed 1) / 8 000 T (speed 2).
**Zysk ~5 700 T / ~11 400 T.**

Uwaga: pętla musi iść **od dołu do góry** (`y` maleje o 8, indeks bloku rośnie
o 1), żeby wskaźnik rekordu szedł do przodu; wtedy trzeba raz na 32 bloki
obsłużyć zawinięcie na `block_delta_ops`.

---

## 4. `generate_block` — spike ~10 000 T co 8 ramek 🟠

`rebuild_block_bitmap_row` (`src/course_renderer.asm:217`) buduje 32-bajtowy
wiersz, wołając `get_course_background_byte_indexed` per kolumnę, z licznikiem
i wskaźnikiem trzymanymi w RAM: **~220 T na bajt × 32 = 7 000 T**.
`rebuild_block_delta` (`:245`) dokłada ~95 T × 32 = 3 000 T (dwa wskaźniki
przechodzą przez RAM w każdej iteracji).

To nie tylko średni koszt (~1 250 T/ramkę), ale przede wszystkim **jitter**:
jedna ramka na osiem (na cztery przy `Q`) jest o 10 000 T cięższa.

### Co zrobić

- Budować wiersz **strukturalnie**, tak jak `render_full_world_row`: bieg lądu
  `0xff`, bajt maski, bieg wody `0x00`, maska prawa, ląd do kolumny 31, potem
  wyspa. ~32 zapisy × ~11 T ≈ 400 T zamiast 7 000 T.
- Deltę liczyć **w tym samym przebiegu** (masz obok stary i nowy bajt),
  ze wskaźnikami w HL/DE zamiast w RAM: ~30 T/bajt zamiast 95 T.

Spike ~10 000 T → ~1 500 T.

---

## 4½. `write_world_sprite_shifted_2xn` — 450 T/wiersz, najdroższy blitter 🟠

`src/sprite_renderer.asm:2726`, używany przez samolot przelatujący (8 wierszy)
i czołg mostowy poza mostem. W **każdym wierszu**:

- `call load_world_background_triplet` → `call block_bitmap_address` liczony od
  zera, mimo że indeks bloku zmienia się dopiero co 8 wierszy, a wskaźnik do
  materializowanego wiersza bloku jest inkrementalny (+32 przy przejściu),
- `call calc_screen_line_addr` (73 T) zamiast `pop` z `screen_line_table`,
- składanie trzech bajtów przez `world_write_byte_0/1/2` w RAM.

**8 wierszy × 450 T = 3 600 T** — najdroższy sprite w grze, i jeden z powodów,
dla których `resolve_fast_speed` dławi `Q` do 1 px, gdy samolot jest aktywny.
Wskaźnik tła inkrementalnie + `pop` na adres ekranu + składanie w rejestrach
daje ~200 T/wiersz. **Zysk ~2 000 T** w ramkach z samolotem.

## 5. `draw_current_player_dirty_rows` — 1 260 T na znalezienie 2 wierszy 🟡

`src/sprite_renderer.asm:1062` testuje resztę modulo 8 dla **wszystkich 14
wierszy** gracza (~90 T każdy), żeby złożyć na nowo zwykle 2 z nich.
`player_y` jest stałe, więc wiersze do odświeżenia wynikają wprost:

```
k = (course_phase - player_y) & 7
wiersze = { (k - j) & 7  oraz  ((k - j) & 7) + 8   dla j = 0..speed_pixels-1 }
```

~60 T zamiast 1 260 T. **Zysk ~1 200 T/ramkę** przy bardzo małej zmianie.

---

## 6. Drobiazgi (razem ~2 000–2 500 T/ramkę)

| Miejsce | Problem | Zysk |
|---|---|---:|
| `src/sprite_renderer.asm:1915` i pozostałe blittery | `di` + `ld (sprite_saved_sp),sp` + `ei` w **każdym** blicie (~50 T × ~15 wywołań). `DI` jest konieczne, ale wystarczy raz: `di` zaraz po `halt`, `ei` tuż przed następnym `halt` | ~700 T |
| `src/sprite_renderer.asm:2404`, `:2479` | test `sprite_write_spill` **w każdym wierszu** (24 T), choć jest stały dla całego blitu — dwa warianty pętli | ~450 T |
| `transition_bullet_direct`, `transition_shell_direct`, `transition_bridge_tank_direct` | dla nieaktywnych obiektów przelatuje ~200 T zapisów geometrii; wystarczy `ld a,(old_active) / ld b,a / ld a,(new_active) / or b / ret z` na wejściu | ~600 T |
| `src/input.asm:202` | `profile_begin`/`profile_end` wołane bezwarunkowo 3× (`call` + odczyt `profile_enabled` + `ret`) także przy `PROFILE_BORDER=0` — do `#if` | ~150 T |
| `snapshot_resident_sprite_state` (`src/sprite_renderer.asm:137`) | 40 par `ld a,(nn)/ld (nn),a` = 26 T/pole. Jeśli pola żywe i snapshot ułożyć jako dwa spójne bloki → jeden `LDIR` (21 T/bajt) | ~200 T |
| `write_water_sprite_1xn` (FUEL, 32 wiersze) | 55 T/wiersz na 1 zapisany bajt; rozwinięcie pętli usuwa `djnz` | ~400 T |
| ROM ISR (IM1) | `KEY-SCAN` ROM-u chodzi w każdej ramce, choć gra sama czyta klawiaturę. IM2 z pustym handlerem to czysty zysk, ale wymaga przeniesienia `SP` (dziś `0xff00`) i dołożenia `im`/`ld i,a`/`reti` do `build.py` | ~1 000–2 000 (zmierzyć) |

---

## Uwagi metodyczne

- Powyższe to **statyczne zliczenia**, bez kontencji ULA. Kontencja dokłada tu
  jednak niewiele: kod i wszystkie tablice siedzą powyżej `0x8000`, więc
  opóźniane są wyłącznie same dostępy do ekranu (~300–350 zapisów na ramkę),
  a pierwsze ~14 000 T po przerwaniu to górny border, gdzie opóźnień nie ma.
  Realnie **~500–1 000 T na ramkę**, czyli ~1,5 %. Błąd samych zliczeń
  (±15–20 %) jest większy niż kontencja.
- `make profile` pozostaje źródłem prawdy. Warto przed zmianami zrobić
  odczyt bazowy dla trzech scen: (1) spokojna ramka speed 1, (2) `Q` bez
  ciężkich obiektów, (3) most + czołg mostowy + pocisk.
- Warto też otoczyć ramkami bordera osobno `render_dirty_rows`
  i `update_frame_object_attributes` — wtedy punkty 1–3 potwierdzą się
  albo wywrócą w jednym uruchomieniu.

## Ograniczenia `tools/build.py`

Wszystkie szkice powyżej mieszczą się w obsługiwanym podzbiorze
(`ld (hl),r`, `add hl,rr`, `ex af,af'`, `(hl)` w ALU, `ld sp,hl`, `djnz`).
Brakuje natomiast rzeczy, które by się przydały i wymagają dopisania kodowania
(zgodnie z AGENTS.md — w tym samym commicie):

- `cpl` (0x2F) zamiast `xor 255` w `write_land_sprite_2xn` i blicie czołgu
  mostowego — 4 T zamiast 7 T na bajt,
- `scf` (0x37) zamiast idiomu `xor a / cp 1` do ustawienia carry,
- `exx` (0xD9) — dałoby drugi komplet rejestrów w pętli brudnych wierszy,
- `im 2` / `ld i,a` / `reti` — tylko jeśli wchodzicie w IM2.

---

## Priorytety

| Prio | Zmiana | Zysk/ramkę |
|---|---|---:|
| 1 | Timex: `timex_paint_object_rows` + painter FUEL/balonu na rejestrach | ~12 700 T (tylko Timex) |
| 2 | Standard: dirty i `restore`/`paint` per obiekt, `0xf8` dla helikoptera i czołgu, painter na rejestrach | ~5 700 T |
| 3 | `render_dirty_rows`: adres i rekord delty inkrementalnie, scalony rekord `[count][Δcol,val]` | ~5 700 T (speed 1) / ~11 400 T (speed 2) |
| 3½ | `write_world_sprite_shifted_2xn` na rejestrach, wskaźnik tła inkrementalnie | ~2 000 T (ramki z samolotem) |
| 4 | `generate_block`: strukturalne budowanie wiersza + delta w tym samym przebiegu | spike 10 000 → 1 500 T |
| 5 | `draw_current_player_dirty_rows`: wyliczyć reszty zamiast skanować 14 wierszy | ~1 200 T |
| 6 | Drobiazgi z §6 (test spill, wczesne wyjścia, `#if` na profilu, `LDIR` w snapshocie) | ~1 300 T |
| 7 | `di`/`ei` raz na ramkę zamiast per blit; opcjonalnie IM2 | ~700 T (+1 000–2 000 za IM2) |

## Kolejność wdrożenia

**Krok 0 — zmierzyć, zanim się cokolwiek ruszy.** Osobne kolory bordera wokół
`render_dirty_rows` i `update_frame_object_attributes` w `main_frame_active`.
To ~30 minut i potwierdza albo wywraca punkty 1–3, które opierają się na
zliczeniach, a punkt 2 dodatkowo na argumencie o częstości (~80 % ramek).

Dalej: **2a → 1a → 5 → 6 → 4 → 2b/1b → 3 → 3½ → 7**, z `make profile` po
każdym kroku.

- **2a** — sam podział dirty na obiekty + `0xf8` dla helikoptera i czołgu.
  Bez nowego paintera: ~40 linii w `main.asm`, ~4 500 T, błędy widać od razu
  na ekranie jako zabrudzone atrybuty.
- **1a** — sama pętla `timex_paint_object_rows` na rejestrach (bez malowania
  wyłącznie wierszy wchodzących). Lokalna zmiana w jednym pliku.
- **2b/1b** — dopiero potem painter na rejestrach w buildzie standardowym
  i malowanie przyrostowe w Timeksie.
- **3** jest ostatnią dużą zmianą, bo rusza układ danych (`block_delta_count`
  + `block_delta_ops` → jeden rekord) i dotyka ścieżki zapasowej oraz naprawy
  mostu (`bridge_restore_top` → `render_v3_row`).
- **7** na sam koniec i osobnym commitem: `SP` wskazuje wtedy w
  `screen_line_table` przez całą ramkę, więc pomyłka w `ei`/`halt` kończy się
  nadpisaniem tablicy przez ROM-owe przerwanie, a nie zwykłym glitchem.
