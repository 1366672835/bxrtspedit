//
//  Tweak.xm —— 给「百相 / BXFloat 0.20.33 原版」加一个悬浮 RTSP 圆钮：点开输入框改地址
//
//  改地址原理（反汇编确认）：
//    BXFloat 里取地址的是一个 block/C 函数（不是 ObjC 方法），
//    arm64 入口 0x3311C4 / arm64e 0x336AC8 处第一条指令是
//        stp d15, d14, [sp, #-0xa0]!
//    紧接着就
//        ldp x0, x28, [x0, #0x20]      ; x0 = ctx->url (NSString)
//    所以在入口打一个跳转（BXHook.m 的 inline hook），先把 ctx+0x20 换成用户
//    填的地址，再跳回原代码继续，整条链路就都用我们的地址。
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <stdlib.h>

extern int BXInstallInlineHook(uintptr_t target, uintptr_t resume);

#if defined(__arm64e__)
static const uintptr_t kPatchOff = 0x336AC8;   // 跳过入口的 pacibsp
#else
static const uintptr_t kPatchOff = 0x3311C4;
#endif

static NSString *gURL = nil;                   // nil = 用 dylib 内嵌地址

id BXCurrentURL(void) { return gURL; }         // 给 BXStore.m 用

static uintptr_t BXSlide(void) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "BXFloat")) return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
    }
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "BX")) return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
    }
    return 0;
}

static void BXInstall(void) {
    uintptr_t slide = BXSlide();
    if (!slide) { NSLog(@"[BXRTSP] 找不到 BXFloat 镜像（确认两个 dylib 都注入了）"); return; }
    uintptr_t patch = slide + kPatchOff;
    int rc = BXInstallInlineHook(patch, patch + 4);
    NSLog(@"[BXRTSP] inline hook patch=%p rc=%d (0=成功 -1=改不了内存保护 -2=跳转太远)",
          (void *)patch, rc);
}

#pragma mark - 弹窗

static UIViewController *BXTopVC(void) {
    UIViewController *top = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { top = w.rootViewController; break; }
    }
    if (!top) top = [UIApplication sharedApplication].windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static void BXEdit(void) {
    NSUserDefaults *st = [NSUserDefaults standardUserDefaults];
    NSString *saved = [st stringForKey:@"bx_rtsp_url"];

    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"RTSP 地址"
                                            message:@"保存后点「预览」即用这个地址"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = gURL.length ? gURL : (saved.length ? saved : @"");
        tf.placeholder = @"rtsp://admin:pass@192.168.1.64:554/Streaming/Channels/101";
        tf.keyboardType = UIKeyboardTypeURL;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"用内嵌地址"
                                          style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *a) {
        gURL = nil;
        [st removeObjectForKey:@"bx_rtsp_url"];
        [st synchronize];
        NSLog(@"[BXRTSP] 清空，回到 dylib 内嵌地址");
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *a) {
        NSString *u = ac.textFields.firstObject.text ?: @"";
        u = [u stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        gURL = u.length ? [u copy] : nil;
        [st setObject:(u ?: @"") forKey:@"bx_rtsp_url"];
        [st synchronize];
        NSLog(@"[BXRTSP] 保存 = %@", u);
    }]];

    UIViewController *top = BXTopVC();
    if (top) [top presentViewController:ac animated:YES completion:nil];
}

#pragma mark - 悬浮圆钮

static UIButton *gBtn = nil;

static void BXButton(void) {
    if (gBtn && gBtn.superview) return;

    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].windows.firstObject;
    if (!win) return;

    NSUserDefaults *st = [NSUserDefaults standardUserDefaults];
    CGFloat x = [st objectForKey:@"bx_rtsp_btn_x"] ? (CGFloat)[st doubleForKey:@"bx_rtsp_btn_x"] : 16;
    CGFloat y = [st objectForKey:@"bx_rtsp_btn_y"] ? (CGFloat)[st doubleForKey:@"bx_rtsp_btn_y"] : 140;

    if (!gBtn) {
        gBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        gBtn.layer.cornerRadius = 23;
        gBtn.backgroundColor = [UIColor colorWithRed:0.08 green:0.48 blue:0.92 alpha:0.92];
        gBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [gBtn setTitle:@"RTSP" forState:UIControlStateNormal];
        [gBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        gBtn.layer.shadowColor = [UIColor blackColor].CGColor;
        gBtn.layer.shadowOpacity = 0.25f;
        gBtn.layer.shadowRadius = 4;
        gBtn.layer.shadowOffset = CGSizeMake(0, 2);
        [gBtn addTarget:gBtn action:@selector(bxTapAction) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:gBtn action:@selector(bxPanAction:)];
        [gBtn addGestureRecognizer:pan];
    }
    gBtn.frame = CGRectMake(x, y, 46, 46);
    [win addSubview:gBtn];
    [win bringSubviewToFront:gBtn];
    NSLog(@"[BXRTSP] 圆钮已挂上 frame=%@", NSStringFromCGRect(gBtn.frame));
}

@interface UIButton (BXRTSP)
- (void)bxTapAction;
- (void)bxPanAction:(UIPanGestureRecognizer *)g;
@end

@implementation UIButton (BXRTSP)
- (void)bxTapAction { BXEdit(); }
- (void)bxPanAction:(UIPanGestureRecognizer *)g {
    UIView *sv = self.superview;
    CGPoint t = [g translationInView:sv];
    CGPoint c = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    CGFloat hw = self.bounds.size.width / 2, hh = self.bounds.size.height / 2;
    c.x = MAX(hw, MIN(sv.bounds.size.width - hw, c.x));
    c.y = MAX(hh + 44, MIN(sv.bounds.size.height - hh - 34, c.y));
    self.center = c;
    [g setTranslation:CGPointZero inView:sv];
    if (g.state == UIGestureRecognizerStateEnded) {
        NSUserDefaults *s = [NSUserDefaults standardUserDefaults];
        [s setDouble:self.frame.origin.x forKey:@"bx_rtsp_btn_x"];
        [s setDouble:self.frame.origin.y forKey:@"bx_rtsp_btn_y"];
        [s synchronize];
    }
}
@end

#pragma mark - 启动

__attribute__((constructor))
static void BXInit(void) {
    @autoreleasepool {
        NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:@"bx_rtsp_url"];
        gURL = s.length ? [s copy] : nil;
        NSLog(@"[BXRTSP] init url=%@", gURL ?: @"(内嵌地址)");

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            BXInstall();
            BXButton();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ BXButton(); });
    }
}
