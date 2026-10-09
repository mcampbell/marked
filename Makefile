# Local use only. No target needs root.
CLT_FW   := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TESTFLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -F -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW)
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
APP      := build/Marked.app
INSTALLED := $(HOME)/Applications/Marked.app

.PHONY: build test app run install clean

build:
	swift build -c release

test:
	swift test $(TESTFLAGS)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/Marked" $(APP)/Contents/MacOS/Marked
	cp Scripts/Info.plist $(APP)/Contents/Info.plist
	cp -R Resources/ $(APP)/Contents/Resources/
	codesign --force -s - $(APP)

run: app
	open $(APP)

install: app
	mkdir -p $(HOME)/Applications
	rm -rf $(INSTALLED)
	ditto $(APP) $(INSTALLED)
	$(LSREGISTER) -f $(INSTALLED)

clean:
	rm -rf .build build
