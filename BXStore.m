//
//  BXStore.m —— 用 MRC 编译（-fno-objc-arc）
//  作用：把某个对象里指定偏移的强引用槽改成我们的字符串。
//        ARC 下不允许 (void**) -> (__strong id*) 的转换，所以单独放到这里。
//

#import <objc/runtime.h>
#import <stddef.h>

void BXRawSetURL(id self, ptrdiff_t offset, id url) {
    if (!self) return;
    id *slot = (id *)((char *)self + offset);
    objc_storeStrong(slot, url);   // 等价 self->ivar = url（release 旧值 / retain 新值）
}
