CC = cc
CXX = c++
CFLAGS = -ObjC -fobjc-arc
CXXFLAGS = -ObjC++ -fobjc-arc
LDFLAGS = -framework Foundation -framework AppKit -framework Cocoa -lobjc -lc++

TARGET = commander
APP_NAME = Commander
APP_BUNDLE = dist/$(APP_NAME).app
APP_EXEC = $(APP_BUNDLE)/Contents/MacOS/$(TARGET)
APP_PLIST = $(APP_BUNDLE)/Contents/Info.plist
SRC_C = src/objc_bridge.c
SRC_MM = src/commander_renderer.mm
OBJ_REL = src/objc_bridge.o src/commander_renderer.o
OBJ_ABS = $(addprefix $(CURDIR)/,$(OBJ_REL))
CRYSTAL = crystal
CRYSTAL_SRC = src/commander.cr
CRYSTAL_SRCS = $(shell find src -name '*.cr')

.PHONY: all app clean run run-open

all: $(TARGET)

src/objc_bridge.o: $(SRC_C) src/commander_renderer.h
	$(CC) $(CFLAGS) -c $(SRC_C) -o $(CURDIR)/$@

src/commander_renderer.o: $(SRC_MM) src/commander_renderer.h
	$(CXX) $(CXXFLAGS) -c $(SRC_MM) -o $(CURDIR)/$@

$(TARGET): $(OBJ_REL) $(CRYSTAL_SRCS)
	$(CRYSTAL) build $(CRYSTAL_SRC) -o $(TARGET) --link-flags "$(OBJ_ABS) $(LDFLAGS)"

app: $(TARGET)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp "$(TARGET)" "$(APP_EXEC)"
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '  <key>CFBundleDevelopmentRegion</key>' \
	  '  <string>en</string>' \
	  '  <key>CFBundleExecutable</key>' \
	  '  <string>$(TARGET)</string>' \
	  '  <key>CFBundleIdentifier</key>' \
	  '  <string>dev.sergey.commander</string>' \
	  '  <key>CFBundleName</key>' \
	  '  <string>$(APP_NAME)</string>' \
	  '  <key>CFBundlePackageType</key>' \
	  '  <string>APPL</string>' \
	  '  <key>CFBundleVersion</key>' \
	  '  <string>0.1.0</string>' \
	  '  <key>CFBundleShortVersionString</key>' \
	  '  <string>0.1.0</string>' \
	  '  <key>LSMinimumSystemVersion</key>' \
	  '  <string>14.0</string>' \
	  '  <key>NSHighResolutionCapable</key>' \
	  '  <true/>' \
	  '  <key>NSPrincipalClass</key>' \
	  '  <string>NSApplication</string>' \
	  '</dict>' \
	  '</plist>' \
	  > "$(APP_PLIST)"

run: app
	"$(APP_EXEC)"

run-open: app
	/usr/bin/open -n "$(APP_BUNDLE)"

clean:
	rm -rf "$(APP_BUNDLE)"
	rm -f $(OBJ_ABS) $(TARGET)
