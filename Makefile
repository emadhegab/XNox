# Build XNox from source. No Apple Developer account needed: the app is ad-hoc signed.
DERIVED := build
APP     := $(DERIVED)/Build/Products/Release/XNox.app
XCB     := xcodebuild -project XNox.xcodeproj -scheme XNox -derivedDataPath $(DERIVED) \
           CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=

.PHONY: build run install test clean

build:            ## Build Release app into ./build
	$(XCB) -configuration Release build

run: build        ## Build and open the app
	open "$(APP)"

install: build    ## Build and copy to /Applications
	ditto "$(APP)" /Applications/XNox.app

test:             ## Run unit tests
	$(XCB) -configuration Debug -destination 'platform=macOS' test

clean:
	rm -rf $(DERIVED)
