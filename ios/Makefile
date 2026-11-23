TARGET := iphone:clang:16.5:8.0
ARCHS := armv7
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = iRemote
iRemote_FILES = Sources/main.m Sources/IRSession.m Sources/IRPhoneStore.m Sources/IRDesktopView.m Sources/IRController.m
iRemote_FRAMEWORKS = UIKit Foundation Security QuartzCore ImageIO CoreGraphics AVFoundation
iRemote_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
iRemote_RESOURCE_DIRS = Resources
iRemote_CODESIGN_FLAGS = -S$(CURDIR)/Entitlements.plist
include $(THEOS_MAKE_PATH)/application.mk
