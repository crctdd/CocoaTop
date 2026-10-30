include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = CocoaTop
CocoaTop_FILES = $(wildcard src/*.m)
CocoaTop_CFLAGS = -fobjc-arc -iquote src -IIOKit.framework/Headers
CocoaTop_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore WebKit
CocoaTop_PRIVATE_FRAMEWORKS = IOKit
CocoaTop_CODESIGN_FLAGS = -Sentitlements.xml
CocoaTop_RESOURCE_FILES = Info.plist $(filter-out res/CocoaTop-helper res/Assets.xcassets res/LaunchScreen.storyboard,$(wildcard res/*))
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
CocoaTop_CFLAGS += -DCT_ROOTHIDE=1
CocoaTop_LIBRARIES += roothide
else
CocoaTop_CFLAGS += -DCT_ROOTHIDE=0
endif

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	python3 ../../scripts/stage-resources.py "$(THEOS_STAGING_DIR)/Applications/CocoaTop.app"
