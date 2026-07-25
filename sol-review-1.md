# Code review: główna pętla i hot path

Zakres: statyczny przegląd bieżącego kodu, ze szczególnym uwzględnieniem pełnej klatki gry, pocisku czołgu, pocisku gracza i rozmiaru playfieldu. Build profilujący (`make profile`) przechodzi, ale sam build nie daje pomiaru czasu wykonania; poniższe priorytety trzeba potwierdzić border-profilerem w emulatorze.

## Wnioski w skrócie

Najbardziej prawdopodobna przyczyna wrażenia, że gra zwalnia dokładnie po wystrzale czołgu, nie leży w czyszczeniu bitmapy. `resolve_fast_speed` wymusza `speed_pixels=1`, gdy `tank_shell_active != 0` (`src/input.asm:70-110`). Przy trzymanym Q świat przed strzałem porusza się naprzemiennie 1/2 px, czyli średnio 1,5 px/klatkę, a podczas lotu pocisku i dziesięcioklatkowego plusku zawsze 1 px/klatkę. To deterministyczny spadek prędkości scrolla o 33%, bardzo łatwy do odebrania jako spadek FPS.

Sprzątanie pocisku czołgu jest logicznie poprawne: stan starej klatki jest snapshotowany przed aktualizacją, `transition_shell_direct` przywraca tylko odsłoniętą część starego prostokąta, po czym rysuje nowy pocisk; przejście pocisk→plusk czyści cały stary ślad przed narysowaniem nowej reprezentacji (`src/sprite_renderer.asm:1839-1919`). Nie znalazłem przypadku pozostawiającego trwały ślad ani czyszczącego nową pozycję po jej narysowaniu.

## Ustalenia

### [P1] Aktywny pocisk czołgu sztucznie obniża prędkość gry

`tank_shell_active` jest jednym z warunków przejścia do `resolve_heavy_fast_speed`, które ustawia stałe 1 px/klatkę (`src/input.asm:70-110`). Obejmuje to również stan `2`, czyli animację plusku. Mechanizm ogranicza ciężkie klatki, ale dla pocisku czołgu koszt bitmapowy jest mały: lecący pocisk ma 2×2 px, porusza się o 4 px w poziomie i o najwyżej 1 px ze światem (`src/entities.asm:1082-1151`, `src/sprite_renderer.asm:854-879`). W efekcie ograniczenie prawdopodobnie kosztuje płynność bardziej, niż odzyskuje czas CPU.

Rekomendacja: najpierw usunąć wyłącznie test `tank_shell_active` z klasyfikacji ciężkiej sceny i zmierzyć najgorszą klatkę profilu przy jednoczesnym pocisku, czołgu oraz dwóch aktorach. Sam `tank_active` już obecnie wymusza ciężką ścieżkę, więc dla zwykłego czołgu usunięcie testu pocisku niczego nie zmieni, dopóki czołg jest na ekranie; różnicę da przede wszystkim pocisk, który przeżył czołg, oraz pocisk mostowy. Docelowo lepszym kryterium byłby budżet faktycznej pracy renderera, a nie sama obecność małego aktora.

Test rozstrzygający: porównać border przy Q w czterech scenach: bez czołgu, czołg bez pocisku, czołg+pocisk, sam pocisk po zejściu czołgu. Jednocześnie obserwować ruch brzegu. Jeśli szerokość bordera pozostaje bezpieczna, a brzeg zmienia tempo, diagnoza jest potwierdzona.

### [P1] Pocisk gracza wykonuje kosztowny test tła przez 10 wierszy w każdej aktywnej klatce

Po przesunięciu pocisku kod sprawdza do sześciu aktorów, a następnie zawsze bada swept interval wysokości 10 px. Dla każdego wiersza wywołuje dwa razy `get_world_background_byte` (`src/entities.asm:1573-1759`). To do 20 zapytań geometrii świata na klatkę pocisku, mimo że pocisk ma tylko dwa rzeczywiste piksele szerokości. Cache jest resetowany przed `update_bullet` (`src/entities.asm:22-24`), ale kolejne zapytania zmieniają Y, więc cache pojedynczego wiersza daje tu niewiele.

To nie tłumaczy wyłącznie pocisku czołgu, lecz jest wyraźniejszym hot spotem od jego sprzątania i może kumulować się, gdy oba pociski są aktywne.

Rekomendacja: testować swept path na poziomie bloków/odcinków brzegu zamiast materializować po dwa bajty dla wszystkich 10 Y. Ponieważ blok kursu ma 8 scanline'ów, odcinek 10 px przecina najwyżej trzy bloki. Można dla każdego przeciętego bloku policzyć kolizję maski raz i zachować osobne jawne testy mostu/drogi. Bezpieczniejszy pierwszy krok to dedykowana funkcja zwracająca dwubajtowe tło dla jednego Y jednym wyznaczeniem indeksu bloku, zamiast dwóch niezależnych wywołań.

### [P2] Lecący pocisk czołgu używa ogólnego, RAM-owego silnika różnic prostokątów

`transition_shell_direct` przechodzi przez `prepare_old_shell_geometry`, `prepare_new_shell_geometry` i `cleanup_resident_sprite_delta` (`src/sprite_renderer.asm:1839-1919`). Ogólny cleanup zapisuje geometrię do wielu zmiennych, osobno obsługuje pion i poziom, a `fill_water_rect_preserve_bridge` dla każdego czyszczonego wiersza ponownie sprawdza pas mostu (`src/sprite_renderer.asm:475-670`). Dla obiektu 2×2 poruszającego się zawsze o ±4 px jest to dużo sterowania względem 1–3 rzeczywiście odsłanianych bajtów.

Nie jest to błąd poprawności. Przy ruchu ukośnym ogólny algorytm może też odtworzyć narożnik dwa razy (raz jako odchodzący wiersz i raz jako odchodzącą kolumnę), co jest poprawne, lecz zbędne.

Rekomendacja: dopiero po pomiarze P1 dodać dedykowaną ścieżkę `transition_flying_shell`: odtworzyć stary prostokąt 1–2 bajty × 2 wiersze, po czym narysować nowe dwa wiersze. To najwyżej cztery odtworzone bajty i eliminuje cały algorytm przecięcia. Zachować obecną ogólną ścieżkę dla spawn/despawn oraz pocisk↔plusk. Jeszcze lepiej połączyć restore i draw per scanline, jeśli pomiar wykaże, że wywołania `calc_screen_line_addr` są istotne.

### [P2] Pełna główna pętla wywołuje wiele pustych procedur aktorów, ale renderer terenu pozostaje dominującym stałym kosztem

`update_entities` bezwarunkowo wywołuje jedenaście aktualizacji, potem compositor wszystkich rezydentnych sprite'ów i kolizję gracza (`src/entities.asm:5-29`). Większość nieaktywnych procedur szybko wraca, więc agregowanie ich bitmaską aktywności da raczej mały zysk i skomplikuje spawnowanie/timery. Nie zaczynałbym optymalizacji od tej listy.

Największy stały koszt przewijanej klatki to nadal `render_dirty_rows`: 19 wywołań `render_v3_row_delta_prepared` dla 1 px i 38 dla 2 px (`src/course_renderer.asm:711-778`). Główna pętla prawidłowo omija go przy `speed_pixels=0` (`src/main.asm:90-110`). Największe rezerwy będą więc w kodzie pojedynczego dirty row i w unikaniu niepotrzebnego drugiego residue, nie w kilku `call`/`ret` pustych aktorów.

Rekomendacja pomiarowa: dodać osobne kolory bordera dla: course advance+dirty rows, update logiki do `transition_all_resident_sprites`, compositor, atrybuty/HUD. Obecny marker całej klatki odpowiada na pytanie „czy się mieści”, lecz nie wskaże, który fragment rośnie po pojawieniu się pocisku.

### [P3] Zmniejszenie playfieldu o 8 px daje przewidywalny, ale niewielki zysk

Obecny zakres Y=16..167 ma 152 linie, dokładnie 19 wystąpień każdej klasy modulo 8. Obcięcie o 8 px zmniejszy dirty pass z 19 do 18 wierszy na residue, czyli o około 5,3% kosztu renderowania terenu (również 36 zamiast 38 w klatce 2 px). Obcięcie o 16 px da około 10,5%. To realny i stały zysk, ale raczej nie naprawa nagłego zwolnienia przy pocisku.

Jeżeli kadrować, najmniej inwazyjne wydaje się odjęcie jednego rzędu od dołu i przesunięcie gracza o 8 px w górę. Dodawanie trzeciego czarnego rzędu u góry wpływa na każdy spawn w Y=16, testy wejścia aktorów i aktywację czołgu mostowego. Dolna zmiana dotyka przede wszystkim `PLAYFIELD_BOTTOM`, pozycji gracza oraz progów despawnu, ale zmniejsza pionowy dystans reakcji. W obu wariantach trzeba przeszukać stałe literalne `16`, ponieważ nie wszystkie oznaczają początek playfieldu.

Rekomendacja: nie kadrować przed rozwiązaniem P1 i pomiarem segmentowym. Jeśli profil nadal nie mieści najgorszej klatki, zrobić osobny eksperyment z playfieldem 144 px (18 rzędów dirty), porównać zapas cykli oraz odczucie gry i dopiero wtedy zmienić layout/HUD.

## Ocena czyszczenia pocisków

- Pocisk gracza: przy ruchu o 6 px ogólny delta-cleanup odtwarza odchodzące wiersze starej pozycji i następnie zapisuje kompletne 4 nowe wiersze (`src/sprite_renderer.asm:1201-1235`). Despawn odtwarza cały stary prostokąt. Kolejność jest poprawna.
- Pocisk czołgu: przy locie cleanup uwzględnia zarówno zmianę X, jak i scroll Y; przy zmianie typu na plusk najpierw wymusza `transition_new_active=0`, dzięki czemu usuwa cały stary prostokąt, a potem rysuje plusk (`src/sprite_renderer.asm:1890-1919`). Despawn analogicznie usuwa stary ślad.
- `write_water_projectile_2xn` zapisuje maskę bez XOR, więc ponowne narysowanie nie kasuje pocisku (`src/sprite_renderer.asm:2766-2812`). Założenie „gwarantowana woda” jest utrzymywane przez wybór toru/targetu; podczas restore kod dodatkowo chroni aktywny most.
- Ryzyko dotyczy wydajności ogólnej ścieżki, nie widocznego ghostingu ani błędnej kolejności erase/draw.

## Proponowana kolejność prac

1. Rozdzielić profiler bordera na fazy i potwierdzić, czy problemem jest czas CPU, czy wyłącznie zmiana `speed_pixels`.
2. Eksperymentalnie wyjąć `tank_shell_active` z heavy-speed gate; zachować zmianę tylko przy bezpiecznym zapasie do 20 ms.
3. Zoptymalizować dziesięciowierszowy test tła pocisku gracza.
4. Jeśli nadal potrzebne: dedykowany transition lecącego pocisku czołgu.
5. Dopiero na końcu rozważyć playfield 144 px; daje około 5,3% mniej pracy terrain renderera.

## Weryfikacja

- `make profile`: sukces; istniejący artefakt profilujący był aktualny.
- `git diff --check`: sukces dla bieżącego drzewa przed dodaniem tego dokumentu.
- Emulator/profil wizualny nie został uruchomiony w ramach review, więc szacunki hot path są statyczne i wymagają pomiaru na emulowanym 48K.
