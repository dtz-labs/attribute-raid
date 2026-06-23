.PHONY: all run clean

OUTDIR := build
TAP := $(OUTDIR)/attribute-raid.tap
ZESARUX ?= /Applications/ZEsarUX.app/Contents/MacOS/zesarux
ZESARUX_DIR := $(dir $(ZESARUX))

all: $(TAP)

$(TAP): src/main.asm tools/build.py | $(OUTDIR)
	python3 tools/build.py src/main.asm $(OUTDIR)

$(OUTDIR):
	mkdir -p $(OUTDIR)

run: $(TAP)
	@test -x "$(ZESARUX)" || { echo "ZEsarUX binary not found: $(ZESARUX)" >&2; exit 1; }
	cd "$(ZESARUX_DIR)" && ./zesarux --noconfigfile --machine 48k \
		--nosplash --verbose 0 "$(abspath $(TAP))"

clean:
	rm -rf $(OUTDIR)
