//
//  BXRTSPEdit.xm —— 给「百相 / BXFloat 0.20.33 原版」加一个悬浮 RTSP 圆钮：点开输入框改地址
//
//  原理（反汇编确认）：
//    BXFloat 里取地址的函数（arm64 0x3311C4 / arm64e 0x336AC4）开头：
//        ldp  x0, x28, [x0, #0x20]      ; x0 = self->_urlString (NSString)
//        ...
//        msgSend(x0, @selector(UTF8String))
//        x21 = char *url                ; 后面整条链路都用它
//    所以在函数入口把 self+0x20 换成用户输入的 NSString，后面全部生效，原版 UI 不用改。
//
//  注入：TrollFools / TrollStore，和 BXFloat.dylib 一起注入宿主 App。
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <stdlib.h>

#if __has_feature(objc_arc)
extern void objc_storeStrong(id *location, id obj);
#endif

// ── 目标函数偏移（BXFloat 0.20.33）──────────────────────────────────────────────
#if defined(__arm64e__)
static const uintptr_t kCand[] = { 0x336AC4, 0x336AC8, 0x336ACC, 0x336AD0 };
#else
static const uintptr_t kCand[] = { 0x3311C4 };
#endif
static const size_t kCandN = sizeof(kCand) / sizeof(kCand[0]);
static const ptrdiff_t kURLIvarOff = 0x20;   // ldp x0, x28, [x0, #0x20]

static NSString *gURL = nil;                 // nil = 用 dylib 内嵌地址
static IMP gOrig = NULL;
static Class gCls = Nil;
static SEL gSel = NULL;

#pragma mark - 找 BXFloat 镜像基址

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

#pragma mark - 挂钩

static void BXWrapper(id self, SEL _cmd) {
    if (gURL.length && self) {
        void **slot = (void **)((uint8_t *)(__bridge void *)self + kURLIvarOff);
        objc_storeStrong((id *)slot, gURL);
    }
    if (gOrig) ((void (*)(id, SEL))gOrig)(self, _cmd);
}

static BOOL BXHook(void) {
    uintptr_t slide = BXSlide();
    if (!slide) { NSLog(@"[BXRTSP] 找不到 BXFloat 镜像"); return NO; }

    uintptr_t lo[8], hi[8];
    size_t nn = 0;
    for (size_t i = 0; i < kCandN; i++) {
        lo[nn] = slide + kCand[i];
        hi[nn] = lo[nn] + 0x40;      // IMP 可能落在函数的 pacibsp/对齐变体上，给 64 字节容差
        nn++;
    }

    int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (int i = 0; i < count && !gOrig; i++) {
        unsigned mc = 0;
        Method *ms = class_copyMethodList(classes[i], &mc);
        for (unsigned j = 0; j < mc && !gOrig; j++) {
            uintptr_t imp = (uintptr_t)method_getImplementation(ms[j]);
            for (size_t k = 0; k < nn; k++) {
                if (imp >= lo[k] && imp < hi[k]) {
                    gCls = classes[i];
                    gSel = method_getName(ms[j]);
                    gOrig = method_setImplementation(ms[j], (IMP)BXWrapper);
                    NSLog(@"[BXRTSP] hooked -[%s %s] imp=%p (cand %#lx)",
                          class_getName(gCls), sel_getName(gSel), (void *)imp, (unsigned long)kCand[k]);
                    break;
                }
            }
        }
        free(ms);
    }
    free(classes);

    if (!gOrig) NSLog(@"[BXRTSP] 没命中目标方法 —— 宿主不是 0.20.33 或偏移不同");
    return gOrig != NULL;
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
                                            message:@"保存后下一次点「预览」生效"
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
        NSLog(@"[BXRTSP] 清空覆盖，回到 dylib 内嵌地址");
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

// 用关联对象在 UIButton 上补两个方法（全局只加一次）
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
            BXHook();
            BXButton();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ BXButton(); });
    }
}
