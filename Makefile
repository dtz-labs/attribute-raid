.PHONY: all standard timex run run-48 run-timex run-tc2048 run-tc2068 \
	run-ts2068 profile run-profile clean

OUTDIR := build
TAP := $(OUTDIR)/attribute-raid.tap
TIMEX_TAP := $(OUTDIR)/attribute-raid-timex.tap
DEFINES ?=
ZESARUX ?= /Applications/ZEsarUX.app/Contents/MacOS/zesarux
ZESARUX_FLAGS ?= --joystickemulated "Kempston"
ZESARUX_MACHINE ?= 128k
ZESARUX_DIR := $(dir $(ZESARUX))

all: $(TAP) $(TIMEX_TAP)

standard: $(TAP)

timex: $(TIMEX_TAP)

$(TAP): src/main.asm tools/build.py | $(OUTDIR)
	python3 tools/build.py $(DEFINES) src/main.asm $(OUTDIR)

$(TIMEX_TAP): src/main.asm tools/build.py | $(OUTDIR)
	python3 tools/build.py $(DEFINES) -D TIMEX_HICOLOR=1 \
		--basename attribute-raid-timex src/main.asm $(OUTDIR)

$(OUTDIR):
	mkdir -p $(OUTDIR)

run: standard
	@test -x "$(ZESARUX)" || { echo "ZEsarUX binary not found: $(ZESARUX)" >&2; exit 1; }
	cd "$(ZESARUX_DIR)" && ./zesarux --noconfigfile --machine $(ZESARUX_MACHINE) \
		$(ZESARUX_FLAGS) --nosplash --verbose 0 "$(abspath $(TAP))"

run-48:
	$(MAKE) ZESARUX_MACHINE=48k run

run-timex: run-tc2068

run-tc2048: timex
	@test -x "$(ZESARUX)" || { echo "ZEsarUX binary not found: $(ZESARUX)" >&2; exit 1; }
	cd "$(ZESARUX_DIR)" && ./zesarux --noconfigfile --machine TC2048 \
		--enabletimexvideo $(ZESARUX_FLAGS) --nosplash --verbose 0 \
		"$(abspath $(TIMEX_TAP))"

run-tc2068: timex
	@test -x "$(ZESARUX)" || { echo "ZEsarUX binary not found: $(ZESARUX)" >&2; exit 1; }
	cd "$(ZESARUX_DIR)" && ./zesarux --noconfigfile --machine TC2068 \
		--enabletimexvideo $(ZESARUX_FLAGS) --nosplash --verbose 0 \
		"$(abspath $(TIMEX_TAP))"

run-ts2068: timex
	@test -x "$(ZESARUX)" || { echo "ZEsarUX binary not found: $(ZESARUX)" >&2; exit 1; }
	cd "$(ZESARUX_DIR)" && ./zesarux --noconfigfile --machine TS2068 \
		--enabletimexvideo $(ZESARUX_FLAGS) --nosplash --verbose 0 \
		"$(abspath $(TIMEX_TAP))"

profile:
	$(MAKE) OUTDIR=build-profile DEFINES="-D PROFILE_BORDER=1" standard

run-profile:
	$(MAKE) OUTDIR=build-profile DEFINES="-D PROFILE_BORDER=1" run

clean:
	rm -rf build build-profile build-timex
