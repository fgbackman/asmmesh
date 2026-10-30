# asmmesh — a Bluetooth LE mesh messenger with a Cocoa window, ARM64 assembly, Apple Silicon only.
#
#   make           build asmmesh.app (signed with your Apple Development identity if found, else ad-hoc)
#   make run       build and open the app (it will ask for Bluetooth permission the first time)
#   make selftest  build and run the mesh-logic tests (no Bluetooth, no window)
#   make install   selftest, then install to /Applications, pin to the Dock and launch
#   make clean

CC      := clang
ARCH    := -arch arm64 -mmacosx-version-min=12.0
SRCDIR  := src
SRCS    := $(SRCDIR)/main.s $(SRCDIR)/ui.s $(SRCDIR)/scanner.s $(SRCDIR)/util.s $(SRCDIR)/ble.s $(SRCDIR)/mesh.s \
           $(SRCDIR)/home.s $(SRCDIR)/parse.s $(SRCDIR)/net.s $(SRCDIR)/hue.s $(SRCDIR)/st.s $(SRCDIR)/lan.s \
           $(SRCDIR)/cloud.s $(SRCDIR)/udp.s $(SRCDIR)/near.s $(SRCDIR)/bt.s $(SRCDIR)/voice.s $(SRCDIR)/test.s \
           $(SRCDIR)/weather.s $(SRCDIR)/crypto.s $(SRCDIR)/rules.s $(SRCDIR)/find.s $(SRCDIR)/extras.s $(SRCDIR)/spin.s $(SRCDIR)/services.s $(SRCDIR)/ident.s \
           $(SRCDIR)/fm.s $(SRCDIR)/fm_dsp.s $(SRCDIR)/fm_audio.s $(SRCDIR)/fm_io.s $(SRCDIR)/fm_pack.s \
           $(SRCDIR)/fm_util.s $(SRCDIR)/fm_fec.s $(SRCDIR)/fm_html.s $(SRCDIR)/web.s $(SRCDIR)/spinui.s $(SRCDIR)/alerts.s $(SRCDIR)/files.s \
           $(SRCDIR)/sens_decode.s $(SRCDIR)/sensors.s $(SRCDIR)/handoff.s $(SRCDIR)/cards.s $(SRCDIR)/limits.s $(SRCDIR)/guard.s $(SRCDIR)/files_mac.s $(SRCDIR)/scan_core.s $(SRCDIR)/listed.s $(SRCDIR)/seek.s \
           $(SRCDIR)/bc_crypto.s $(SRCDIR)/bc_link.s $(SRCDIR)/bc_ble.s $(SRCDIR)/bc_packet.s $(SRCDIR)/bc_zlib.s
OBJS    := $(SRCS:.s=.o)
FRAMEWORKS := -framework Cocoa -framework CoreBluetooth -framework Security -framework Speech -framework AVFoundation \
              -framework IOBluetooth -framework AudioToolbox -framework CoreAudio -framework CoreFoundation -framework CoreLocation -framework CoreImage -framework IOKit -lz
APP     := asmmesh.app

SIGN ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $$2; exit}')
ifeq ($(strip $(SIGN)),)
SIGN := -
endif

all: $(APP)

asmmesh: $(OBJS)
	$(CC) $(ARCH) -o $@ $(OBJS) $(FRAMEWORKS)

$(SRCDIR)/%.o: $(SRCDIR)/%.s $(SRCDIR)/macros.inc $(SRCDIR)/fm_defs.inc $(SRCDIR)/fm_fec_tables.inc $(SRCDIR)/sens_bthome.inc $(SRCDIR)/bc_defs.inc
	$(CC) $(ARCH) -I $(SRCDIR) -c $< -o $@

$(APP): asmmesh Info.plist icon/AppIcon.icns
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp asmmesh $(APP)/Contents/MacOS/asmmesh
	cp Info.plist $(APP)/Contents/Info.plist
	cp icon/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	chmod -R u+w $(APP)
	xattr -cr $(APP)
	codesign --force --sign "$(SIGN)" $(APP)
	@echo "built $(APP) (signed: $(SIGN))"

run: $(APP)
	open $(APP)

selftest: asmmesh
	./asmmesh --selftest

install: selftest $(APP)
	sh install.sh

clean:
	rm -rf $(OBJS) asmmesh $(APP)

.PHONY: all run selftest install clean
