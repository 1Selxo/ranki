//! libcurl proxy/shim for Kindle devices
//! Forwards to system libcurl if present, or provides safe fallbacks

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
        b"/usr/lib/libcurl.so\0".as_ptr(),
        b"/usr/lib/libcurl.so.4\0".as_ptr(),
        b"/usr/lib/libcurl.so.3\0".as_ptr(),
        b"/lib/libcurl.so\0".as_ptr(),
        b"/lib/libcurl.so.4\0".as_ptr(),
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
pub unsafe extern "C" fn curl_easy_init() -> usize {
    let sym = get_real_sym(b"curl_easy_init\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn() -> usize = core::mem::transmute(sym);
        return f();
    }
    1 // dummy handle
}

#[no_mangle]
pub unsafe extern "C" fn curl_easy_setopt(handle: usize, opt: i32, val: usize) -> i32 {
    let sym = get_real_sym(b"curl_easy_setopt\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, i32, usize) -> i32 = core::mem::transmute(sym);
        return f(handle, opt, val);
    }
    0 // CURLE_OK
}

#[no_mangle]
pub unsafe extern "C" fn curl_easy_perform(handle: usize) -> i32 {
    let sym = get_real_sym(b"curl_easy_perform\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize) -> i32 = core::mem::transmute(sym);
        return f(handle);
    }
    7 // CURLE_COULDNT_CONNECT (handled gracefully by Downloader catch block)
}

#[no_mangle]
pub unsafe extern "C" fn curl_easy_cleanup(handle: usize) {
    let sym = get_real_sym(b"curl_easy_cleanup\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize) = core::mem::transmute(sym);
        f(handle);
    }
}

#[no_mangle]
pub unsafe extern "C" fn curl_easy_getinfo(handle: usize, info: i32, out: usize) -> i32 {
    let sym = get_real_sym(b"curl_easy_getinfo\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(usize, i32, usize) -> i32 = core::mem::transmute(sym);
        return f(handle, info, out);
    }
    0 // CURLE_OK
}

static OK_STR: &[u8] = b"OK\0";

#[no_mangle]
pub unsafe extern "C" fn curl_easy_strerror(code: i32) -> *const u8 {
    let sym = get_real_sym(b"curl_easy_strerror\0".as_ptr());
    if sym != 0 {
        let f: extern "C" fn(i32) -> *const u8 = core::mem::transmute(sym);
        return f(code);
    }
    OK_STR.as_ptr()
}
