APP       = texterm
BUILD     = .build
BUNDLE    = $(BUILD)/$(APP).app
BINARY    = $(BUNDLE)/Contents/MacOS/$(APP)
RESOURCES = $(BUNDLE)/Contents/Resources

SDK       = $(shell xcrun --show-sdk-path --sdk macosx)
ARCH      = $(shell uname -m)
TARGET    = $(ARCH)-apple-macosx13.0

SWIFT_SRCS  = $(wildcard Sources/texterm/*.swift)
C_OBJ       = $(BUILD)/pty_spawn.o
BRIDGE_HDR  = Sources/texterm/BridgingHeader.h

# Stable code-signing identity. Ad-hoc signing (codesign -s -) gives the app a
# new cdhash every build, so macOS treats each rebuild as a new app and
# re-prompts for Photos/Music/file (TCC) access forever. A self-signed cert in a
# dedicated keychain gives a stable, cert-based designated requirement, so a TCC
# grant survives rebuilds. Created once by `make cert`; build falls back to
# ad-hoc when the identity is absent.
SIGN_ID    = texterm-codesign
SIGN_KC    = $(HOME)/Library/Keychains/$(SIGN_ID).keychain-db
SIGN_KCPW  = texterm
INSTALLDIR = $(HOME)/Applications

.PHONY: all setup build run clean cert install icon

all: build

# Download KaTeX (fonts included) into Resources/katex/
setup:
	@command -v npm >/dev/null || { echo "ERROR: npm is required for setup (installs KaTeX + xterm.js)."; exit 1; }
	@echo "Downloading KaTeX + xterm.js..."
	@mkdir -p Resources/katex Resources/xterm
	@TMP=$$(mktemp -d) && \
	  npm install --prefix $$TMP katex @xterm/xterm @xterm/addon-fit --silent && \
	  cp -r $$TMP/node_modules/katex/dist/. Resources/katex/ && \
	  cp $$TMP/node_modules/@xterm/xterm/lib/xterm.js Resources/xterm/ && \
	  cp $$TMP/node_modules/@xterm/xterm/css/xterm.css Resources/xterm/ && \
	  cp $$TMP/node_modules/@xterm/addon-fit/lib/addon-fit.js Resources/xterm/ && \
	  rm -rf $$TMP && echo "KaTeX + xterm.js installed."

# Compile the C shim that wraps fork() + exec()
$(C_OBJ): Sources/texterm/pty_spawn.c
	@mkdir -p $(BUILD)
	clang -c Sources/texterm/pty_spawn.c \
	      -isysroot $(SDK) \
	      -target $(TARGET) \
	      -o $(C_OBJ)

build: $(C_OBJ) $(SWIFT_SRCS)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(RESOURCES)
	swiftc $(SWIFT_SRCS) \
	    -sdk $(SDK) \
	    -target $(TARGET) \
	    -framework AppKit \
	    -framework WebKit \
	    -import-objc-header $(BRIDGE_HDR) \
	    -I Sources/texterm \
	    $(C_OBJ) \
	    -O \
	    -o $(BINARY)
	@cp Info.plist $(BUNDLE)/Contents/
	@cp -r Resources/ $(RESOURCES)/
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "$(SIGN_ID)"; then \
	  security unlock-keychain -p "$(SIGN_KCPW)" "$(SIGN_KC)" 2>/dev/null || true; \
	  codesign --force -s "$(SIGN_ID)" --entitlements texterm.entitlements $(BUNDLE) && \
	  echo "Signed with stable identity '$(SIGN_ID)' (TCC grants persist)."; \
	else \
	  codesign -s - --entitlements texterm.entitlements $(BUNDLE) 2>/dev/null || true; \
	  echo "Signed ad-hoc. Run 'make cert' once so TCC grants survive rebuilds."; \
	fi
	@echo ""
	@echo "Built: $(BUNDLE)"
	@echo "Run with: make run"

# One-time: create a dedicated keychain + self-signed code-signing certificate
# so rebuilds keep a stable identity (see SIGN_ID comment). Idempotent and fully
# non-interactive. Reverse with: security delete-keychain $(SIGN_KC)
cert:
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "$(SIGN_ID)"; then \
	  echo "Signing identity '$(SIGN_ID)' already exists. Nothing to do."; \
	else \
	  echo "Creating dedicated signing keychain + self-signed cert '$(SIGN_ID)'..."; \
	  KC="$(HOME)/Library/Keychains/$(SIGN_ID).keychain"; \
	  security create-keychain -p "$(SIGN_KCPW)" "$$KC"; \
	  security set-keychain-settings "$$KC"; \
	  security unlock-keychain -p "$(SIGN_KCPW)" "$$KC"; \
	  T=$$(mktemp -d); \
	  openssl req -x509 -newkey rsa:2048 -keyout $$T/k.pem -out $$T/c.pem -days 3650 -nodes \
	    -subj "/CN=$(SIGN_ID)" \
	    -addext "basicConstraints=critical,CA:false" \
	    -addext "keyUsage=critical,digitalSignature" \
	    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null; \
	  openssl pkcs12 -export -legacy -out $$T/id.p12 -inkey $$T/k.pem -in $$T/c.pem -passout pass:tt 2>/dev/null; \
	  security import $$T/id.p12 -k "$$KC" -P tt -T /usr/bin/codesign -A >/dev/null; \
	  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(SIGN_KCPW)" "$$KC" >/dev/null 2>&1; \
	  security add-trusted-cert -r trustRoot -p codeSign -k "$$KC" $$T/c.pem >/dev/null 2>&1; \
	  EX=$$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g'); \
	  echo "$$EX" | grep -q "$(SIGN_ID)" || security list-keychains -d user -s $$EX "$$KC"; \
	  rm -rf $$T; \
	  echo "Done. Now: make install, then grant Full Disk Access once."; \
	fi

# Install to a fixed location (TCC/Full Disk Access is tied to a stable path).
install: build
	@mkdir -p $(INSTALLDIR)
	@rm -rf $(INSTALLDIR)/$(APP).app
	@cp -R $(BUNDLE) $(INSTALLDIR)/
	@echo "Installed: $(INSTALLDIR)/$(APP).app"
	@echo "Grant Full Disk Access once: System Settings > Privacy & Security > Full Disk Access > +"

# Regenerate Resources/AppIcon.icns from assets/icon.png (the 1024px master).
icon:
	@sh scripts/make-icon.sh

run: build
	open $(BUNDLE)

clean:
	rm -rf $(BUILD)
