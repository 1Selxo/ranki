//! libk5compat - Compatibility shim for running modern ARM binaries on Kindle Touch 4th Gen
//! Target OS: Linux 2.6.31-rt11-lab126 / glibc 2.12.1 (Kindle firmware 5.3.7.3)
//!
//! Provides missing symbols introduced in glibc > 2.12:
//! - clock_gettime (GLIBC_2.17 in libc.so.6; in glibc 2.12 it was in librt.so.1)
//! - getauxval (GLIBC_2.16)
//! - __cxa_thread_atexit_impl (GLIBC_2.18)

#![no_std]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

#[inline(always)]
unsafe fn syscall3(nr: usize, a0: usize, a1: usize, a2: usize) -> isize {
    let ret: isize;
    core::arch::asm!(
        "svc 0",
        inout("r7") nr => ret,
        in("r0") a0,
        in("r1") a1,
        in("r2") a2,
        options(nostack)
    );
    ret
}

#[inline(always)]
unsafe fn syscall2(nr: usize, a0: usize, a1: usize) -> isize {
    let ret: isize;
    core::arch::asm!(
        "svc 0",
        inout("r7") nr => ret,
        in("r0") a0,
        in("r1") a1,
        options(nostack)
    );
    ret
}

#[inline(always)]
unsafe fn syscall1(nr: usize, a0: usize) -> isize {
    let ret: isize;
    core::arch::asm!(
        "svc 0",
        inout("r7") nr => ret,
        in("r0") a0,
        options(nostack)
    );
    ret
}

#[repr(C)]
pub struct timespec {
    pub tv_sec: isize,
    pub tv_nsec: isize,
}

/// Linux ARM EABI SYS_clock_gettime = 263
#[no_mangle]
pub unsafe extern "C" fn clock_gettime(clk_id: i32, tp: *mut timespec) -> i32 {
    let res = syscall2(263, clk_id as usize, tp as usize);
    res as i32
}

#[repr(C)]
struct Elf32Auxv {
    a_type: u32,
    a_val: u32,
}

/// Reads hardware capability and system info from /proc/self/auxv
#[no_mangle]
pub unsafe extern "C" fn getauxval(type_: usize) -> usize {
    let path = b"/proc/self/auxv\0";
    let fd = syscall3(5 /* SYS_open */, path.as_ptr() as usize, 0 /* O_RDONLY */, 0);
    if fd < 0 {
        return 0;
    }
    let fd = fd as usize;
    let mut entry = Elf32Auxv { a_type: 0, a_val: 0 };
    let mut found = 0usize;
    loop {
        let n = syscall3(3 /* SYS_read */, fd, &mut entry as *mut _ as usize, core::mem::size_of::<Elf32Auxv>());
        if n as usize != core::mem::size_of::<Elf32Auxv>() {
            break;
        }
        if entry.a_type == 0 {
            break;
        }
        if entry.a_type as usize == type_ {
            found = entry.a_val as usize;
            break;
        }
    }
    syscall1(6 /* SYS_close */, fd);
    found
}

/// Thread destructor registration fallback
#[no_mangle]
pub unsafe extern "C" fn __cxa_thread_atexit_impl(
    _dtor: usize,
    _obj: usize,
    _dso_symbol: usize,
) -> i32 {
    0
}
