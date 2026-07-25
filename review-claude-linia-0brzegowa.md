# Linia brzegowa — czy rysujemy tylko to, co trzeba?

Analiza ścieżki aktualizacji brzegów rzeki w `render_dirty_rows`. Uzupełnienie
do `review-render-loop.md` (§3 i §4 tamtego dokumentu).

**Krótka odpowiedź: tak, na poziomie bajtów jest to minimalne i nie ma tu czego
poprawiać. Cały problem jest w narzucie na dostarczenie tych bajtów, nie w ich
liczbie.**

---

## 1. Nie ma osobnej fazy kasowania

`rebuild_block_delta` (`src/course_renderer.asm:245`) porównuje bajt po bajcie
zmaterializowany 32-bajtowy wiersz bloku `i` z wierszem bloku `i-1` i zapisuje
parę `(kolumna, wartość)` **wyłącznie dla bajtów, które faktycznie się różnią**.

„Zgaś ląd" i „zapal ląd" to ta sama operacja — jeden zapis nowej wartości.
Nie istnieje krok kasowania, który trzeba by później cofać. Na poziomie bajtów
nie da się tego zrobić taniej; niżej byłaby już granulacja bitowa, a Z80 i tak
zapisuje całymi bajtami.

## 2. Ile bajtów realnie kosztuje przesunięcie brzegu

Ciekawe jest to, że **przekroczenie granicy bajtu nic nie kosztuje**, bo maska
skrajnej kolumny i sąsiedni bajt „mijają się" idealnie:

| sytuacja | stary stan | nowy stan | zapisy |
|---|---|---|---:|
| `x&7 ≥ 1`, brzeg cofa się o 1 px | kol. `c` = maska | kol. `c` = maska bez bitu | **1** |
| `x&7 = 0`, brzeg cofa się o 1 px | kol. `c-1` = `0xff`, kol. `c` = `0x00` | kol. `c-1` = `0xfe`, kol. `c` = woda `0x00` | **1** |
| `x&7 ≤ 5`, brzeg rośnie o 1–2 px | kol. `c` = maska | kol. `c` = maska z bitem | **1** |
| `x&7 = 6`, brzeg rośnie o 2 px | kol. `c` = `0xfc` | kol. `c` = `0xff`, kol. `c+1` = maska `0x00` (już woda) | **1** |
| `x&7 = 7`, brzeg rośnie o 2 px | kol. `c` = `0xfe` | kol. `c` = `0xff`, kol. `c+1` = `0x80` | **2** |

Czyli **1 bajt na brzeg** przy ruchu o 1 px i 1–2 przy 2 px. Razem z wyspą daje
to typowo **2–4 zapisy na brudny wiersz**, ~76 bajtów na całą ramkę przy 1 px.

Dla porównania ścieżka zapasowa `render_v3_row_indexed`
(`src/course_renderer.asm:727`) pisze **bezwarunkowo 6 bajtów** —
`left_col-1` = `0xff`, maska, `left_col+1` = `0x00` i symetrycznie z prawej —
niezależnie od tego, czy cokolwiek się zmieniło. Delta jest ~3× oszczędniejsza.

Blok całkowicie statyczny ma dodatkowo early-out (`count == 0` → `or a / ret z`).
Tabela ruchu daje `dL = dR = 0` w 2/16 wpisów, a wybrany ruch trzyma się
4–7 bloków, więc trafia się to realnie.

---

## 3. Trzy rzeczy, które mimo to warto poprawić

### 3.1 Narzut 390 T na dostarczenie 2 bajtów

To jest sedno i jednocześnie §3 głównego raportu. Sama pętla delty to 62 T na
zapisany bajt, ale wokół niej stoi ~390 T na wiersz: `call
calc_screen_line_addr` (73 T), `call block_delta_address` z `push/pop bc`
(118 T) i bookkeeping `dirty_y` / `row_block_index` przez RAM (113 T).

Skutek uboczny: **nawet early-out dla statycznego bloku kosztuje ~145 T**, bo
żeby w ogóle przeczytać `count`, trzeba najpierw policzyć adres rekordu.
Po przepisaniu wg §3 ten sam early-out kosztowałby ~30 T.

### 3.2 Ścieżka `count = 255` jest praktycznie nieosiągalna

Ruch brzegu jest ograniczony do ±2 px na blok, więc każdy brzeg wnosi ≤2
zapisy, a wyspa (`fork_widths`, max 4 bajty) ≤8. Maksimum to ~12 zmian przy
progu 16 (`src/course_renderer.asm:280`).

Wniosek praktyczny: **~190 linii obsługi wyspy w `render_v3_row_indexed`
(`src/course_renderer.asm:783-969`) jest na gorącej ścieżce martwe.**
`dirty_shift_island_left/right`, `dirty_island_left_edges`,
`dirty_write_island_run` wykonują się wyłącznie przez `render_v3_row` przy
naprawie mostu, czyli 1–2 razy na ramkę i tylko gdy most jest aktywny. To
skomplikowana logika przypadków, którą trzeba utrzymywać dla ścieżki zimnej.

Przy okazji: limit można bezpiecznie obniżyć z 16 na 15 par — to jest dokładnie
to, czego potrzebuje §3, żeby scalić `block_delta_count` z `block_delta_ops`
w jeden 32-bajtowy rekord `[count][Δcol,val]…` obsługiwany jednym wskaźnikiem.

### 3.3 Wiersze pod mostem — potrójny przebieg i podejrzenie dziury w przęśle

⚠️ **Hipoteza z lektury kodu, nie z pomiaru — do sprawdzenia w emulatorze.**

Kolejność w ramce: `render_dirty_rows` (`src/main.asm:97`) → dopiero potem
`update_entities` → `update_bridge`. Dla wiersza pod mostem oznacza to trzy
przebiegi po tym samym miejscu:

1. delta terenu wpisuje bajty brzegu (także wewnątrz przęsła),
2. `bridge_fill_rows` nadpisuje pas mostu,
3. `bridge_refresh_edges` łata **tylko 4 bajty**: `bridge_col`, `bridge_col+1`
   oraz dwa ostatnie (`src/sprite_renderer.asm:2912`).

Problem: `bridge_col` i `bridge_width` są ustawiane **jednorazowo**, przy
powstaniu mostu (`src/entities.asm:1220`, `:1225`), a rzeka pod nim dalej
meandruje. Most żyje na ekranie ~150 ramek, czyli ~19 bloków; przy |dL| ≤ 2 px
na blok brzeg może zdryfować kilka bajtów.

Gdy aktualny `left_col` wejdzie **głębiej niż 2 bajty** w przęsło, delta terenu
wpisze tam bajt wody `0x00`, a `bridge_refresh_edges` go nie dosięgnie.
W brązowych komórkach mostu (`0x0a`, INK ciemnoczerwony / PAPER niebieski)
bajt `0x00` to samo PAPER, czyli **niebieskie wycięcie w przęśle** — i nic go
później nie odmaluje, bo `bridge_fill_rows` dotyka wyłącznie wierszy
wchodzących i schodzących. Most byłby zjadany po 1–2 linie na ramkę.

Ta sama zamrożona geometria dotyczy naprawy góry mostu: `bridge_restore_top`
czyści pas `bridge_col..bridge_col+width-1` i woła `render_v3_row`, który maluje
tylko po 3 bajty wokół każdego brzegu. Jeśli aktualny brzeg jest poza starym
przęsłem, wyczyszczony ląd nie zostanie odtworzony.

**Jak sprawdzić:** długi most na wyraźnym zakręcie rzeki, `make run`, obserwować
przęsło przez cały jego przejazd przez ekran.

**Jeśli się potwierdzi:** najprostsza poprawka to kazać `bridge_refresh_edges`
odtworzyć **całe przęsło** dla tych 2×`speed_pixels` wierszy, które i tak
tyka delta — ~50 zapisów ≈ 600 T/ramkę, akceptowalne i odporne na dryf.
Alternatywa (tańsza, ale bardziej inwazyjna) to aktualizować `bridge_col`
i `bridge_width` wraz ze scrollem, co jednak zmienia geometrię kolizji
i drogi dojazdowej, więc nie jest to zmiana czysto renderowa.

---

## Podsumowanie

| Aspekt | Ocena |
|---|---|
| liczba zapisanych bajtów | **optymalna** — dokładnie te, które się różnią |
| obsługa granicy bajtu | **optymalna** — przekroczenie nie kosztuje dodatkowego zapisu |
| osobna faza kasowania | **nie istnieje** — i słusznie |
| pominięcie statycznych bloków | **jest**, ale kosztuje 145 T zamiast 30 T |
| koszt dostarczenia bajtu | **~195 T/bajt zamiast ~60 T** — tu jest cały zysk (§3) |
| kod obsługi wyspy | zimny, ~190 linii utrzymywanych dla ścieżki zapasowej |
| interakcja z mostem | podejrzenie realnej dziury w przęśle przy dryfie brzegu |
