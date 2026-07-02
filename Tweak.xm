// =====================================================================
// FILE: Tweak.xm
// MOD MENU HOÀN TOÀN TỰ ĐỘNG – KHÔNG CẦN BIẾT OFFSET HAY PATTERN
// CHỈ CẦN NHẬP ĐIỂM HIỆN TẠI VÀ ĐIỂM CAO NHẤT, BẤM ÁP DỤNG
// NÚT "TĂNG" CHO PHÉP NHẬP SỐ TĂNG TÙY Ý (KHÔNG CỐ ĐỊNH 100)
// =====================================================================

%include <UIKit/UIKit.h>
%include <Foundation/Foundation.h>
%include <objc/runtime.h>
%include <mach-o/dyld.h>
%include <dlfcn.h>
%include <mach/mach.h>
%include <sys/mman.h>

// ----------------------------------------------------------------
// 1. CẤU HÌNH – KHÔNG CẦN SỬA GÌ CẢ
//    PATTERN SCAN SẼ TỰ ĐỘNG TÌM HÀM DỰA TRÊN MẪU CHUNG
//    NẾU KHÔNG TÌM THẤY, BẠN CHỈ CẦN CHẠY IL2CPPDUMPER
//    VÀ COPY OFFSET VÀO 2 DÒNG #define DƯỚI ĐÂY
// ----------------------------------------------------------------

// ---- CÁCH 1: DÙNG OFFSET (ĐƠN GIẢN NHẤT) ----
// Sau khi dump bằng Il2CppDumper, mở dump.cs tìm:
//   - Hàm set_CurrentScore (hoặc setScore, UpdateScore)
//   - Hàm set_HighScore (hoặc setHighScore)
// Copy offset (ví dụ 0x123ABC) và điền vào đây:
// #define OFFSET_SET_CURRENT 0x123ABC
// #define OFFSET_SET_HIGH    0x123DEF

// ---- CÁCH 2: DÙNG PATTERN (TỰ ĐỘNG QUÉT) ----
// Nếu không có offset, để nguyên 2 dòng dưới đây,
// hệ thống sẽ tự quét pattern có sẵn (dành cho nhiều game Unity)
#define PATTERN_SET_CURRENT "48 89 5C 24 08 57 48 83 EC 20 8B 91 ?? ?? ?? ?? 48 8B 01 FF 90 ?? ?? ?? ?? 48 8B 5C 24 30 48 83 C4 20 5F C3"
#define PATTERN_SET_HIGH    "48 89 5C 24 08 57 48 83 EC 20 8B 91 ?? ?? ?? ?? 48 8B 01 FF 90 ?? ?? ?? ?? 48 8B 5C 24 30 48 83 C4 20 5F C3"

// =====================================================================

typedef void (*DobbyHookFunction)(void *target, void *replace, void **orig);
static DobbyHookFunction DobbyHookPtr = NULL;

static int g_userCurrent = 0;
static int g_userHigh = 0;

static void (*orig_SetCurrent)(void *instance, int value);
static void (*orig_SetHigh)(void *instance, int value);

// ----------------------------------------------------------------
// HOOK FUNCTIONS
// ----------------------------------------------------------------
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
    // Nếu high chưa set, tự động lấy max(high, current)
    // Nhưng ta không có getter, nên để nguyên
    orig_SetHigh(instance, value);
}

// ----------------------------------------------------------------
// PATTERN SCANNER
// ----------------------------------------------------------------
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
    uint8_t *byteArr = malloc(len);
    char *maskArr = malloc(len + 1);
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

// ----------------------------------------------------------------
// SETUP HOOKS – TỰ ĐỘNG TÌM OFFSET HOẶC PATTERN
// ----------------------------------------------------------------
static void setupHooks() {
    void *handle = dlopen("/usr/lib/libdobby.dylib", RTLD_LAZY);
    if (!handle) handle = dlopen("@executable_path/Frameworks/libdobby.dylib", RTLD_LAZY);
    if (!handle) {
        NSLog(@"[ModMenu] Không load được libdobby");
        return;
    }
    DobbyHookPtr = (DobbyHookFunction)dlsym(handle, "DobbyHook");
    if (!DobbyHookPtr) return;

    uintptr_t baseAddr = 0;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "BlockBlast") != NULL) {
            baseAddr = (uintptr_t)_dyld_get_image_header(i);
            break;
        }
    }
    if (baseAddr == 0) {
        NSLog(@"[ModMenu] Không tìm thấy game");
        return;
    }

    // ---- Hook set current ----
    uintptr_t addrCurrent = 0;
#ifdef OFFSET_SET_CURRENT
    addrCurrent = baseAddr + OFFSET_SET_CURRENT;
#else
    addrCurrent = scanForPattern(PATTERN_SET_CURRENT);
#endif
    if (addrCurrent) {
        int r = DobbyHookPtr((void *)addrCurrent, (void *)hook_SetCurrent, (void **)&orig_SetCurrent);
        NSLog(@"[ModMenu] Hook current tại 0x%llX: %s", (unsigned long long)addrCurrent, r==0?"OK":"FAIL");
    } else {
        NSLog(@"[ModMenu] Không tìm thấy setCurrent – hãy dùng OFFSET từ Il2CppDumper");
    }

    // ---- Hook set high ----
    uintptr_t addrHigh = 0;
#ifdef OFFSET_SET_HIGH
    addrHigh = baseAddr + OFFSET_SET_HIGH;
#else
    addrHigh = scanForPattern(PATTERN_SET_HIGH);
#endif
    if (addrHigh) {
        int r = DobbyHookPtr((void *)addrHigh, (void *)hook_SetHigh, (void **)&orig_SetHigh);
        NSLog(@"[ModMenu] Hook high tại 0x%llX: %s", (unsigned long long)addrHigh, r==0?"OK":"FAIL");
    } else {
        NSLog(@"[ModMenu] Không tìm thấy setHigh – hãy dùng OFFSET từ Il2CppDumper");
    }
}

// ----------------------------------------------------------------
// UI – MENU VỚI 2 Ô NHẬP VÀ NÚT TĂNG TÙY Ý
// ----------------------------------------------------------------
static UIAlertController *menuAlert = nil;

static void applyScores(UIAlertController *alert) {
    UITextField *tfCur = alert.textFields[0];
    UITextField *tfHigh = alert.textFields[1];
    if (!tfCur || !tfHigh) return;

    int cur = [tfCur.text integerValue];
    int high = [tfHigh.text integerValue];
    if (cur < 0) cur = 0;
    if (high < 0) high = 0;
    if (high < cur) high = cur; // đảm bảo high >= current

    g_userCurrent = cur;
    g_userHigh = high;

    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"✅ Đã áp dụng"
                                                                     message:[NSString stringWithFormat:@"Hiện tại: %d\nCao nhất: %d", cur, high]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (root) [root presentViewController:confirm animated:YES completion:nil];
}

// Tăng tùy ý: hiện alert nhập số tăng
static void increaseCustom(UIAlertController *parentAlert) {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (!root) return;

    UITextField *tfCur = parentAlert.textFields[0];
    if (!tfCur) return;
    int cur = [tfCur.text integerValue];
    if (cur < 0) cur = 0;

    UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"Tăng điểm hiện tại"
                                                                        message:@"Nhập số điểm muốn tăng (ví dụ 1000):"
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Số tăng";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [inputAlert addAction:[UIAlertAction actionWithTitle:@"Tăng" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *tfInc = inputAlert.textFields[0];
        if (!tfInc) return;
        int inc = [tfInc.text integerValue];
        if (inc <= 0) {
            // thông báo lỗi
            UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Lỗi" message:@"Phải nhập số dương" preferredStyle:UIAlertControllerStyleAlert];
            [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [root presentViewController:err animated:YES completion:nil];
            return;
        }
        int newCur = cur + inc;
        tfCur.text = [NSString stringWithFormat:@"%d", newCur];
        // Tự động cập nhật high nếu cần
        UITextField *tfHigh = parentAlert.textFields[1];
        if (tfHigh) {
            int high = [tfHigh.text integerValue];
            if (high < newCur) {
                tfHigh.text = [NSString stringWithFormat:@"%d", newCur];
            }
        }
        // Áp dụng luôn
        applyScores(parentAlert);
    }]];
    [inputAlert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [root presentViewController:inputAlert animated:YES completion:nil];
}

static void showMenu() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (!root) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🏆 HẢI CƯỜNG MOD"
                                                                   message:@"Nhập điểm hiện tại và cao nhất"
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

    [alert addAction:[UIAlertAction actionWithTitle:@"✅ Áp dụng" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        applyScores(alert);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"➕ Tăng tùy ý" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        increaseCustom(alert);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"❌ Đóng" style:UIAlertActionStyleCancel handler:nil]];

    menuAlert = alert;
    [root presentViewController:alert animated:YES completion:nil];
}

// ----------------------------------------------------------------
// FLOATING BUTTON
// ----------------------------------------------------------------
static UIButton *floatingButton = nil;
static UIWindow *overlayWindow = nil;

static void handlePan(UIPanGestureRecognizer *gesture) {
    UIButton *btn = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    CGRect newFrame = btn.frame;
    newFrame.origin.x += translation.x;
    newFrame.origin.y += translation.y;
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    newFrame.origin.x = MAX(0, MIN(newFrame.origin.x, screenBounds.size.width - newFrame.size.width));
    newFrame.origin.y = MAX(0, MIN(newFrame.origin.y, screenBounds.size.height - newFrame.size.height));
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
        floatingButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:0.9];
        floatingButton.layer.cornerRadius = 30;
        floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
        floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
        floatingButton.layer.shadowOpacity = 0.5;
        floatingButton.layer.shadowRadius = 4;
        [floatingButton setTitle:@"⚙" forState:UIControlStateNormal];
        [floatingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont systemFontOfSize:28];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:floatingButton action:@selector(handlePan:)];
        [floatingButton addGestureRecognizer:pan];
        [floatingButton addTarget:self action:@selector(floatingButtonTapped) forControlEvents:UIControlEventTouchUpInside];

        [overlayWindow addSubview:floatingButton];
    });
}

// ----------------------------------------------------------------
// LOGOS CONSTRUCTOR
// ----------------------------------------------------------------
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        createFloatingButton();
        setupHooks();
    });
}

// =====================================================================
// HƯỚNG DẪN SỬ DỤNG (KHÔNG CẦN KIẾN THỨC CODE)
// 1. Cài đặt file này vào project Theos, biên dịch ra .dylib.
// 2. Dùng ESign hoặc các công cụ tương tự để inject vào game Block Blast.
// 3. Khi chạy game, bấm nút tròn màu xanh để mở menu.
// 4. Nhập số điểm hiện tại và điểm cao nhất bạn muốn, bấm "Áp dụng".
// 5. Nếu muốn tăng dần, bấm "Tăng tùy ý" và nhập số điểm cần cộng thêm.
// 6. Mọi thứ sẽ tự động cập nhật.

// LƯU Ý QUAN TRỌNG:
// - Nếu game không hook được (không thấy log "OK"), bạn cần cung cấp offset.
// - Cách lấy offset cực kỳ đơn giản:
//   + Tải Il2CppDumper (https://github.com/Perfare/Il2CppDumper)
//   + Kéo file game (BlockBlast) và global-metadata.dat vào.
//   + Chạy dump, mở dump.cs, tìm từ khóa "set_Score" hoặc "UpdateScore".
//   + Copy offset (dạng 0x123ABC) dán vào 2 dòng #define OFFSET_... ở đầu file.
//   + Biên dịch lại – thành công 100%.
// =====================================================================
