# Review głównej pętli — analiza wydajności `main_loop`

Świeży przegląd gorącej ścieżki w `src/main.asm` i wywoływanych z niej
modułów (`course_renderer.asm`, `sprite_renderer.asm`, `entities.asm`,
`input.asm`). Liczby to **statyczne zliczenia T-stanów Z80** (3,5 MHz),
nie pomiary emulatora — ostatecznym arbiterem pozostaje `make profile`.
Budżet ramki 48K: **69 888 T**.

## Stan istniejących optymalizacji

Zanim przejdę do wniosków — potwierdzam, co z poprzednich review już
żyje w kodzie i działa:

- **Prekomputowana delta bloku** (`rebuild_block_delta`,
  `course_renderer.asm:245`) + odtwarzanie listy `(col,value)` w
  `render_v3_row_delta` (`course_renderer.asm:693`). Pętla dirty nie
  powtarza już porównań banków — to ~41 T na zmieniony bajt.
- **Przyrostowy adres atrybutu** w generycznym `paint_object_attribute_cells`
  (`main.asm:1023`, krok `add hl,de` z `de=32`) oraz w `paint_fuel_attributes`
  (`main.asm:706`).
- **Cache przesunięć sprite'ów** budowany raz w `init_shifted_sprites`;
  blitery konsumują gotowe 3-bajtowe wiersze bez rotacji.
- **Trik `SP → screen_line_table` + `POP HL`** w bliterach omija
  `calc_screen_line_addr` w wewnętrznej pętli rysowania.
- **`background_cache_y`** eliminuje powtórne lookupy bloków w zapytaniach
  o tło w obrębie ramki.

Poniższe punkty dotyczą tego, co **nadal** wisi na pętli.

---

## 1. Per-row overhead w pętli dirty — adres linii i wskaźnik delty

`render_dirty_rows` (`course_renderer.asm:642`) woła `render_v3_row_delta`
dla 22 wierszy przy `speed=1` (38 przy `speed=2`). Część stała każdego
wiersza (poza samym odtwarzaniem bajtów) to ~215 T:

| Składnik | Koszt | Uwaga |
|---|---|---|
| `calc_screen_line_addr` z `ld a,(dirty_y)` | ~86 T | `course_renderer.asm:707`, `1086` |
| `block_delta_address` (call + ciało) | ~97 T | `course_renderer.asm:367` — rekalkulowane z indeksu |
| round-tripy `row_block_index`, `dirty_y` przez RAM | ~32 T | |

Adres bitmapy Spectrum dla `Y` i `Y+8`: w obrębie trzecia ekranu to
`L += 32`, przy zawinięciu `H += 8`. Kolejne dirty-wiersze dzieli dokładnie
8 linii, a `row_block_index` w `dirty_row_loop` już maleje o 1 z iteracją.

**Propozycja:** trzymać bazę wiersza w parze rejestrów (np. `BC`) przez
całą pętlę `dirty_row_loop`; krok do następnego wiersza to:

```asm
ld a,c
add a,32           ; 7
ld c,a             ; 4
jr nc,addr_ok      ; 7
ld a,b
add a,8            ; 7
ld b,a             ; 4
addr_ok:
```

≈ 18 T zamiast 86 T. Analogicznie wskaźnik listy delty w `block_delta_ops`
kolejnego bloku leży o `-16` bajtów (z zawinięciem strony co 8 bloków).

**Szacowany zysk:** ~70 T/wiersz × 22–38 wierszy = **~1500–2700 T/ramkę**
(~2–4%). Niskie ryzyko — czysto lokalna zmiana jednej pętli.

## 2. `DI`/`EI` + zapis `SP` per blit, zamiast per faza

Każdy blit robi własną sekwencję
`di` / `ld (sprite_saved_sp),sp` / `ld sp,hl` … `ld sp,(sprite_saved_sp)` / `ei`
(~58 T narzutu poza pracą). Przykładowe miejsca:

- `xor_sprite_shifted_2xn` (`sprite_renderer.asm:1977`) — eksplozje,
- `fill_uniform_sprite_rect` (`sprite_renderer.asm:2042`) — czyszczenie
  odchodzących wierszy wszystkich aktorów,
- `write_water_sprite_2xn` / `_shifted_2xn` / `_shifted_4xn`
  (`sprite_renderer.asm:2350`, `2454`, `2521`),
- `write_land_sprite_2xn` (`2392`), `write_water_sprite_1xn` (`2313`),
- `write_intact_bridge_tank_shifted_2xn` (`2601`),
- `bridge_fill_rows` (`2919`).

W typowej ramce `transition_all_resident_sprites` woła tych bliterów
kilkanaście razy (clear-top + draw dla każdego ruchomego aktora + most).
Narzut ~15 × 58 ≈ **~870 T/ramkę**, a przy mostku i dwóch statkach bywa
więcej.

**Propozycja:** otoczyć cały blok `transition_all_resident_sprites` (i ew.
`advance_active_bridge`) jednym `DI` na wejściu i jednym `EI` na wyjściu;
`SP` zapisać/przywrócić raz. Pojedyncze blitery przestają dotykać `SP`/`DI`.
Przerwanie ROM wyzwala się spod `HALT` na początku ramki, a kolejne
pojawi się dopiero za ~20 ms — więc praca z wyłączonymi przerwaniami przez
całą fazę rysowania jest bezpieczna, o ile AY/klawiaturę obsłużymo poza nią
(tak jest dziś: `read_keyboard` i `update_ay_sound` lecą przed fazą rysowania).

**Haczyk:** zdarzenia typu `start_tank_shot_sound` / `start_ay_explosion`
wyzwalane z `update_entities` piszą do AY — `out (c),a` jest poprawne pod
`DI`. Trzeba tylko zachować sekwencję: `HALT` → wczytanie klawiatury/AY →
`DI` → faza rysowania → `EI` → `HALT`.

**Szacowany zysk:** **~600–1000 T/ramkę** (~1–1,5%) oraz mniej szumu
na magistrali. Niskie ryzyko, wymaga jednorazowej refaktoryzacji bliterów.

## 3. `paint_balloon_attribute_row` przebudowuje adres co wiersz

`paint_balloon_attribute_row` (`main.asm:754`) liczy adres komórki atrybutu
od zera w każdej iteracji (`rrca×3`, `srl×3`, `add a,0x58`, … ≈ 40 T),
podczas gdy kolejny wiersz to po prostu **+32**. Helikopter, czołg i fuel
korzystają już z generycznego, przyrostowego malacza — balon jest wyjątkiem.

**Szacowany zysk:** ~30 T/wiersz × ~3–4 wiersze × 2 przebiegi (restore +
paint, gdy balon się przesuwa) ≈ **~200–250 T/ramkę** w ramkach z aktywnym
balonem. Trywialna, lokalna zmiana.

## 4. `check_player_background_pixels` — lookup bloku w każdym z 6 wierszy

`check_player_background_pixels` (`entities.asm:2412`) biega **co ramkę**
dla 6 wierszy rdzenia gracza i w każdym woła `get_block_index_for_y`
(~30 T, `course_renderer.asm:976`). Rdzeń ma wysokość 6 pikseli, więc
przekracza granicę bloku (8 linii) najwyżej raz.

**Propozycja:** policzyć `block_index` z `player_core_y` jeden raz, a w
pętli inkrementować licznik wewnątrzblokowy; przy zawinięciu (co najwyżej
jedno na ramkę) zdekrementować indeks pierścienia. Zysk ~20–25 T × 6 =**

~120–150 T/ramkę**, plus oszczędność na powtarzanych odczytach
`block_left_x` / `block_right_x` / `block_island_*` z tej samej strony.
Niskie ryzyko, umiarkowany zysk — punkt wart załatwienia przy okazji
innych zmian w `entities.asm`.

## 5. Darmowe drobiazgi (kompilacja warunkowa + martwy OUT)

- **`profile_begin`/`profile_end` wołane bezwarunkowo**
  (`input.asm:202`, wołane z `main.asm:74,81,110,114,1119,1145,1149`).
  Przy `PROFILE_BORDER=0` to nadal `call`+`ld a,(profile_enabled)`+`or a`+
  `ret z`+`ret` ≈ 45 T na wywołanie, 2–3× na ramkę. Otoczyć makrem
  `#if PROFILE_BORDER` — zysk **~100–150 T/ramkę** za darmo.

- **`xor a` + `out (0xfe),a` na początku `main_loop`** (`main.asm:59`):
  przy wyłączonym profilingu border i tak jest cały czas czarny
  (ustawiony przy starcie / przez ostatnie `profile_end`). Możesz warunkować
  razem z powyższym. **~15 T/ramkę**.

- **`advance_frame_samples`** (`main.asm:91`): pętla `push bc/call/pop bc/
  djnz` wołająca `advance_course_sample`, które 7 na 8 wywołań robi tylko
  `inc a/and 7/ret nz`. `speed_pixels ∈ {1,2}`, więc maksymalnie 2 iteracje.
  Inlinowanie (dla `speed=1` bez pętli, dla `speed=2` dwa razy sekwencyjnie)
  oszczędza ~50 T/ramkę. Kosmetyka.

## 6. O czym warto wiedzieć, ale **nie** ruszać

Zrzucam tu rzeczy, które po analizie uważam za już uzasadnione — żeby
kolejny review nie otwierał ich na nowo:

- **Pełne przerysowanie ruchomych sprite'ów co ramkę** (`transition_*_direct`
  → `draw_current_*_direct`). Choć statki przesuwają się tylko o 1 px w dół,
  treść każdego z 8 wierszy zmienia się (kolejny wiersz sprite'a ląduje na tym
  samym wierszu ekranu). Screen-to-screen copy w dół na przeplotanej bitmapie
  Spectrum byłoby droższe i bardziej ryzykowne niż dzisiejszy odczyt z cache.
- **`snapshot_resident_sprite_state`** (`sprite_renderer.asm:137`) — ~30
  kopii bajtów (~780 T/ramkę). Wygląda jak łatwy cel, ale każda z tych
  wartości jest konsumowana przez logikę przejść; warunkowanie po
  `*_active` dodałoby ~30 gałęzi, jedząc większość zysku.
- **`STANDARD_ATTR_CHANGED` × 4** (`main.asm:149`) — długa sekwencja
  porównań, ale to early-out chroniący przed pełnym przemalowaniem atrybutów
  czterech obiektów. Gdy nic się nie rusza, kończy się na ~520 T/ramkę —
  tania cena za to, co oszczędza.
- **Podwójne XOR eksplozji trafień** (`restore_frame_entities` +
  `draw_frame_entities`, gdy `hit_explosion_active`) — wymagane: efekt
  scrolluje się ze światem, więc pozycja zmienia się co ramkę. Krótkie
  (~15 ramek) i akceptowalne.

---

## Tabela priorytetów

| Prio | Zmiana | Lokalizacja | Szacowany zysk | Ryzyko |
|---|---|---|---|---|
| 1 | Przyrostowy adres linii + wskaźnik delty w pętli dirty | `course_renderer.asm:642`, `693`, `367` | ~1500–2700 T (~2–4%) | niskie |
| 2 | Raz `DI`/`EI` i zapis `SP` na fazę rysowania | `sprite_renderer.asm` (blitery), `entities.asm:28` | ~600–1000 T (~1–1,5%) | niskie/średnie |
| 3 | Przyrostowy adres w `paint_balloon_attribute_row` | `main.asm:754` | ~200–250 T | bardzo niskie |
| 4 | Inkrementalny indeks bloku w `check_player_background_pixels` | `entities.asm:2412` | ~120–150 T | niskie |
| 5 | `#if PROFILE_BORDER` + usunięcie martwego `out (0xfe)` | `main.asm:59`, `input.asm:202` | ~100–150 T | zerowe |

Łączny realistyczny zysk z punktów 1–5: **~2,5–4 tys. T/ramkę**, czyli
**~3,5–6%** budżetu 50 Hz, głównie w ciężkich ramkach (scroll + most),
które są najbardziej narażone na dropy.

## Sugerowana kolejność

1. **Punkt 5** — czysty zysk, brak ryzyka, dobry warm-up commit.
2. **Punkt 3** — mały, samodzielny, łatwy do zweryfikowania na `make profile`.
3. **Punkt 1** — największy pojedynczy zysk; zmiana jednej pętli, po niej
   odpalić `make profile` i porównać border zRekordowaniem ramki z aktywnym
   scrollem.
4. **Punkt 2** — refaktoryzacja bliterów; robić po punkcie 1, żeby profil
   pokazywał udział samych bliterów bez bałaganu z pętlą dirty.
5. **Punkt 4** — przy okazji, jeśli `entities.asm` jest otwarty.

Po każdej zmianie: `make` (lub `make profile`) + `git diff --check`.
