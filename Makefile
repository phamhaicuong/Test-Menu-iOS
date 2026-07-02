ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTestDylib
MyTestDylib_FILES = Tweak.xm
MyTestDylib_CFLAGS = -fobjc-arc
MyTestDylib_LDFLAGS = -ldobby

include $(THEOS_MAKE_PATH)/tweak.mk
