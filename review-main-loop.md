# Review `main_loop` — możliwe przyspieszenia

Przegląd `src/main.asm` (5960 linii) pod kątem wszystkiego, co wisi na
`main_loop`. Liczby to **statyczne zliczenia T-stanów na typowej ścieżce**,
nie pomiary w emulatorze. Budżet ramki ZX Spectrum 48K: **69888 T**
(3,5 MHz / 50,08 Hz).

> **Uwaga:** `review-optimizations.md` jest nieaktualny — opisuje `render_cell`,
> `make_cell_byte`, `calc_bank_range` i ścieżkę Timex, których w źródle już nie
> ma. Z tamtej listy aktualny został tylko punkt o `read_keyboard` (§5);
> `init_attributes` już używa `LDIR`.

---

## 1. Dominujący koszt: `render_dirty_rows` → `render_v3_row_indexed`

Wspólna ścieżka (bez wyspy) to ok. **590 T na wiersz**:

| Fragment | Koszt |
|---|---|
| preludium + `calc_screen_line_addr` | ~131 T |
| lewy bank | ~121 T |
| prawy bank | ~117 T |
| sprawdzenie wyspy (ścieżka „brak wyspy") | ~121 T |
| narzut pętli `dirty_row_loop` | ~100 T |

Przy `speed_pixels=1` renderujesz 22 wiersze (~13 000 T ≈ **19% ramki**),
przy `speed_pixels=2` — 44 wiersze (~26 000 T ≈ **37% ramki**).

### Kluczowa obserwacja strukturalna

Treść wiersza zależy **wyłącznie** od `row_block_index`, a nie od `dirty_y` —
wiersz dostarcza tylko adres bazowy. Co więcej, porównanie „stare vs nowe"
zawsze dotyczy pary bloków `(i-1, i)`.

Wyprowadzenie z `get_block_index_for_y`:

```
index = (course_block_head - ((y + 7 - course_phase) >> 3)) & 31
```

Dirty-wiersze spełniają `y ≡ course_phase (mod 8)`. Dla wiersza `y` i nowej fazy
`phase` mamy `k = (y - phase) / 8`, więc `index_new = head - k`. Przed scrollem
`phase_old = phase - 1`, co daje `index_old = head_old - (k+1) = index_new - 1`.
Gdy faza zawinęła do 0, `head` wzrósł o 1, a `phase_old = 7` — oba efekty się
znoszą i nadal `index_old = index_new - 1`.

Dokładnie to zakłada już kod wyspy w linii 1195 (`row_block_index - 1`).

**Wniosek:** cała ta praca porównawcza to funkcja indeksu bloku, wykonywana
22–44 razy na ramkę, choć jej wynik zmienia się raz na 8 pikseli scrolla.

### Co zrobić

Przenieś porównanie do `generate_block` — dla każdego z 32 bloków pierścienia
policz **raz** listę operacji `(offset_w_wierszu, wartość)` opisującą różnicę
`i-1 → i`. Pętla wierszy sprowadza się wtedy do: adres bazowy + odtworzenie
N par.

Koszt jednej pary przy `HL` = baza wiersza, `DE` = wskaźnik listy:

```asm
ld a,(de)      ; 7   offset
inc de         ; 6
add a,c        ; 4   c = młodszy bajt bazy wiersza
ld l,a         ; 4
ld a,(de)      ; 7   wartość
inc de         ; 6
ld (hl),a      ; 7
               ; = 41 T na zmieniony bajt
```

Typowy blok zmienia 2 bajty (maska lewa + prawa), więc wiersz spada z ~590 T do
**~170 T** — ok. **3,4×** na najdroższym elemencie ramki, czyli **13–18 tys. T**
odzyskane przy szybkim scrollu.

Prekompute wykonuje się raz na wygenerowany blok, czyli raz na 8 pikseli scrolla
(co 8 ramek przy speed 1, co 4 przy speed 2) — amortyzowany koszt to ~150–350 T
na ramkę wobec zysku rzędu kilkunastu tysięcy.

### Dlaczego to się opłaca — analiza `block_motion_table` (linia 5437)

Pary `(center_step, half_step)` dają `dL = center - half`, `dR = center + half`:

| Wpis | (c, h) | dL | dR |
|---|---|---|---|
| 1  | (0, 0)   | 0  | 0  |
| 2  | (1, 1)   | 0  | +2 |
| 3  | (1, -1)  | +2 | 0  |
| 4  | (0, 1)   | -1 | +1 |
| 5  | (1, 0)   | +1 | +1 |
| 6  | (-1, 0)  | -1 | -1 |
| 7  | (0, -1)  | +1 | -1 |
| 8  | (-1, 1)  | -2 | 0  |
| 9  | (0, 0)   | 0  | 0  |
| 10 | (1, 0)   | +1 | +1 |
| 11 | (-1, 0)  | -1 | -1 |
| 12 | (0, 1)   | -1 | +1 |
| 13 | (0, -1)  | +1 | -1 |
| 14 | (1, 0)   | +1 | +1 |
| 15 | (-1, 0)  | -1 | -1 |
| 16 | (-1, -1) | 0  | -2 |

- `dL = 0` w 4/16 wpisów, `dR = 0` w 4/16 → bank całkowicie statyczny, 3 zapisy
  do pominięcia.
- Przy `dL = ±1` kolumna bajtowa zmienia się tylko **co drugi blok**
  (bo `col = q >> 1`), a maska przełącza się co blok → bardzo często zmienia się
  **tylko bajt maski**.

Dziś zapisujesz zawsze 3 bajty na bank, niezależnie od tego, co się zmieniło.

### Ważne zastrzeżenie

Delta zakłada, że ekran zawiera treść bloku `i-1`. To prawda dla
`render_dirty_rows`, ale **nie** dla `render_v3_row` wołanego z
`bridge_restore_top` (linia 3706) — tam wiersz został zamalowany przez
`bridge_fill_rows` i wymaga bezwarunkowego zapisu pełnej treści.

Trzeba więc rozdzielić dwa wejścia:

- `render_v3_row_full` — bezwzględne, dla mostu i `full_redraw`
- `render_v3_row_delta` — dla pętli dirty

Pamięci jest pod dostatkiem: binarka kończy się na ~`0xBAF0`, do `SP = 0xff00`
zostaje ~17 KB. Lista operacji o pojemności 8 par to 32 × 17 = 544 bajty; dla
rzadkich przypadków przekraczających pojemność (pojawienie się / zniknięcie
wyspy podczas rozwidlenia) wystarczy flaga „blok złożony" i fallback na
istniejącą ścieżkę ogólną.

---

## 2. Ta sama pętla, bez zmiany architektury (~40% taniej)

Wariant tańszy w realizacji niż §1 (wyklucza się z §1 — to ta sama idea, tylko
mniej agresywna). Samo przeniesienie stanu z RAM do rejestrów daje ~230 T/wiersz
przy **identycznej semantyce**:

- **`calc_screen_line_addr` → adresowanie przyrostowe** (~53 T/wiersz).
  Kolejne dirty-wiersze dzieli dokładnie 8 linii. Przy układzie adresu
  `H = 0x40 | third*8 | (y & 7)`, `L = ((y & 0x38) << 2) | col` dodanie 8 do `y`
  to `L += 32`, a przy przeniesieniu `H += 8`:

  ```asm
  ld a,l
  add a,32
  ld l,a
  jr nc,addr_ready
  ld a,h
  add a,8
  ld h,a
  addr_ready:
  ```

  22–33 T zamiast 78 T z `call calc_screen_line_addr`.

- **`row_screen_addr` w BC zamiast RAM** (~52 T/wiersz). Dziś: 1× zapis 16 T +
  3× `ld hl,(nn)` po 16 T. Z bazą w BC: `ld h,b : ld a,c : add a,d : ld l,a` =
  16 T zamiast 28 T na użycie.

- **`row_block_index` w rejestrze** (~40 T/wiersz) — ładowany 4× po 13 T.
  Tablice bloków są `align 256`, więc indeks i tak ląduje prosto w `L`.

- **Inline `render_v3_row_indexed` do pętli** (~60 T/wiersz) — znika `call`/`ret`
  i podwójne sprawdzanie granic Y (raz w `render_v3_row`, raz w wersji
  indeksowanej).

- **`dirty_y` w rejestrze** (~26 T/wiersz) — dziś load/modify/store w każdej
  iteracji `dirty_row_loop`.

- **`dirty_old_island_*` / `dirty_new_island_*` w rejestrach** (~26 T/wiersz na
  ścieżce bez wyspy) — dziś przechodzą przez RAM zanim zostaną porównane.

- **Pierwsza iteracja każdej klasy reszt zawsze wypada** przez `cp 8 / ret c`,
  bo `dirty_first_y = course_phase ∈ 0..7`. Startuj od `phase + 8` z
  odpowiednio skorygowanym indeksem bloku (~148 T/ramkę).

Przykład docelowego lewego banku z bazą wiersza w `BC` i indeksem bloku w `D`
(92 T zamiast 121 T):

```asm
ld l,d
ld h,HIGH(block_left_mask)
ld a,(hl)                  ; maska
ex af,af'
ld h,HIGH(block_left_col)
ld a,(hl)                  ; kolumna (L nadal = d)
add a,c
ld l,a
ld h,b
dec l
ld (hl),255
inc l
ex af,af'
ld (hl),a
inc l
xor a
ld (hl),a
```

---

## 3. Atrybuty — ~7% ramki na samą arytmetykę adresu

`paint_object_attribute_row` (linia 512) liczy adres atrybutu od zera dla
**każdego** wiersza: ~150 T prologu + ~72 T epilogu, żeby zapisać 1–3 bajty
(~30 T). Stosunek narzutu do pracy **7:1**. Kolejne wiersze atrybutów to po
prostu **+32**.

Na ramkę wychodzi ~22 wiersze atrybutowe (helikopter 2×~3, fuel 2×~5, czołg
2×~3 — `restore_*` i `paint_*` idą parami) → **~4800 T ≈ 7% ramki**.

**Co zrobić:** policz adres raz przed pętlą, potem `ld de,32 : add hl,de`;
trzymaj `object_attr_row` / `object_attr_rows` / `object_attr_width` /
`object_attr_value` w rejestrach zamiast czytać je z RAM w każdej iteracji.

---

## 4. `paint_fuel_attributes` — 5× pełny prolog dla 5 bajtów

`paint_next_fuel_attribute` (linia 368) woła `paint_object_attribute_cells`
**oddzielnie dla każdego** z 4–5 wierszy, bo każdy ma inny kolor (F/E biały,
U/L magenta), za każdym razem z `object_attr_rows = 1`.

To ~1100 T po to, by zapisać 5 bajtów. Zrób z tego jedną pętlę trzymającą adres
w rejestrze i przełączającą tylko wartość koloru.

---

## 5. Sprite'y — blitter jest już dobry, zostały drobiazgi

Ścieżka `pop hl` z `screen_line_table` przez `SP` plus gotowe przesunięcia
z cache (`init_shifted_sprites`) to właściwe rozwiązanie — nie ma tu czego
przewracać. Co da się jeszcze uszczknąć:

- **`di`/`ei` + `ld (sprite_saved_sp),sp` w każdym blicie** — ~48 T × ~20
  wywołań (erase + draw) ≈ **1000 T/ramkę**. `DI` jest konieczne (ROM ISR
  odłożyłby na stos wskazujący w tablicę linii i zniszczył ją), ale wystarczy
  **raz**: `DI` po `halt`, `EI` tuż przed następnym `halt`, `SP` zapisany raz na
  ramkę.

- **`inc de` → `inc e`** w pętlach wierszy, jeśli dane wiersza sprite'a nie
  przekraczają strony: 2 T × 3 bajty × wysokość.

- **Rozwinięcie `djnz`** — 13 T na wiersz (gracz: 13 wierszy × 2 przebiegi =
  338 T), kosztem rozmiaru kodu.

- **Ścieżka `shift == 0`** w `xor_sprite_shifted_2xn`: trzeci bajt jest wtedy
  zawsze zerem, a i tak płacisz `ld a,(de) / xor (hl) / ld (hl),a` = 27 T na
  wiersz. `player_x` chodzi co 2 piksele, więc trafia się to w 1/4 przypadków.

Dla orientacji, koszt wiersza 3-bajtowego blitu:
`pop hl` 10 + adres 12 + 2×31 + 27 + `djnz` 13 = **124 T**.

---

## 6. Darmowe drobiazgi

- **`read_keyboard` czyta port `0xfbfe` dwa razy** — linia 5281 (bit 0 = Q,
  szybko) i linia 5400 (bit 3 = R, reset). Wystarczy jeden odczyt schowany
  w rejestrze (~22 T).

- **`profile_begin` / `profile_end` wołane bezwarunkowo** — 3× ~45 T = 135 T na
  ramkę na `call` + odczyt `profile_enabled` + `ret`, nawet gdy
  `PROFILE_BORDER=0`. Warto je asemblować warunkowo.

---

## Podsumowanie priorytetów

| Prio | Zmiana | Szacowany zysk |
|---|---|---|
| 1 | Prekompute delty bloku w `generate_block`, pętla dirty odtwarza listę operacji | ~13–18 tys. T/ramkę (19–26%) |
| 2 | *Alternatywnie:* rejestry + adres przyrostowy w istniejącej pętli dirty | ~5–11 tys. T/ramkę (8–17%) |
| 3 | Adres atrybutu przyrostowo (+32), stan w rejestrach | ~3–4 tys. T/ramkę (5%) |
| 4 | Jedna pętla w `paint_fuel_attributes` | ~800 T/ramkę |
| 5 | `DI`/`EI` i zapis `SP` raz na ramkę zamiast per blit | ~1000 T/ramkę |
| 6 | `read_keyboard`, warunkowy profiling, `inc e` | ~200 T/ramkę |

Punkty **1 i 2 się wykluczają** — 2 to tańsza wersja tego samego pomysłu.

## Sugerowana kolejność

1. §3 + §4 w jednym commicie — małe, lokalne, niskie ryzyko regresji, ~5% ramki.
2. `make profile` jako punkt odniesienia (kolory bordera pokażą, gdzie faktycznie
   idzie czas po tej zmianie).
3. §1 jako osobna zmiana, z rozdzieleniem `render_v3_row_full` /
   `render_v3_row_delta`.
4. §5 i §6 na koniec jako sprzątanie.
