//! libk5compat - Compatibility shim for running modern ARM binaries on Kindle Touch 4th Gen
//! Target OS: Linux 2.6.31-rt11-lab126 / glibc 2.12.1 (Kindle firmware 5.3.7.3)
//!
//! Provides missing symbols introduced in glibc > 2.12:
//! - clock_gettime (GLIBC_2.17 in libc.so.6; in glibc 2.12 it was in librt.so.1)
//! - getauxval (GLIBC_2.16)
//! - __cxa_thread_atexit_impl (GLIBC_2.18)
//! - LipcGetIntProperty / LipcSetStringProperty interceptors for keyboard compatibility

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

// -------------------------------------------------------------
// LIPC Interceptors & Helpers
// -------------------------------------------------------------

extern "C" {
    fn dlopen(filename: *const u8, flags: i32) -> usize;
    fn dlsym(handle: usize, symbol: *const u8) -> usize;
}

static mut REAL_LIPC_HANDLE: usize = 0;
static mut REAL_LIPC_ATTEMPTED: bool = false;
static mut KEYBOARD_OPEN: bool = false;

unsafe fn get_real_lipc_handle() -> usize {
    if REAL_LIPC_ATTEMPTED {
        return REAL_LIPC_HANDLE;
    }
    REAL_LIPC_ATTEMPTED = true;
    let paths = [
        b"/usr/lib/liblipc.so\0".as_ptr(),
        b"/usr/lib/liblipc.so.0\0".as_ptr(),
        b"/lib/liblipc.so\0".as_ptr(),
    ];
    for &p in paths.iter() {
        let h = dlopen(p, 1 /* RTLD_LAZY */);
        if h != 0 {
            REAL_LIPC_HANDLE = h;
            return h;
        }
    }
    0
}

unsafe fn get_real_lipc_sym(name: *const u8) -> usize {
    let h = get_real_lipc_handle();
    if h == 0 {
        return 0;
    }
    dlsym(h, name)
}

unsafe fn cstr_eq(mut a: *const u8, mut b: *const u8) -> bool {
    if a.is_null() || b.is_null() {
        return false;
    }
    while *a != 0 && *b != 0 {
        if *a != *b {
            return false;
        }
        a = a.add(1);
        b = b.add(1);
    }
    *a == *b
}

unsafe fn cstr_len(mut s: *const u8) -> usize {
    if s.is_null() {
        return 0;
    }
    let mut len = 0;
    while *s != 0 {
        len += 1;
        s = s.add(1);
    }
    len
}

unsafe fn log_str(s: &[u8]) {
    syscall3(4 /* SYS_write */, 2 /* stderr */, s.as_ptr() as usize, s.len());
}

unsafe fn log_cstr(s: *const u8) {
    if s.is_null() {
        log_str(b"(null)");
    } else {
        let len = cstr_len(s);
        syscall3(4 /* SYS_write */, 2 /* stderr */, s as usize, len);
    }
}

#[no_mangle]
pub unsafe extern "C" fn LipcGetIntProperty(
    lipc: usize,
    service: *const u8,
    property: *const u8,
    value: *mut i32,
) -> i32 {
    let is_kb_show = cstr_eq(service, b"com.lab126.keyboard\0".as_ptr())
        && cstr_eq(property, b"show\0".as_ptr());

    // CRITICAL FIX: On Kindle Touch FW 5.3.7.3, querying "com.lab126.keyboard show"
    // crashes with SIGSEGV in Amazon's liblipc.so.
    // We MUST NOT call the real function for keyboard show!
    if is_kb_show {
        log_str(b"[libk5compat] Intercepted com.lab126.keyboard show -> returning tracked state: ");
        if KEYBOARD_OPEN {
            log_str(b"1\n");
            if !value.is_null() {
                *value = 1;
            }
        } else {
            log_str(b"0\n");
            if !value.is_null() {
                *value = 0;
            }
        }
        return 0; // LIPC_OK!
    }

    let sym = get_real_lipc_sym(b"LipcGetIntProperty\0".as_ptr());
    if sym != 0 {
        let real_fn: extern "C" fn(usize, *const u8, *const u8, *mut i32) -> i32 =
            core::mem::transmute(sym);
        return real_fn(lipc, service, property, value);
    }

    -1
}

#[no_mangle]
pub unsafe extern "C" fn LipcSetStringProperty(
    lipc: usize,
    service: *const u8,
    property: *const u8,
    value: *const u8,
) -> i32 {
    log_str(b"[libk5compat] LipcSetStringProperty: service=");
    log_cstr(service);
    log_str(b", property=");
    log_cstr(property);
    log_str(b", value=");
    log_cstr(value);
    log_str(b"\n");

    let is_kb_service = cstr_eq(service, b"com.lab126.keyboard\0".as_ptr());
    let is_kb_open = is_kb_service && cstr_eq(property, b"open\0".as_ptr());
    let is_kb_close = is_kb_service && cstr_eq(property, b"close\0".as_ptr());

    if is_kb_open {
        KEYBOARD_OPEN = true;
        log_str(b"[libk5compat] Calling real LipcSetStringProperty to open keyboard...\n");
        let sym = get_real_lipc_sym(b"LipcSetStringProperty\0".as_ptr());
        if sym != 0 {
            let real_fn: extern "C" fn(usize, *const u8, *const u8, *const u8) -> i32 =
                core::mem::transmute(sym);
            let res = real_fn(lipc, service, property, value);
            log_str(b"[libk5compat] real LipcSetStringProperty result: ");
            if res == 0 {
                log_str(b"0 (success)\n");
            } else {
                log_str(b"non-zero, trying alternate mode :abc:0...\n");
                let alt = b"ranki.ranki.ranki:abc:0\0";
                let res2 = real_fn(lipc, service, property, alt.as_ptr());
                log_str(b"[libk5compat] alternate mode result: ");
                if res2 == 0 {
                    log_str(b"0 (success)\n");
                } else {
                    log_str(b"non-zero\n");
                }
            }
        }
        return 0;
    }

    if is_kb_close {
        KEYBOARD_OPEN = false;
        log_str(b"[libk5compat] Calling real LipcSetStringProperty to close keyboard...\n");
        let sym = get_real_lipc_sym(b"LipcSetStringProperty\0".as_ptr());
        if sym != 0 {
            let real_fn: extern "C" fn(usize, *const u8, *const u8, *const u8) -> i32 =
                core::mem::transmute(sym);
            real_fn(lipc, service, property, value);
        }
        return 0;
    }

    let sym = get_real_lipc_sym(b"LipcSetStringProperty\0".as_ptr());
    if sym != 0 {
        let real_fn: extern "C" fn(usize, *const u8, *const u8, *const u8) -> i32 =
            core::mem::transmute(sym);
        return real_fn(lipc, service, property, value);
    }

    -1
}
