#
# BXRTSPEdit —— 给「百相 0.20.33 原版」加一个能改 RTSP 地址的悬浮按钮
# 产物：BXRTSPEdit.dylib（和 BXFloat.dylib 一起注入，原版界面原样保留）
#

TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = BXRTSPEdit

BXRTSPEdit_FILES = Tweak.xm
BXRTSPEdit_CFLAGS = -fobjc-arc -Wno-everything
BXRTSPEdit_FRAMEWORKS = UIKit Foundation
BXRTSPEdit_LDFLAGS = -Wl,-x -install_name @executable_path/BXRTSPEdit.dylib

include $(THEOS_MAKE_PATH)/library.mk
