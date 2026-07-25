# Review szybkości rysowania pętli gry

Ogólnie: obecny renderer jest wolniejszy od najprostszego XOR-a w liczbie instrukcji na sprite, ale jest dużo lepiej zaprojektowany wizualnie i nadal mieści typową klatkę w budżecie 50 Hz. Nie widzę powodu, żeby wracać do klasycznego „XOR erase + XOR draw”. Jest natomiast kilka konkretnych miejsc do przyspieszenia.

## Ustalenia

### 1. Średni priorytet: błąd w ścieżce pojawiania się FUEL może uruchamiać niepotrzebne czyszczenie prostokąta

W `src/sprite_renderer.asm`, w `transition_fuel_exception`, jest:

```asm
transition_fuel_exception:
    xor a
    ld a,(timex_attr_fuel_active)
```

`xor a` nie zapisuje zera do `transition_old_width`. Gdy stare FUEL było nieaktywne, zmienna zachowuje szerokość ustawioną przez poprzedni obiekt. Następne `cleanup_resident_sprite_delta` może więc potraktować nieistniejący stary prostokąt jako istniejący.

Powinno być:

```asm
xor a
ld (transition_old_width),a
ld a,(timex_attr_fuel_active)
```

To przede wszystkim błąd stanu, ale może też generować kosztowne i zbędne naprawianie tła podczas spawnu FUEL.

### 2. Największy potencjał optymalizacji: poruszające się sprite’y nadal są zapisywane w całości

Dla przykładu FUEL przy przewijaniu:

- naprawia tylko 1–2 wychodzące wiersze,
- ale następnie zapisuje ponownie wszystkie 32 wiersze.

Widać to w `transition_fuel_direct`, szczególnie w skoku do `draw_current_fuel_direct`, który kończy w pełnym blitterze `write_water_sprite_1xn`.

To samo, choć dla mniejszych obiektów, dotyczy balonu, statków, śmigłowca i czołgu. To prawdopodobnie główny powód, dla którego prosty XOR może wygrywać w syntetycznym porównaniu.

Najbardziej obiecujący następny krok to wygenerowanie podczas startu masek przejścia pionowego:

```text
delta[row] = old_sprite[row + speed] XOR new_sprite[row]
```

Wtedy dla przesunięcia o 1 px część wspólna sprite’a byłaby aktualizowana gotową maską, a osobno naprawiany byłby tylko górny brzeg i rysowany dolny. To nadal nie wymaga widocznej fazy kasowania całego sprite’a, więc nie powinno przywrócić dawnego migania. Najpierw zastosowałbym to do FUEL i statycznego balonu, bo mają stałe X i najprostsze tło.

### 3. Średni potencjał: mieszany compositor wykonuje dużo operacji przez RAM dla każdego wiersza

`write_world_sprite_shifted_2xn` dla każdego wiersza:

- wywołuje `load_world_background_triplet`,
- wielokrotnie zapisuje i odczytuje `world_write_byte_*`,
- ponownie wywołuje `calc_screen_line_addr`,
- utrzymuje liczniki i wskaźniki w pamięci.

To poprawne, ale kosztowne na Z80. W szczególności samolot przelatujący nad mieszanym terenem płaci ten koszt dla wszystkich ośmiu wierszy.

Dałoby się przygotować wyspecjalizowane warianty:

- bez mostu, będący przypadkiem częstym,
- dla shiftu zero,
- dla sprite’a bez trzeciego bajtu,
- z bieżącym wskaźnikiem źródła i licznikami trzymanymi w rejestrach.

Tu możliwy jest zauważalny zysk, lecz kosztem większego kodu.

### 4. Niski/średni potencjał: dirty renderer ponownie wylicza adres ekranu dla każdego z 19 wierszy

W `render_dirty_rows` wiersze są odwiedzane co dokładnie 8 pikseli, ale każdy `render_v3_row_delta` wywołuje `calc_screen_line_addr`.

Ponieważ istnieje już tablica adresów linii, pętla mogłaby utrzymywać wskaźnik do `screen_line_table` i przesuwać go o 16 bajtów na kolejny Y+8. Odpadałoby wywołanie funkcji i część komunikacji przez `dirty_y`. To nie da rewolucji, ale ścieżka wykonuje się 19 albo 38 razy na klatkę, więc jest dobrym celem mikrooptymalizacji.

### 5. Niski potencjał: pełny snapshot wykonywany jest zawsze

`snapshot_resident_sprite_state` kopiuje stan wszystkich obiektów co klatkę, również nieaktywnych. Następnie `transition_all_resident_sprites` wywołuje wszystkie procedury przejścia.

To nie jest główne wąskie gardło, ale można:

- osobno kopiować mały, zawsze potrzebny stan,
- snapshotować aktywne grupy,
- połączyć snapshot z aktualizacją konkretnego obiektu.

Spodziewałbym się oszczędności rzędu setek, nie tysięcy T-state na klatkę.

## Ocena względem XOR-a

Poprzednia recenzja mogła mieć rację tylko w wąskim sensie: klasyczny XOR wykonuje zwykle bardzo prosty odczyt–XOR–zapis, a obecny kod rekonstruuje tło i zapisuje finalny obraz. XOR może więc być szybszy w benchmarku samego sprite’a.

Obecna konstrukcja ma jednak istotne zalety:

- teren aktualizuje tylko 19/38 scanline’ów, nie cały ekran;
- przesunięte sprite’y są buforowane podczas startu;
- gracz stojący bez ruchu naprawia tylko dirty rows;
- obiekty nie znikają na całą wyświetlaną klatkę;
- ciężkie klatki ograniczają szybkie przewijanie.

Według obecnych pomiarów zapisanych w README zwykłe klatki kosztują około 31–60 tys. T-state przy budżecie 69 888. To oznacza, że typowa klatka mieści się w 50 Hz, choć margines dla najcięższych scen jest mały.

`make profile` i `git diff --check` przechodzą poprawnie. Target `profile` tylko buduje wersję z markerem borderu — bez uruchomienia emulatora nie generuje nowych danych czasowych.

## Zalecana kolejność prac

1. Naprawić brak zerowania `transition_old_width`.
2. Dodać pomiar osobnych sekcji: terrain, transitions, attributes i gameplay.
3. Zrobić pionowe maski delta najpierw dla 32-wierszowego FUEL.
4. Zoptymalizować iterację dirty rows po tablicy adresów.
5. Dopiero potem specjalizować mixed-terrain compositor.

Największą szansę na realny zysk bez powrotu migania daje punkt 3: delta rezydentnego sprite’a, a nie ponowne pełne rysowanie ani klasyczne dwufazowe kasowanie XOR-em.
