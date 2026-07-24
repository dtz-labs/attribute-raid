# Attribute Raid — renderer V3

Prototyp gry w stylu River Raid dla ZX Spectrum 48K. Kod wykonywany na
Spectrum jest napisany w dobrze komentowanym assemblerze Z80. Nie ma kodu C.

V3 świadomie zbliża geometrię do wersji Atari 2600: brzegi są zbudowane z
dużych, schodkowych fragmentów, ale przewijają się płynnie co jeden piksel.
Bitmapa ekranu nigdy nie jest kopiowana ani przewijana. Renderer zmienia tylko
linie, które właśnie przekroczyły granicę bloku świata. Sprite'y są usuwane i
rysowane przez XOR, a szeroki most jest utrzymywany przyrostowo.

To nadal prototyp, nie kompletna gra, ale ma już podstawową pętlę rozgrywki:
sterowanie samolotem, dwa biegi, pocisk, zderzenia, dwa życia, animację
eksplozji oraz ekran `GAME OVER`. Nie ma jeszcze paliwa, punktów, dźwięku ani
logiki pełnych poziomów.

## Budowanie i uruchamianie

```sh
make
make run
```

Wynik powstaje jako `build/attribute-raid.tap`. Pozostałe cele:

```sh
make profile      # border pokazuje czas pełnej aktualizacji gry
make run-profile
make clean
```

Program startuje od `32768` (`0x8000`). `tools/build.py` jest małym assemblerem
używanego podzbioru Z80 oraz generatorem loadera BASIC i pliku TAP, więc
repozytorium nie wymaga zewnętrznego toolchainu Z80.

## Sterowanie

- `O` / `P` — samolot gracza w lewo / w prawo (2 px/klatkę),
- bez klawisza prędkości — bieg bazowy (1 px/klatkę),
- przytrzymane `Q` — chwilowo szybciej (2 px/klatkę),
- przytrzymane `A` — chwilowo wolniej (średnio 0,5 px/klatkę),
- `SPACE` — strzał,
- `R` — rozpoczęcie nowej gry z dwoma życiami i nową trasą.

Kempston joystick obsługuje lewo/prawo, FIRE oraz chwilową zmianę prędkości:
wychylenie w górę odpowiada `Q`, a w dół odpowiada `A`. Cel `make run`
uruchamia ZEsarUX z emulacją Kempstona. Po utracie drugiego życia `SPACE` lub
FIRE rozpoczyna nową grę; najpierw trzeba puścić przycisk, aby przypadkowo nie
pominąć ekranu `GAME OVER`.

## Model V3

Jeden blok trasy ma osiem linii świata. Położenie obu brzegów jest wyrażone w
jednostkach czterech pikseli, co daje charakterystyczne duże schodki. Generator
utrzymuje ten sam ruch brzegu przez 5–12 bloków, czyli 40–96 linii. Długie
proste i stałe skosy są dzięki temu częstsze niż drobny losowy zygzak. Taki
odcinek można później skompresować do pary `długość + krok`.

32 bloki tworzą pierścień. Sześć wyrównanych do stron tablic przechowuje:

- kolumnę i maskę lewego brzegu,
- kolumnę i maskę prawego brzegu,
- opcjonalny lewy i prawy koniec wyspy.

Wyspa jest trzecim przedziałem lądu wewnątrz rzeki. Rośnie przez kolejne bloki,
utrzymuje szerokość i zwęża się, tworząc prawdziwe rozwidlenie bez drugiego
renderera ani bufora ekranu. Most pozostał osobnym obiektem, dobiera szerokość
do aktualnego koryta i ma 16 scanline'ów wysokości.

Po każdej próbce przewinięcia zmienia się tylko jedna ósma linii ekranu.
Renderer aktualizuje więc:

- 24 linie przy 1 px/klatkę,
- 48 linii przy 2 px/klatkę.

Na każdej takiej linii zapisuje trzy bajty lewego brzegu, trzy prawego oraz —
tylko podczas rozwidlenia — krótki przedział wyspy. Pełne 6144 bajty bitmapy są
rysowane wyłącznie przy starcie i po `R`.

## Kolor, most i sprite'y

Normalne komórki atrybutów mają wartość `0x4c`: BRIGHT 1, zielony INK i
niebieski PAPER. Bit `1` bitmapy oznacza ląd lub obiekt, a bit `0` wodę. Most
czasowo przełącza zajmowane komórki na `0x0a`, czyli ciemny czerwono-brązowy
INK na niebieskim tle. Oryginalny Spectrum nie ma osobnej barwy brązowej;
ciemna czerwień jest tutaj najbliższym czystym kolorem bez ditheringu.

Most także jest bitmapą, dlatego może zaczynać się na dowolnym Y i przesuwać
płynnie o jeden piksel. Standardowe atrybuty ZX Spectrum są przywiązane do
siatki 8×8, więc kolor obejmuje dwie lub trzy całe komórki i zmienia zasięg
co osiem linii. Bitmapa mostu nadal porusza się co piksel. Renderer aktualizuje
tylko jeden wchodzący lub wychodzący rząd atrybutów, zamiast przemalowywać
cały prostokąt. Tryb Timex hi-colour nie jest wymagany.

Sylwetki gracza, statku, poprzecznego samolotu i helikoptera zostały
zrekonstruowane z przeplatanych danych obiektów oryginalnego River Raid na
Atari 2600 i rozszerzone poziomo 2×. Źródłem porównawczym był publiczny
[dekompilat River Raid](https://gitlab.com/menelkir/atari-2600/-/blob/master/River%20Raid%20%28decomp%29.asm).
Czołg jest nową sylwetką narysowaną według tych samych ograniczeń 8-bitowego
wzoru rozszerzanego 2×.

Kolejność wierszy helikoptera i poprzecznego samolotu została dodatkowo
sprawdzona na zrzutach Atari 2600; wcześniejsza tabela zamieniała parami
wiersze pochodzące z przeplatanego obrazu. Helikopter używa białego INK na
niebieskim PAPER. Atari mogło zmieniać kolor obiektu co scanline, natomiast
Spectrum ma jeden zestaw kolorów na komórkę 8×8, dlatego dokładne czarno-białe
pasy wymagałyby widocznego prostokąta attribute clash.

Aktualna scena zawiera:

- samolot gracza sterowany klawiszami `O` / `P`,
- dwa statki: jeden pozostaje nieruchomy w osi X, drugi patroluje z prędkością
  jednego rzeczywistego piksela co dwie klatki,
- samolot przelatujący przez całe 256 pikseli z prędkością 3 px/klatkę; jego Y
  przesuwa się razem z trasą, więc pozostaje na tej samej linii świata,
- helikopter, którego kolejne pojawienia naprzemiennie stoją lub patrolują po
  jednym pikselu na klatkę,
- okresowy czołg na lewym albo prawym brzegu,
- okresowy most i rozwidlenie.

Domki i drzewa są celowo wyłączone w tej wersji.

Ruchome sprite'y są nakładane przez XOR. Blitter obsługuje dowolne przesunięcie
bitowe, więc ruch 1–3 px nie jest serią skoków o pełne osiem pikseli. Osiem
wariantów przesunięcia każdego kształtu powstaje raz przy starcie w pamięci
RAM; czas rysowania nie zależy już od `X & 7`. Statek i helikopter pobierają
granice aktualnej odnogi; podczas rozwidlenia wyspa działa dla nich jak drugi
brzeg i wymusza zawrócenie. Na czas kilku linii sprite'a rejestr `SP` wskazuje
tabelę adresów scanline'ów; kolejne `POP HL` omijają koszt wyliczania
przeplatanej adresacji bitmapy Spectrum.

Most nie jest kasowany w całości. Co klatkę odtwarzane są tylko 1–2 linie
opuszczających jego górę, dopisywane są nowe linie na dole, a cztery bajty przy
brzegach są odświeżane po rendererze rzeki. Dzięki temu 16-pikselowa grubość
nie wymaga dwóch pełnych przebiegów po całym prostokącie.

Kolizja brzegu nie korzysta już z prostokątnych granic odnogi. Wszystkie
nieprzezroczyste piksele maski samolotu 16×13 są porównywane z faktyczną
bitmapą: ustawiony bit oznacza brzeg, wyspę albo nienaruszony most. Dzięki temu
przezroczyste narożniki sprite'a nie zabijają przed zetknięciem z lądem, a obie
strony wyspy działają identycznie. Osobny, łagodniejszy rdzeń 6×6 wykrywa
zderzenia ze statkami, helikopterem, poprzecznym samolotem i czołgiem.

Gracz zaczyna z dwoma życiami, pokazanymi jako małe ikony w lewym górnym
rogu. Po kolizji samolot zastępuje trzyklatkowa eksplozja, a rzeka i pozostałe
obiekty zatrzymują się na 75 klatek, czyli około 1,5 sekundy przy 50 Hz. Po
pierwszym zgonie trasa startuje od nowa z jednym życiem; po drugim pojawia się
osobny ekran `GAME OVER`.

Pocisk leci w górę i może zniszczyć most. Statki oraz helikopter są odsuwane
poza pionowy pas mostu i nie mogą przez niego przepłynąć; czołg celowo nie
podlega tej regule i może znajdować się na brzegu na tej samej wysokości co
most.

## Zweryfikowany budżet

Pomiary wykonane protokołem debuggera ZEsarUX dla Spectrum 48K, na szybkim
biegu 2 px/klatkę:

- 65 223 takty w ciężkiej klatce z aktywnym mostem i wszystkimi
  sprite'ami,
- 61 582 takty przy wymuszonym, zmieniającym kształt rozwidleniu długości
  dziesięciu bloków i wszystkich sprite'ach.

Budżet klatki 50 Hz wynosi 69 888 taktów. Powyższe przypadki zajmują
odpowiednio około 93,3% i 88,1% klatki. Generator planuje most i rozwidlenie
jako osobne cechy trasy, więc ich najdroższe przebiegi nie nakładają się w
normalnej sekwencji. Pozostaje około 4,7 tys. taktów w ciężkiej klatce mostu;
przed dodaniem dźwięku i paliwa warto ponowić profilowanie.

Test po usunięciu poruszonych sprite'ów porównał wszystkie 6144 bajty bitmapy
z pełną rekonstrukcją z pierścienia trasy: liczba różniących się bajtów wyniosła
`0`.
