.PHONY: all run timex run-timex clean

OUTDIR := build
TAP := $(OUTDIR)/attribute-raid.tap
DEFINES ?=
MACHINE ?= 48k
ZESARUX ?= /Applications/ZEsarUX.app/Contents/MacOS/zesarux
ZESARUX_FLAGS ?=
ZESARUX_DIR := $(dir $(ZESARUX))

all: $(TAP)

$(TAP): src/main.asm tools/build.py | $(OUTDIR)
	python3 tools/build.py $(DEFINES) src/main.asm $(OUTDIR)

$(OUTDIR):
	mkdir -p $(OUTDIR)

run: $(TAP)
	@test -x "$(ZESARUX)" || { echo "ZEsarUX binary not found: $(ZESARUX)" >&2; exit 1; }
	cd "$(ZESARUX_DIR)" && ./zesarux --noconfigfile --machine $(MACHINE) \
		$(ZESARUX_FLAGS) --nosplash --verbose 0 "$(abspath $(TAP))"

timex:
	$(MAKE) OUTDIR=build-timex DEFINES="-D TIMEX_DOUBLE_BUFFER=1" MACHINE=TC2048 all

run-timex:
	$(MAKE) OUTDIR=build-timex DEFINES="-D TIMEX_DOUBLE_BUFFER=1" MACHINE=TC2048 \
		ZESARUX_FLAGS=--enabletimexvideo run

clean:
	rm -rf build build-timex
