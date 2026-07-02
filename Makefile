ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HaiCuongMenu
HaiCuongMenu_FILES = Tweak.xm
HaiCuongMenu_CFLAGS = -fobjc-arc
HaiCuongMenu_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
