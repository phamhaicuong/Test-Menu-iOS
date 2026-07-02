ARCHS = arm64
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTestDylib
MyTestDylib_FILES = Tweak.x
MyTestDylib_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk