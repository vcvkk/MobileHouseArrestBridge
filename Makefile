TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = MobileHouseArrestBridge

MobileHouseArrestBridge_FILES = main.m MCMBridge.m
MobileHouseArrestBridge_CFLAGS = -fobjc-arc -I.
MobileHouseArrestBridge_CODESIGN_FLAGS = -S
MobileHouseArrestBridge_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tool.mk
