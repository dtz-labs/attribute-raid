.PHONY: all run run-48 profile run-profile clean

OUTDIR := build
TAP := $(OUTDIR)/attribute-raid.tap
DEFINES ?=
ZESARUX ?= /Applications/ZEsarUX.app/Contents/MacOS/zesarux
ZESARUX_FLAGS ?= --joystickemulated "Kempston"
ZESARUX_MACHINE ?= 128k
ZESARUX_DIR := $(dir $(ZESARUX))

all: $(TAP)

$(TAP): src/main.asm tools/build.py | $(OUTDIR)
	python3 tools/build.py $(DEFINES) src/main.asm $(OUTDIR)

$(OUTDIR):
	mkdir -p $(OUTDIR)

run: $(TAP)
	@test -x "$(ZESARUX)" || { echo "ZEsarUX binary not found: $(ZESARUX)" >&2; exit 1; }
	cd "$(ZESARUX_DIR)" && ./zesarux --noconfigfile --machine $(ZESARUX_MACHINE) \
		$(ZESARUX_FLAGS) --nosplash --verbose 0 "$(abspath $(TAP))"

run-48:
	$(MAKE) ZESARUX_MACHINE=48k run

profile:
	$(MAKE) OUTDIR=build-profile DEFINES="-D PROFILE_BORDER=1" all

run-profile:
	$(MAKE) OUTDIR=build-profile DEFINES="-D PROFILE_BORDER=1" run

clean:
	rm -rf build build-profile build-timex
