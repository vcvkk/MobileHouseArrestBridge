TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MobileHouseArrestBridge

MobileHouseArrestBridge_FILES = main.m AppDelegate.m GlassStatusViewController.m MHAServer.m MCMBridge.m
MobileHouseArrestBridge_CFLAGS = -fobjc-arc -I.
MobileHouseArrestBridge_CODESIGN_FLAGS = -S
MobileHouseArrestBridge_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/application.mk
