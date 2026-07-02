#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include <substrate.h>

// --- ĐIỀN OFFSET CỦA GAME VÀO ĐÂY ---
// Tạm thời để 0x123456, sau này bạn dùng Il2CppDumper tìm được số chuẩn thì thay vào
#define OFFSET_SET_SCORE 0x123456 

static int g_targetScore = -1;
static void (*orig_UpdateScore)(void *instance, int score);

// Hàm thay đổi điểm
static void hook_UpdateScore(void *instance, int score) {
    if (g_targetScore >= 0) {
        orig_UpdateScore(instance, g_targetScore);
    } else {
        orig_UpdateScore(instance, score);
    }
}

// --- TẠO GIAO DIỆN MENU HẢI CƯỜNG ---
@interface HaiCuongMenu : NSObject
+ (void)showMenu;
@end

@implementation HaiCuongMenu
+ (void)showMenu {
    // Cách lấy màn hình chuẩn không bao giờ bị lỗi Apple cấm
    UIWindow *keyWindow = nil;
    NSArray *windows = [[UIApplication sharedApplication] windows];
    for (UIWindow *window in windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    if (!keyWindow) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🏆 HẢI CƯỜNG MOD"
                                                                   message:@"Nhập điểm Block Blast bạn muốn:"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Ví dụ: 999999";
        textField.keyboardType = UIKeyboardTypeNumberPad;
    }];

    UIAlertAction *applyAction = [UIAlertAction actionWithTitle:@"Áp dụng" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alert.textFields.firstObject;
        if (textField.text.length > 0) {
            g_targetScore = [textField.text intValue];
            
            UIAlertController *success = [UIAlertController alertControllerWithTitle:@"✅ Thành công"
                                                                             message:[NSString stringWithFormat:@"Đã hack thành: %d điểm", g_targetScore]
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [success addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [keyWindow.rootViewController presentViewController:success animated:YES completion:nil];
        }
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil];

    [alert addAction:applyAction];
    [alert addAction:cancelAction];

    [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}
@end

// --- TẠO NÚT CÀI ĐẶT TRÔI NỔI ---
@interface FloatingButtonTarget : NSObject
- (void)buttonTapped;
- (void)handlePan:(UIPanGestureRecognizer *)recognizer;
@end

@implementation FloatingButtonTarget
- (void)buttonTapped {
    [HaiCuongMenu showMenu];
}
- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    UIView *button = recognizer.view;
    CGPoint translation = [recognizer translationInView:button.superview];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [recognizer setTranslation:CGPointZero inView:button.superview];
}
@end

static FloatingButtonTarget *targetInstance;

// Hiển thị nút lên màn hình game
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            
            targetInstance = [[FloatingButtonTarget alloc] init];
            
            UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            menuBtn.frame = CGRectMake(20, 100, 55, 55);
            menuBtn.backgroundColor = [UIColor blackColor];
            menuBtn.layer.cornerRadius = 27.5;
            [menuBtn setTitle:@"⚙" forState:UIControlStateNormal];
            menuBtn.titleLabel.font = [UIFont systemFontOfSize:28];
            
            [menuBtn addTarget:targetInstance action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
            
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:targetInstance action:@selector(handlePan:)];
            [menuBtn addGestureRecognizer:pan];
            
            [(UIWindow *)self addSubview:menuBtn];
        });
    });
}
%end

// --- TIẾN HÀNH TIÊM CODE (HOOK) KHI MỞ GAME ---
%ctor {
    uintptr_t baseAddr = 0;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "BlockBlast")) {
            baseAddr = (uintptr_t)_dyld_get_image_header(i);
            break;
        }
    }
    
    if (baseAddr != 0) {
        uintptr_t targetFunc = baseAddr + OFFSET_SET_SCORE;
        MSHookFunction((void *)targetFunc, (void *)hook_UpdateScore, (void **)&orig_UpdateScore);
    }
}
