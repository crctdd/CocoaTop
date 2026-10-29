TARGET ?= iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME ?= rootless
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
ARCHS ?= arm64e
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
ARCHS ?= arm64 arm64e
else
$(error Only rootless and roothide packages are supported)
endif
DEBUG = 0
FINALPACKAGE = 1
export TARGET ARCHS DEBUG FINALPACKAGE THEOS_PACKAGE_SCHEME

include $(THEOS)/makefiles/common.mk
SUBPROJECTS += src/CocoaTop-helper src/CocoaTop
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	chmod 0755 "$(THEOS_STAGING_DIR)/Applications/CocoaTop.app/CocoaTop"
	chmod 4755 "$(THEOS_STAGING_DIR)/Applications/CocoaTop.app/CocoaTop-helper"
