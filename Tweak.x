#import <UIKit/UIKit.h>

// Hook vào quá trình khởi tạo giao diện của app
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig; // Gọi lại hàm gốc để app vẫn chạy bình thường (rất quan trọng)
    
    // Đảm bảo thông báo chỉ hiện 1 lần duy nhất khi mở app
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Menu Test" 
                                                                       message:@"Dylib đã được tiêm thành công bằng ESign!" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:ok];
        
        UIViewController *rootViewController = self.rootViewController;
        [rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

%end