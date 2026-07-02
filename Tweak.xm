#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <substrate.h> 
#include <string.h>
#include <stdlib.h>

#define PATTERN_SET_CURRENT "48 89 5C 24 08 57 48 83 EC 20 8B 91 ?? ?? ?? ?? 48 8B 01 FF 90 ?? ?? ?? ?? 48 8B 5C 24 30 48 83 C4 20 5F C3"
#define PATTERN_SET_HIGH    "48 89 5C 24 08 57 48 83 EC 20 8B 91 ?? ?? ?? ?? 48 8B 01 FF 90 ?? ?? ?? ?? 48 8B 5C 24 30 48 83 C4 20 5F C3"

static int g_userCurrent = 0;
static int g_userHigh = 0;

static void (*orig_SetCurrent)(void *instance, int value);
static void (*orig_SetHigh)(void *instance, int value);

static void hook_SetCurrent(void *instance, int value) {
    if (g_userCurrent > 0) {
        orig_SetCurrent(instance, g_userCurrent);
        return;
    }
    orig_SetCurrent(instance, value);
}

static void hook_SetHigh(void *instance, int value) {
    if (g_userHigh > 0) {
        orig_SetHigh(instance, g_userHigh);
        return;
    }
    orig_SetHigh(instance, value);
}

// ==== BỘ QUÉT PATTERN TỰ ĐỘNG ====
static uintptr_t findPattern(const char *pattern, const char *mask, size_t len) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, "BlockBlast")) continue;
        uintptr_t base = (uintptr_t)header;
        uintptr_t textStart = 0, textEnd = 0;
        struct load_command *lc = (struct load_command *)(base + sizeof(struct mach_header_64));
        for (uint32_t j = 0; j < header->ncmds; j++) {
            if (lc->cmd == LC_SEGMENT_64) {
                struct segment_command_64 *seg = (struct segment_command_64 *)lc;
                if (strcmp(seg->segname, "__TEXT") == 0) {
                    textStart = base + seg->fileoff;
                    textEnd = textStart + seg->filesize;
                }
            }
            lc = (struct load_command *)((uintptr_t)lc + lc->cmdsize);
        }
        if (textStart == 0) continue;
        for (uintptr_t addr = textStart; addr < textEnd - len; addr++) {
            BOOL match = YES;
            for (size_t k = 0; k < len; k++) {
                if (mask[k] == '?') continue;
                if (((uint8_t *)addr)[k] != (uint8_t)strtol(pattern + (k*3), NULL, 16)) {
                    match = NO;
                    break;
                }
            }
            if (match) return addr;
        }
    }
    return 0;
}

static uintptr_t scanForPattern(const char *patternStr) {
    NSArray *parts = [[NSString stringWithUTF8String:patternStr] componentsSeparatedByString:@" "];
    NSMutableArray *bytes = [NSMutableArray array];
    NSMutableString *maskStr = [NSMutableString string];
    for (NSString *part in parts) {
        if ([part isEqualToString:@"?"]) {
            [bytes addObject:@0];
            [maskStr appendString:@"?"];
        } else {
            unsigned int byteVal;
            [[NSScanner scannerWithString:part] scanHexInt:&byteVal];
            [bytes addObject:@(byteVal)];
            [maskStr appendString:@"x"];
        }
    }
    size_t len = [bytes count];
    uint8_t *byteArr = (uint8_t *)malloc(len);
    char *maskArr = (char *)malloc(len + 1);
    for (size_t i = 0; i < len; i++) {
        byteArr[i] = [bytes[i] unsignedCharValue];
        maskArr[i] = [maskStr characterAtIndex:i];
    }
    maskArr[len] = '\0';
    uintptr_t result = findPattern((const char *)byteArr, maskArr, len);
    free(byteArr);
    free(maskArr);
    return result;
}

// ==== MÓC NỐI VÀO GAME BẰNG SUBSTRATE ====
static void setupHooks() {
    uintptr_t addrCurrent = scanForPattern(PATTERN_SET_CURRENT);
    if (addrCurrent) {
        MSHookFunction((void *)addrCurrent, (void *)hook_SetCurrent, (void **)&orig_SetCurrent);
    }

    uintptr_t addrHigh = scanForPattern(PATTERN_SET_HIGH);
    if (addrHigh) {
        MSHookFunction((void *)addrHigh, (void *)hook_SetHigh, (void **)&orig_SetHigh);
    }
}

// ==== GIAO DIỆN MENU HẢI CƯỜNG ====
static void applyScores(UIAlertController *alert) {
    UITextField *tfCur = alert.textFields[0];
    UITextField *tfHigh = alert.textFields[1];
    if (!tfCur || !tfHigh) return;

    int cur = [tfCur.text intValue];
    int high = [tfHigh.text intValue];
    if (cur < 0) cur = 0;
    if (high < 0) high = 0;
    if (high < cur) high = cur;

    g_userCurrent = cur;
    g_userHigh = high;

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"✅ Thành công"
                                                                     message:[NSString stringWithFormat:@"Đã cập nhật!\nHiện tại: %d\nCao nhất: %d", cur, high]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (root) [root presentViewController:confirm animated:YES completion:nil];
}

static void showMenu() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (!root) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🏆 HẢI CƯỜNG MOD"
                                                                   message:@"Nhập điểm bạn muốn thay đổi:"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Điểm hiện tại";
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.text = [NSString stringWithFormat:@"%d", g_userCurrent];
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Điểm cao nhất";
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.text = [NSString stringWithFormat:@"%d", g_userHigh];
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Áp dụng" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        applyScores(alert);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

    [root presentViewController:alert animated:YES completion:nil];
}

// ==== NÚT TRÔI NỔI (FLOATING BUTTON) ====
static UIButton *floatingButton = nil;
static UIWindow *overlayWindow = nil;

static void handlePan(UIPanGestureRecognizer *gesture) {
    UIButton *btn = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    CGRect newFrame = btn.frame;
    newFrame.origin.x += translation.x;
    newFrame.origin.y += translation.y;
    btn.frame = newFrame;
    [gesture setTranslation:CGPointZero inView:btn.superview];
}

static void floatingButtonTapped() {
    showMenu();
}

static void createFloatingButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        overlayWindow.windowLevel = UIWindowLevelStatusBar + 100;
        overlayWindow.backgroundColor = [UIColor clearColor];
        overlayWindow.userInteractionEnabled = YES;
        overlayWindow.hidden = NO;

        floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = CGRectMake(20, 100, 60, 60);
        floatingButton.backgroundColor = [UIColor blackColor];
        floatingButton.layer.cornerRadius = 30;
        [floatingButton setTitle:@"⚙" forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont systemFontOfSize:30];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:floatingButton action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];
        [floatingButton addTarget:self action:@selector(floatingButtonTapped) forControlEvents:UIControlEventTouchUpInside];

        [overlayWindow addSubview:floatingButton];
    });
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        createFloatingButton();
        setupHooks();
    });
}
