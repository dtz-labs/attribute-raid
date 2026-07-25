.PHONY: all standard timex run run-48 run-timex run-tc2048 run-tc2068 \
	run-ts2068 profile run-profile profile-timex run-profile-timex \
	zesarux-config clean

OUTDIR := build
TAP := $(OUTDIR)/attribute-raid.tap
TIMEX_TAP := $(OUTDIR)/attribute-raid-timex.tap
ASM_SOURCES := $(wildcard src/*.asm)
DEFINES ?=
ZESARUX ?= /Applications/ZEsarUX.app/Contents/MacOS/zesarux
ZESARUX_CONFIG ?= $(abspath tools/zesarux.rc)
ZESARUX_FLAGS ?=
ZESARUX_MACHINE ?= 128k
ZESARUX_DIR := $(dir $(ZESARUX))

# --configfile must come first; it replaces ~/.zesaruxrc and carries the
# joystick mapping. --nosplash/--nowelcomemessage skip the startup logo.
ZESARUX_BASE = --configfile "$(ZESARUX_CONFIG)" --nosplash --nowelcomemessage \
	--verbose 0

define check-zesarux
@test -x "$(ZESARUX)" || { echo "ZEsarUX binary not found: $(ZESARUX)" >&2; exit 1; }
@test -f "$(ZESARUX_CONFIG)" || { echo "ZEsarUX config not found: $(ZESARUX_CONFIG)" >&2; exit 1; }
endef

all: $(TAP) $(TIMEX_TAP)

standard: $(TAP)

timex: $(TIMEX_TAP)

$(TAP): $(ASM_SOURCES) tools/build.py | $(OUTDIR)
	python3 tools/build.py $(DEFINES) src/main.asm $(OUTDIR)

$(TIMEX_TAP): $(ASM_SOURCES) tools/build.py | $(OUTDIR)
	python3 tools/build.py $(DEFINES) -D TIMEX_HICOLOR=1 \
		--basename attribute-raid-timex src/main.asm $(OUTDIR)

$(OUTDIR):
	mkdir -p $(OUTDIR)

run: standard
	$(check-zesarux)
	cd "$(ZESARUX_DIR)" && ./zesarux $(ZESARUX_BASE) \
		--machine $(ZESARUX_MACHINE) $(ZESARUX_FLAGS) "$(abspath $(TAP))"

run-48:
	$(MAKE) ZESARUX_MACHINE=48k run

run-timex: run-tc2068

run-tc2048: timex
	$(check-zesarux)
	cd "$(ZESARUX_DIR)" && ./zesarux $(ZESARUX_BASE) \
		--machine TC2048 --enabletimexvideo $(ZESARUX_FLAGS) \
		"$(abspath $(TIMEX_TAP))"

run-tc2068: timex
	$(check-zesarux)
	cd "$(ZESARUX_DIR)" && ./zesarux $(ZESARUX_BASE) \
		--machine TC2068 --enabletimexvideo $(ZESARUX_FLAGS) \
		"$(abspath $(TIMEX_TAP))"

run-ts2068: timex
	$(check-zesarux)
	cd "$(ZESARUX_DIR)" && ./zesarux $(ZESARUX_BASE) \
		--machine TS2068 --enabletimexvideo $(ZESARUX_FLAGS) \
		"$(abspath $(TIMEX_TAP))"

profile:
	$(MAKE) OUTDIR=build-profile DEFINES="-D PROFILE_BORDER=1" standard

run-profile:
	$(MAKE) OUTDIR=build-profile DEFINES="-D PROFILE_BORDER=1" run

profile-timex:
	$(MAKE) OUTDIR=build-profile-timex DEFINES="-D PROFILE_BORDER=1" timex

run-profile-timex:
	$(MAKE) OUTDIR=build-profile-timex DEFINES="-D PROFILE_BORDER=1" run-tc2068

# Re-copy the real joystick mapping from the global ZEsarUX config into
# tools/zesarux.rc, keeping everything above the sentinel line intact.
zesarux-config:
	@test -f "$(HOME)/.zesaruxrc" || \
		{ echo "No $(HOME)/.zesaruxrc to copy joystick settings from" >&2; exit 1; }
	@joy=$$(grep -E '^--(joystick|realjoystick|steering-wheel)' "$(HOME)/.zesaruxrc" \
			| grep -v '^--joystickemulated' | sed -e 's/[[:space:]]*$$//'); \
	if [ -z "$$joy" ]; then \
		echo "No joystick settings found in $(HOME)/.zesaruxrc" >&2; exit 1; \
	fi; \
	awk '{ print } /^;--- BEGIN generated/ { exit }' "$(ZESARUX_CONFIG)" \
		> "$(ZESARUX_CONFIG).new"; \
	printf '%s\n' "$$joy" >> "$(ZESARUX_CONFIG).new"; \
	mv "$(ZESARUX_CONFIG).new" "$(ZESARUX_CONFIG)"; \
	echo "Updated $(ZESARUX_CONFIG) from $(HOME)/.zesaruxrc"

clean:
	rm -rf build build-profile build-profile-timex build-timex
