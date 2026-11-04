//
//  BXHook.m —— 直接改函数入口（inline hook），不依赖 ObjC 方法表
//  目标：BXFloat 里那个取地址的函数（arm64 0x3311C4 / arm64e 0x336AC8 的 stp）
//  做法：把入口那条 stp 改成 "b bx_stub"，stub 里先调 BXSetCtxURL(ctx, url)，
//        再复刻被覆盖的那条指令，然后跳回 +4 继续执行。
//  编译：-fno-objc-arc
//

#import <stdint.h>
#import <string.h>
#import <unistd.h>
#import <sys/mman.h>
#import <mach/mach.h>
#import <libkern/OSCacheControl.h>

extern void BXSetCtxURL(void *ctx);   // 在 BXStore.m 里实现

uintptr_t gBXResume = 0;              // 被覆盖指令之后的下一条

// 入口 stub：保存调用者寄存器 -> 调 C -> 还原 -> 复刻 stp -> 跳回
__attribute__((naked)) void bx_stub(void) {
    __asm__ volatile(
        "sub  sp, sp, #224\n"
        "stp  x0, x1, [sp, #0]\n"
        "stp  x2, x3, [sp, #16]\n"
        "stp  x4, x5, [sp, #32]\n"
        "stp  x6, x7, [sp, #48]\n"
        "stp  x8, x9, [sp, #64]\n"
        "stp  x16, x17, [sp, #80]\n"
        "stp  q0, q1, [sp, #96]\n"
        "stp  q2, q3, [sp, #128]\n"
        "stp  q4, q5, [sp, #160]\n"
        "stp  q6, q7, [sp, #192]\n"
        "bl   _BXSetCtxURL\n"
        "ldp  q6, q7, [sp, #192]\n"
        "ldp  q4, q5, [sp, #160]\n"
        "ldp  q2, q3, [sp, #128]\n"
        "ldp  q0, q1, [sp, #96]\n"
        "ldp  x16, x17, [sp, #80]\n"
        "ldp  x8, x9, [sp, #64]\n"
        "ldp  x6, x7, [sp, #48]\n"
        "ldp  x4, x5, [sp, #32]\n"
        "ldp  x2, x3, [sp, #16]\n"
        "ldp  x0, x1, [sp, #0]\n"
        "add  sp, sp, #224\n"
        "stp  d15, d14, [sp, #-160]!\n"
        "adrp x16, _gBXResume@PAGE\n"
        "ldr  x16, [x16, _gBXResume@PAGEOFF]\n"
        "br   x16\n"
    );
}

static int bx_make_writable(uintptr_t page) {
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)page, 0x4000, FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY | VM_PROT_EXECUTE);
    if (kr == KERN_SUCCESS) return 0;
    if (mprotect((void *)page, 0x4000, PROT_READ | PROT_WRITE | PROT_EXEC) == 0) return 0;
    return -1;
}

// 返回 0 成功；-1 无法改页属性；-2 跳转距离不够；-3 目标不像代码
int BXInstallInlineHook(uintptr_t target, uintptr_t resume) {
    if (!target || (target & 3)) return -3;
    gBXResume = resume;

    uintptr_t page = target & ~(uintptr_t)0x3FFF;
    if (bx_make_writable(page) != 0) return -1;

    int64_t disp = ((int64_t)(uintptr_t)&bx_stub - (int64_t)target) >> 2;
    if (disp < -(1LL << 25) || disp >= (1LL << 25)) return -2;

    uint32_t insn = 0x14000000u | ((uint32_t)disp & 0x03FFFFFFu);
    *(volatile uint32_t *)target = insn;
    sys_icache_invalidate((void *)target, 4);
    return 0;
}
