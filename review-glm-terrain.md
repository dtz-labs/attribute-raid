# Review generacji terenu — `course_renderer.asm`

Analiza samego generatora bloków i prekomputacji delty, bez ruszania kodu.
Liczby to **statyczne zliczenia T-stanów Z80**. Ostateczny arbiter to
`make profile`.

## Gdzie to leży w budżecie ramki

`advance_course_sample` (`course_renderer.asm:49`) woła `generate_next_block`
tylko wtedy, gdy `course_phase` zawinęło do 0 — czyli **raz na 8 pikseli
scrolla**. Przy `speed=1` to raz na 8 ramek, przy `speed=2` raz na 4 ramki.

Jedno wywołanie `generate_block` (~6100 T) składa się z:

| Fragment | Linie | Koszt / blok |
|---|---|---|
| `update_course_motion` + clamping center/half | 66–128 | ~400 T |
| konwersja krawędzi → col+maska (lewy + prawy bank) | 134–214 | ~300 T |
| `rebuild_block_bitmap_row` (materializacja wiersza) | 217–243 | **~3200 T** |
| `rebuild_block_delta` (porównanie z poprzednikiem) | 245–308 | **~2240 T** |
| **razem** | | **~6140 T / blok** |

Amortyzowane: **~770 T/ramkę** przy `speed=1`, **~1535 T/ramkę** przy
`speed=2`. Same w sobie niegrubo, ale **konkretny pik** na ramce generującej
blok pada dokładnie na tę ramkę, która już ma najcięższą pętlę dirty
(38 wierszy). To te ramki jako pierwsze łamią 50 Hz.

## Co już jest dobrze

- **Delta bloku w ogóle istnieje** — pętla dirty odtwarza gotową listę
  `(col,value)` (~41 T/bajt) zamiast powtarzać geometrię.
- **Tablice `block_*` są `align 256`** — indeks bloku ląduje bezpośrednio w
  `L`, adresowanie to `ld h,HIGH(...)`.
- **Zmaterializowany wiersz jest współdzielony** z runtime'em: czyta go
  `get_world_background_byte` (`sprite_renderer.asm:2068`) przy kompozycji
  sprite'ów na tle. Więc materia nie jest zbędna — ma drugiego konsumenta.
- **LFSR + `center_motion_table`** dają kontrolowane zakręty; algorytm
  generatora jest rozsądny, nie ma w nim decyzji o złożoności gorszej niż
  O(1) na blok.

Materia do poprawy leży w **mechanice**, nie w algorytmie.

---

## 1. `rebuild_block_bitmap_row` — 32 lookupy zamiast kilku filli

Najdroższy element generatora (~52% jego kosztu). Pętla
`rebuild_block_bitmap_byte` (linia 228) iteruje po **wszystkich 32
kolumnach** i dla każdej woła `get_course_background_byte_indexed`, które
robi do 5 porównań (`cp (hl)`) przeciwko `block_left_col`,
`block_left_mask`, `block_right_col`, `block_island_left`,
`block_island_right`.

Per kolumna: ~50–65 T (ciało `get_course_background_byte_indexed`) +
~27 T (`call`/`ret`) + ~50 T narzutu pętli (ładowanie `block_bitmap_build_*`
z RAM, wskaźnik w RAM, licznik w RAM). **~110–140 T × 32 ≈ 3600 T**.

A przecież wiersz ma strukturę **ciągłych runów**:

```
[0 .. left_col-1]             = 0xff   (ląd lewy)
[left_col]                    = left_mask
(left_col .. right_col-1)     = 0x00   (woda)  -- z ew. wyspą
[right_col]                   = right_mask
(right_col+1 .. 31)           = 0xff   (ląd prawy)
[island_left .. island_right] = 0xff   (opcjonalnie)
```

Wystarczy kilka `LDIR`/małych filli:

```asm
; HL = baza wiersza w block_bitmap_rows
; 1) lewy ląd: (HL)[0..left_col-1] = 0xff
; 2) (HL)[left_col] = left_mask
; 3) woda: (HL)[left_col+1..right_col-1] = 0x00
; 4) opcjonalnie wyspa wewnątrz runu wody = 0xff
; 5) (HL)[right_col] = right_mask
; 6) prawy ląd: (HL)[right_col+1..31] = 0xff
```

`LDIR` na N bajtów to ~16·N + ~30 T setupu. Dla typowego bloku (bez wyspy):
~130 (lewy ląd) + 7 (maska) + ~225 (woda) + 7 (maska) + ~130 (prawy ląd)
= **~500 T**. Z wyspą (2 dodatkowe runy) ~700 T. Zamiast ~3600 T.

**Zysk: ~2500–3000 T na blok** (~80% tej procedury). Największy pojedynczy
strzał w całym generatorze. Lokalna zmiana — to jedna funkcja produkująca
te same 32 bajty.

### Haczyk do sprawdzenia

`get_course_background_byte_indexed` implementuje dokładnie tę samą
strukturę runów, więc run-based materializacja musi pokrywać się z nią
co do bitu na granicach: `cp (hl)` jest porównaniem bez znaku, a
`left_col`/`right_col` pochodzą z `srl×3` (zawsze 0..31). Warunki brzegowe
`left_col == 0` (pusta lewa stać lądu) i `right_col == 31` trzeba obsłużyć
jako puste runy. Po zmianie warto porównać `block_bitmap_rows` z buildem
referencyjnym na kilku losowych seedach `lfsr`.

---

## 2. `rebuild_block_delta` — wskaźniki round-tripują przez RAM

Druga procedura (~36% kosztu generatora). Pętla
`rebuild_block_delta_byte` (linia 266) trzyma wszystkie trzy wskaźniki w
RAM i per bajt robi:

```asm
ld hl,(block_delta_old_ptr)   ; 16
ld a,(hl); ld b,a; inc hl     ; 7+4+6
ld (block_delta_old_ptr),hl   ; 16
ld hl,(block_delta_new_ptr)   ; 16
ld a,(hl); ld c,a; inc hl     ; 7+4+6
ld (block_delta_new_ptr),hl   ; 16
cp b; jr z,next               ; 4+7/12
```

To **~91 T samego ruchu wskaźnikami** na każdy z 32 bajtów, plus ścieżka
 emisji (~40 T) gdy bajt się różni. Łącznie ~130 T × 32 ≈ **~4160 T**
wliczając emisję, z czego połowa to sam round-trip wskaźników.

Trzy wskaźniki zmieszczą się w parach rejestrów:

- `DE` → wiersz old,
- `HL` → wiersz new,
- `BC` → wskaźnik zapisu delty (albo `IX`).

Licznik kolumny to `B`/`B'` albo licznik uboczny. W ciele pętli bez round-tripu:

```asm
ld a,(de)            ; 7
ld b,a               ; 4
inc de               ; 6
ld a,(hl)            ; 7   (nowy bajt = wartość do emisji)
cp b                 ; 4
jr z,delta_next      ; 7/12
inc hl               ; 6   (moved past cp path)
; emisja: (IX)=col, (IX+1)=a
...
```

Per bajt spada do ~35–45 T (bez emisji) / ~75 T (z emisją).

**Zysk: ~1200–1600 T na blok.** Reorganizacja jednej pętli, ta sama
semantyka wyjścia.

---

## 3. (Opcjonalnie) Delta geometryczna zamiast bajt-po-bajcie

`rebuild_block_delta` porównuje dwa zmaterializowane wiersze bajt po bajcie.
Ale lista zmienionych kolumn da się wyprowadzić **bezpośrednio z geometrii**
bloku `i-1` i `i`:

- stara kolumna lewej krawędzi, która przestała być krawędzią → 0xff lub 0x00,
- nowa kolumna lewej krawędzi → `left_mask`,
- analogicznie prawa,
- granice wyspy (już dziś runtime ma tę logikę w `render_v3_row_indexed`:
  `dirty_island_changed` w linii 820 i dalej).

To dokładnie ten sam zestaw przypadków, który runtime obsługuje w
`render_v3_row_indexed` (linie 820–928). Generyczne porównanie w
`rebuild_block_delta` to najprostsza poprawna implementacja, ale nie
najtańsza — geometria zmienia najwyżej ~6 kolumn, więc listę da się
wyprodukować w ~300–500 T zamiast ~2200 T.

**Ale uwaga:** materia (zmaterializowany wiersz) i tak musi powstać
(punkt 1), bo `get_world_background_byte` czyta ją w runtime. Zatem
delta geometryczna skraca **tylko** prekomputację delty, nie eliminuje
materializacji. Opłaca się dopiero **po** punktach 1 i 2 — jako kolejny
krok pozbawiający `rebuild_block_delta` potrzeby istnienia w obecnej
postaci. Wyższe ryzyko (wiele przypadków brzegowych wyspy), więc osobna
zmiana, nie wspólnie z 1/2.

---

## 4. Drobne w `generate_block`

- **Wielokrotne ładowanie `gen_center_x` / `gen_half_x` z RAM** (linie 69,
  75, 104, 115, 134, 136, 170, 172). Każde `ld a,(nn)` to 13 T. Sekcja
  clamping (104–128) i konwersja krawędzi (134–203) czytają te pary łącznie
  ~8 razy. Po `update_course_motion` można by trzymać `center_x` w `B`/`C`
  przez resztę funkcji i zapisać raz na końcu. Zysk ~80–100 T/blok.

- **Konwersja lewej krawędzi** (134–168) przelicza `gen_center_x -
  gen_half_x` drugi raz (już po clamping, który ten sam ładował w 104–127).
  Drobna, ale flagowa redundancja.

- **`push af`/`pop af`** wokół ładowania `course_block_head` (linie 142/146,
  177/181) — istnieją tylko po to, by zachować pixel-edge przez narzut
  zapisu `block_left_x`. Lepsza alokacja rejestrów (trzymać `head` w
  rejestrze przez całą konwersję, zamiast czytać cztery razy z RAM)
  usuwa oba `push/pop` i cztery `ld a,(course_block_head)` (× 13 T).

Razem te drobiazgi to **~200–250 T/blok**. Robić dopiero po 1 i 2, ich
względny udział wtedy rośnie.

---

## 5. Czego **nie** warto ruszać

- **`update_course_motion` / `lfsr_next` / `update_course_feature`** — tanie
  i rzadkie. `lfsr_next` (~30 T) leci raz na blok, kiedy `motion_timer`
  wygaśnie.
- **Pętla dirty odtwarzająca deltę** (`render_v3_row_delta`) — ta jest już
  chuda; to oddzielny temat z `review-glm.md` (przyrostowy adres linii).
- **Pojemność listy delta = 16 par, overflow → 255 → fallback** —
  wystarczająca; fallback do `render_v3_row_indexed` trafia na ścieżkę,
  która ma własną, sprytną logikę diff'u wyspy.

---

## Podsumowanie

| Prio | Zmiana | Linie | Zysk / blok | Ryzyko |
|---|---|---|---|---|
| 1 | Materializacja runami zamiast 32 lookupów | 217–243 | ~2500–3000 T | niskie |
| 2 | Wskaźniki delty w rejestrach, nie w RAM | 266–297 | ~1200–1600 T | niskie |
| 3 | (opc.) Delta geometryczna zamiast bajt-po-bajcie | 245–308 | ~1500–1900 T | średnie |
| 4 | `gen_center_x`/`gen_half_x` w rejestrach, usunięcie `push/pop` | 66–214 | ~200–250 T | bardzo niskie |

Amortyzowany zysk z 1+2 (realistycznie): **~3700–4600 T/blok**, czyli przy
`speed=2` (blok co 4 ramki) **~900–1150 T/ramkę** odzyskane z budżetu
generatora, skumulowane na ramkach, które i tak są najcięższe. W ujęciu
ramki to ~1,3–1,6% budżetu 50 Hz — skromnie, ale punktowe piki generujące
blok są właśnie te, które najłatwiej łamią płynność.

## Sugerowana kolejność

1. **Punkt 1** jako pierwszy, samodzielny — biggest win, lokalna funkcja.
   Po niej: zrób build i sprawdź równoważność `block_bitmap_rows` względem
   starej wersji na kilku seedach (np. dump z `make` + skrypt porównujący
   BIN). Dopiero potem `make profile`.
2. **Punkt 2** — registeryzacja wskaźników w `rebuild_block_delta`, ta sama
   semantyka wyjścia.
3. **Punkt 4** — sprzątanie drobiazgów w `generate_block`.
4. **Punkt 3** opcjonalnie, jeśli profil po 1+2 nadal pokazuje generator
   jako gorącą plamę na ramkach z blokiem.

Po każdej zmianie: `make` + `git diff --check`; przy zmianach materiału
(wiersza) konieczne porównanie z referencją.

---

## 6. Alternatywa: biblioteka "gotowych elementów" (chunków)

Pytanie, czy zamiast generować teren proceduralnie, nie lepiej trzymać
**zapiekane elementy**. Oryginalne River Raid na Atari 2600 tak właśnie
robiło (tablica wzorców ścieżki `PPR`). W tej bazie kodu wariant ten ma
sens, ale z realistycznie skromnym zyskiem wydajnościowym — główną nagrodą
jest **kontrola projektowa**, nie szybkość.

### Dwa warianty "gotowych elementów"

**(A) Run-fill = minimalne pieczenie (opisane w §1).** Maski krawędzi są
już zapiekane (`left_edge_masks`, `right_edge_masks`); reszta wiersza to
trywialne runy ląd/woda/ląd. Nie dodaje pamięci ani ryzyka, daje ~80%
zysku generatora. To *też* rodzaj biblioteki elementów — najtańszy.

**(B) Chunki wieloblokowe w stylu Atari.** "Chunk" = sekwencja np. 8 bloków
z zapiekaną, per blok, pełną postacią:

- zmaterializowanym wierszem (32 B),
- geometrią: `left_col`/`left_mask`/`right_col`/`right_mask`/
  `island_left`/`island_right`,
- gotową listą delta `(col,value)` względem poprzednika.

Runtime to tylko `LDIR` z szablonu do pierścienia:

| | proceduralnie | z chunku |
|---|---|---|
| materializacja wiersza | ~3200 T | ~550 T (`LDIR` 32 B) |
| delta | ~2240 T | ~150 T (`LDIR` par, śr. 4 pary) |
| geometria (6 B do tabel) | ~300 T | ~80 T |
| **razem / blok** | **~6100 T** | **~800 T** |
| amortyzowane, `speed=2` | ~1535 T/ramkę | ~200 T/ramkę |

**Zysk ~5300 T/blok → ~1300 T/ramkę** zamortyzowane przy `speed=2`
(vs ~900–1150 T/ramkę z §1+§2 bez chunków).

Pamięć: ~576 B/chunk × 16 chunków ≈ **9 KB**. Binarka kończy się
~`0xBAF0`, `SP=0xff00` → ~17 KB wolnego — mieści się z zapasem.
`block_bitmap_rows` (1 KB) i `block_delta_ops` (1 KB) pozostają buforami
pierścieniowymi; chunk je tylko zasila.

### Szczere zastrzeżenia

1. **Zysk ramkowy jest skromny względem ryzyka.** Generator zamortyzowany
   to ~1,5–2% budżetu 50 Hz; chunki dają dodatkowe ~0,3–0,5% ramki ponad
   run-fill (§1), za cenę sporego redesignu.

2. **Wąskie gardło NIE jest w generatorze.** Pętla dirty
   (`render_dirty_rows`, ~9600–10600 T/ramkę wg README) scanuje wiersze co
   ramkę i chunki jej **nie dotykają**. Kolejność po zysku wydajności:
   `review-glm.md §1` (pętla dirty) → `review-glm-terrain.md §1` (run-fill)
   → chunki dopiero jako ostatnia warstwa.

3. **Prawdziwa nagroda za chunki to gameplay.** Kontrola nad terenem
   (uczciwe rozwidlenia, gwarantowane mosty, brak nudnych pasów),
   deterministyczna i testowalna — ta sama wartość, którą miał oryginał.
   Szybkość jest tu bonusem, nie celem samym w sobie.

4. **Przestrzeń stanów krawędzi:** maska ∈ 8 wartości, kolumna ∈ 0..31 →
   256 stanów na krawędź, 65 536 dla obu. Nie da się wypiec wszystkich.
   Ale proceduralny generator z `align`-owanym clampem i 16-wpisową
   `center_motion_table` osiąga tylko ich podzbiór — więc wystarczy
   kuratorska biblioteka, dokładnie jak w Atari.

### Hybryda bez utraty varietu

Chunki można **wygenerować automatycznie** z obecnego generatora:
uruchomić go offline (np. skryptem zakładającym `tools/build.py`), zdumpować
N-blokowe okna wraz z ich delta-listami i geometrią, zapisać jako stałą
tabelę w `state.asm`. Wtedy:

- identyczne wyjście jak dziś (ten sam algorytm, tylko zapieczony),
- zero ręcznego projektowania na start,
- można potem dogrywać ręczne chunki dla konkretnych miejsc (np. trudne
  rozwidlenie z mostem),
- łączenie chunków wymaga jednego proceduralnego delta-seamu na styku
  (jeden blok, ścieżką z §2/§3).

To usuwa główną obiekcję ("utrata varietu") — zachowujesz obecny charakter
terenu, tylko przyspieszasz jego produkcję z ~6100 T/blok do ~800 T/blok
plus ewentualny seam.

### Rekomendacja

- **Jeśli cel to tylko szybkość:** zrób §1 (run-fill) + §2 (rejestry w
  delcie). Proste, lokalne, ~80% zysku generatora, zero nowej pamięci.
- **Chunki bierz dopiero, gdy chcesz level design.** Wtedy zysk wydajności
  jest miłym efektem ubocznym, a nie uzasadnieniem samej zmiany. Start przez
  auto-dump z proceduralnego generatora (hybryda), ręczne chunki dograne
  później.
