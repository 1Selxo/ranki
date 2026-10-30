//! liblipc proxy/shim for Kindle devices
//! Forwards to system /usr/lib/liblipc.so if present, or returns safe defaults

#![no_std]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

extern "C" {
    fn dlopen(filename: *const u8, flags: i32) -> usize;
    fn dlsym(handle: usize, symbol: *const u8) -> usize;
}

static mut REAL_HANDLE: usize = 0;
static mut ATTEMPTED: bool = false;

unsafe fn get_real_handle() -> usize {
    if ATTEMPTED {
        return REAL_HANDLE;
    }
    ATTEMPTED = true;
    let paths = [
        b"/usr/lib/liblipc.so\0".as_ptr(),
        b"/usr/lib/liblipc.so.0\0".as_ptr(),
        b"/lib/liblipc.so\0".as_ptr(),
        b"/opt/amazon/ebook/lib/liblipc.so\0".as_ptr(),
    ];
    for &p in paths.iter() {
        let h = dlopen(p, 1 /* RTLD_LAZY */);
        if h != 0 {
            REAL_HANDLE = h;
            return h;
        }
    }
    0
}

unsafe fn get_real_sym(name: *const u8) -> usize {
    let h = get_real_handle();
    if h == 0 {
        return 0;
    }
    dlsym(h, name)
}

#[no_mangle]
pub unsafe extern "C" fn LipcOpenNoName() -> usize {
    let sym = get_real_sym(b"LipcOpenNoName\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn() -> usize = core::mem::transmute(sym);
        return f();
    }
    1
}

#[no_mangle]
pub unsafe extern "C" fn LipcOpen(name: *const u8) -> usize {
    let sym = get_real_sym(b"LipcOpen\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(*const u8) -> usize = core::mem::transmute(sym);
        return f(name);
    }
    1
}

#[no_mangle]
pub unsafe extern "C" fn LipcClose(h: usize) -> i32 {
    let sym = get_real_sym(b"LipcClose\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize) -> i32 = core::mem::transmute(sym);
        return f(h);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn LipcSetStringProperty(h: usize, prop: *const u8, val: *const u8) -> i32 {
    let sym = get_real_sym(b"LipcSetStringProperty\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, *const u8, *const u8) -> i32 = core::mem::transmute(sym);
        return f(h, prop, val);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn LipcGetStringProperty(h: usize, prop: *const u8, out: *mut *mut u8) -> i32 {
    let sym = get_real_sym(b"LipcGetStringProperty\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, *const u8, *mut *mut u8) -> i32 = core::mem::transmute(sym);
        return f(h, prop, out);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn LipcSetIntProperty(h: usize, prop: *const u8, val: i32) -> i32 {
    let sym = get_real_sym(b"LipcSetIntProperty\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, *const u8, i32) -> i32 = core::mem::transmute(sym);
        return f(h, prop, val);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn LipcGetIntProperty(h: usize, prop: *const u8, out: *mut i32) -> i32 {
    let sym = get_real_sym(b"LipcGetIntProperty\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, *const u8, *mut i32) -> i32 = core::mem::transmute(sym);
        return f(h, prop, out);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn LipcFreeString(s: *mut u8) {
    let sym = get_real_sym(b"LipcFreeString\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(*mut u8) = core::mem::transmute(sym);
        f(s);
    }
}

#[no_mangle]
pub unsafe extern "C" fn LipcGetStringParam(event: usize, idx: i32, out: *mut *mut u8) -> i32 {
    let sym = get_real_sym(b"LipcGetStringParam\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, i32, *mut *mut u8) -> i32 = core::mem::transmute(sym);
        return f(event, idx, out);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn LipcGetIntParam(event: usize, idx: i32, out: *mut i32) -> i32 {
    let sym = get_real_sym(b"LipcGetIntParam\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, i32, *mut i32) -> i32 = core::mem::transmute(sym);
        return f(event, idx, out);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn LipcSubscribeExt(h: usize, name: *const u8, cb: usize, data: usize) -> i32 {
    let sym = get_real_sym(b"LipcSubscribeExt\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, *const u8, usize, usize) -> i32 = core::mem::transmute(sym);
        return f(h, name, cb, data);
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn LipcUnsubscribeExt(h: usize, name: *const u8, cb: usize, data: usize) -> i32 {
    let sym = get_real_sym(b"LipcUnsubscribeExt\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, *const u8, usize, usize) -> i32 = core::mem::transmute(sym);
        return f(h, name, cb, data);
    }
    0
}
