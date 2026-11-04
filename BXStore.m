//
//  BXStore.m —— 用 MRC 编译（-fno-objc-arc）
//  1) BXSetCtxURL：把上下文对象里 +0x20 的强引用改成用户填的地址
//  2) 供 BXHook.m 的 stub 调用
//

#import <objc/runtime.h>
#import <stddef.h>

extern void objc_storeStrong(id *location, id obj);
extern id BXCurrentURL(void);      // 在 Tweak.xm 里实现（ARC 那边持有 gURL）

void BXSetCtxURL(void *ctx) {
    if (!ctx) return;
    id url = BXCurrentURL();
    if (!url) return;
    id *slot = (id *)((char *)ctx + 0x20);
    objc_storeStrong(slot, url);
}
