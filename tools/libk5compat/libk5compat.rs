//! libk5compat - Compatibility shim for running modern ARM binaries on Kindle Touch 4th Gen
//! Target OS: Linux 2.6.31-rt11-lab126 / glibc 2.12.1 (Kindle firmware 5.3.7.3)
//!
//! Features:
//! 1. Missing glibc symbols: clock_gettime, getauxval, __cxa_thread_atexit_impl
//! 2. LIPC interceptors for keyboard compatibility (prevents FW 5.3.7.3 segfault)
//! 3. Sync media toggle in Settings:
//!    - Intercepts GtkBuilder to initialize and track the "Sync media" toggle button
//!    - Synchronizes toggle state with /mnt/us/extensions/ranki/config.ini
//!    - Patches backend sync_media instruction dynamically in memory

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

// -------------------------------------------------------------
// Logging Utilities
// -------------------------------------------------------------

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

// -------------------------------------------------------------
// Glibc 2.12 Missing Symbols
// -------------------------------------------------------------

#[repr(C)]
pub struct timespec {
    pub tv_sec: isize,
    pub tv_nsec: isize,
}

static mut INITIALIZED: bool = false;

unsafe fn ensure_initialized() {
    if !INITIALIZED {
        INITIALIZED = true;
        k5compat_init();
    }
}

/// Linux ARM EABI SYS_clock_gettime = 263
#[no_mangle]
pub unsafe extern "C" fn clock_gettime(clk_id: i32, tp: *mut timespec) -> i32 {
    ensure_initialized();
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
    ensure_initialized();
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

#[no_mangle]
pub unsafe extern "C" fn __cxa_thread_atexit_impl(
    _dtor: usize,
    _obj: usize,
    _dso_symbol: usize,
) -> i32 {
    0
}

// -------------------------------------------------------------
// Dynamic Linker Helper
// -------------------------------------------------------------

extern "C" {
    fn dlopen(filename: *const u8, flags: i32) -> usize;
    fn dlsym(handle: usize, symbol: *const u8) -> usize;
}

// -------------------------------------------------------------
// LIPC Interceptors
// -------------------------------------------------------------

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

#[no_mangle]
pub unsafe extern "C" fn LipcGetIntProperty(
    lipc: usize,
    service: *const u8,
    property: *const u8,
    value: *mut i32,
) -> i32 {
    ensure_initialized();
    let is_kb_show = cstr_eq(service, b"com.lab126.keyboard\0".as_ptr())
        && cstr_eq(property, b"show\0".as_ptr());

    if is_kb_show {
        log_str(b"[libk5compat] Intercepted com.lab126.keyboard show -> state: ");
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
        return 0;
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
    ensure_initialized();
    let is_kb_service = cstr_eq(service, b"com.lab126.keyboard\0".as_ptr());
    let is_kb_open = is_kb_service && cstr_eq(property, b"open\0".as_ptr());
    let is_kb_close = is_kb_service && cstr_eq(property, b"close\0".as_ptr());

    if is_kb_open {
        KEYBOARD_OPEN = true;
        log_str(b"[libk5compat] Calling LipcSetStringProperty open...\n");
        let sym = get_real_lipc_sym(b"LipcSetStringProperty\0".as_ptr());
        if sym != 0 {
            let real_fn: extern "C" fn(usize, *const u8, *const u8, *const u8) -> i32 =
                core::mem::transmute(sym);
            let res = real_fn(lipc, service, property, value);
            if res != 0 {
                let alt = b"ranki.ranki.ranki:abc:0\0";
                real_fn(lipc, service, property, alt.as_ptr());
            }
        }
        return 0;
    }

    if is_kb_close {
        KEYBOARD_OPEN = false;
        log_str(b"[libk5compat] Calling LipcSetStringProperty close...\n");
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

// -------------------------------------------------------------
// Sync Media Configuration & Runtime Code Patching
// -------------------------------------------------------------

const CONFIG_PATH: &[u8] = b"/mnt/us/extensions/ranki/config.ini\0";
const ADDR_SYNC_MEDIA: usize = 0x0022d0ec;
const ADDR_SERVICE: usize = 0x0022d0fa;

unsafe fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if haystack.len() < needle.len() {
        return None;
    }
    for i in 0..=(haystack.len() - needle.len()) {
        let mut matches = true;
        for j in 0..needle.len() {
            if haystack[i + j] != needle[j] {
                matches = false;
                break;
            }
        }
        if matches {
            return Some(i);
        }
    }
    None
}

unsafe fn copy_slice(dest: &mut [u8], dest_len: &mut usize, src: &[u8]) {
    for &b in src.iter() {
        if *dest_len < dest.len() {
            dest[*dest_len] = b;
            *dest_len += 1;
        }
    }
}

unsafe fn starts_with_ignore_case(s: &[u8], prefix: &[u8]) -> bool {
    if s.len() < prefix.len() {
        return false;
    }
    for i in 0..prefix.len() {
        let a = s[i].to_ascii_lowercase();
        let b = prefix[i].to_ascii_lowercase();
        if a != b {
            return false;
        }
    }
    true
}

unsafe fn read_config_sync_media() -> bool {
    let mut fd = syscall3(5 /* SYS_open */, CONFIG_PATH.as_ptr() as usize, 0 /* O_RDONLY */, 0);
    if fd < 0 {
        fd = syscall3(5, b"config.ini\0".as_ptr() as usize, 0, 0);
    }
    if fd < 0 {
        return true; // default enabled
    }
    let fd = fd as usize;
    let mut buf = [0u8; 1024];
    let n = syscall3(3 /* SYS_read */, fd, buf.as_mut_ptr() as usize, buf.len());
    syscall1(6 /* SYS_close */, fd);
    if n <= 0 {
        return true;
    }
    let len = n as usize;
    let content = &buf[..len];

    let key = b"sync_media";
    if let Some(pos) = find_subslice(content, key) {
        let after = &content[pos + key.len()..];
        let mut idx = 0;
        while idx < after.len() && (after[idx] == b' ' || after[idx] == b'=') {
            idx += 1;
        }
        if idx < after.len() {
            let val = &after[idx..];
            if starts_with_ignore_case(val, b"false") || starts_with_ignore_case(val, b"0") {
                return false;
            }
            if starts_with_ignore_case(val, b"true") || starts_with_ignore_case(val, b"1") {
                return true;
            }
        }
    }
    true
}

unsafe fn write_config_sync_media(enabled: bool) {
    let mut buf = [0u8; 2048];
    let mut fd = syscall3(5 /* SYS_open */, CONFIG_PATH.as_ptr() as usize, 0 /* O_RDONLY */, 0);
    let path = if fd < 0 {
        b"config.ini\0".as_ptr()
    } else {
        syscall1(6 /* SYS_close */, fd as usize);
        CONFIG_PATH.as_ptr()
    };

    let fd_in = syscall3(5, path as usize, 0 /* O_RDONLY */, 0);
    let mut len = 0usize;
    if fd_in >= 0 {
        let n = syscall3(3 /* SYS_read */, fd_in as usize, buf.as_mut_ptr() as usize, buf.len() - 100);
        syscall1(6 /* SYS_close */, fd_in as usize);
        if n > 0 {
            len = n as usize;
        }
    }

    let mut out_buf = [0u8; 2048];
    let mut out_len = 0usize;

    let target_line: &[u8] = if enabled {
        b"sync_media=true\n"
    } else {
        b"sync_media=false\n"
    };

    if len == 0 {
        copy_slice(&mut out_buf, &mut out_len, b"[General]\n");
        copy_slice(&mut out_buf, &mut out_len, target_line);
    } else {
        let content = &buf[..len];
        let mut found = false;
        let mut line_start = 0usize;

        while line_start < content.len() {
            let mut line_end = line_start;
            while line_end < content.len() && content[line_end] != b'\n' {
                line_end += 1;
            }
            let line = &content[line_start..line_end];
            let mut trimmed = line;
            while !trimmed.is_empty() && (trimmed[0] == b' ' || trimmed[0] == b'\t' || trimmed[0] == b'\r') {
                trimmed = &trimmed[1..];
            }

            if trimmed.starts_with(b"sync_media") {
                copy_slice(&mut out_buf, &mut out_len, target_line);
                found = true;
            } else {
                copy_slice(&mut out_buf, &mut out_len, line);
                if line_end < content.len() {
                    out_buf[out_len] = b'\n';
                    out_len += 1;
                }
            }
            line_start = line_end + 1;
        }

        if !found {
            let res = &out_buf[..out_len];
            let mut inserted_buf = [0u8; 2048];
            let mut inserted_len = 0usize;
            if let Some(pos) = find_subslice(res, b"[General]\n") {
                let split = pos + 10;
                copy_slice(&mut inserted_buf, &mut inserted_len, &res[..split]);
                copy_slice(&mut inserted_buf, &mut inserted_len, target_line);
                copy_slice(&mut inserted_buf, &mut inserted_len, &res[split..]);
                out_buf[..inserted_len].copy_from_slice(&inserted_buf[..inserted_len]);
                out_len = inserted_len;
            } else {
                copy_slice(&mut out_buf, &mut out_len, target_line);
            }
        }
    }

    let fd_out = syscall3(5 /* SYS_open */, path as usize, 577 /* O_WRONLY|O_CREAT|O_TRUNC */, 420 /* 0644 */);
    if fd_out >= 0 {
        syscall3(4 /* SYS_write */, fd_out as usize, out_buf.as_ptr() as usize, out_len);
        syscall1(6 /* SYS_close */, fd_out as usize);
        log_str(b"[libk5compat] Saved sync_media state to config.ini\n");
    }
}

unsafe fn patch_sync_media_instruction(enabled: bool) {
    let page = ADDR_SYNC_MEDIA & !0xfff;
    let ret = syscall3(125 /* SYS_mprotect */, page, 4096, 7 /* PROT_READ|WRITE|EXEC */);
    if ret < 0 {
        log_str(b"[libk5compat] mprotect failed!\n");
        return;
    }

    // Ensure ADDR_SERVICE (0x0022d0fa) is movs r1, #1 (0x2101 in Thumb little-endian -> [0x01, 0x21])
    let service_ptr = ADDR_SERVICE as *mut u8;
    *service_ptr = 0x01;
    *service_ptr.add(1) = 0x21;

    // Set ADDR_SYNC_MEDIA (0x0022d0ec):
    // Enabled: movs r7, #1 -> [0x01, 0x27]
    // Disabled: movs r7, #0 -> [0x00, 0x27]
    let media_ptr = ADDR_SYNC_MEDIA as *mut u8;
    *media_ptr = if enabled { 0x01 } else { 0x00 };
    *media_ptr.add(1) = 0x27;

    // Flush cache for ARM: syscall 0xf0002 (sys_cacheflush)
    core::arch::asm!(
        "svc 0",
        in("r7") 0xf0002usize,
        in("r0") ADDR_SYNC_MEDIA,
        in("r1") ADDR_SERVICE + 4,
        in("r2") 0usize,
    );

    syscall3(125 /* SYS_mprotect */, page, 4096, 5 /* PROT_READ|EXEC */);

    log_str(b"[libk5compat] Active sync_media instruction: ");
    if enabled {
        log_str(b"movs r7, #1 (Sync Media ON)\n");
    } else {
        log_str(b"movs r7, #0 (Sync Media OFF - Cards & Text only)\n");
    }
}

#[no_mangle]
pub unsafe extern "C" fn _init() {
    ensure_initialized();
}

unsafe extern "C" fn k5compat_init() {
    log_str(b"[libk5compat] Initializing Kindle Touch 5.3.7.3 compatibility runtime...\n");
    let is_enabled = read_config_sync_media();
    patch_sync_media_instruction(is_enabled);
}

// -------------------------------------------------------------
// GtkBuilder & UI Toggle Interceptor
// -------------------------------------------------------------

static mut SET_ACTIVE_FN: Option<unsafe extern "C" fn(usize, i32)> = None;
static mut GET_ACTIVE_FN: Option<unsafe extern "C" fn(usize) -> i32> = None;
static mut GTK_GET_OBJECT_FN: Option<unsafe extern "C" fn(usize, *const u8) -> usize> = None;
static mut G_SIGNAL_CONNECT_FN: Option<
    unsafe extern "C" fn(usize, *const u8, Option<unsafe extern "C" fn(usize, usize, usize)>, usize, usize, i32) -> usize,
> = None;
static mut REAL_BUILDER_ADD_FROM_STRING_FN: Option<
    unsafe extern "C" fn(usize, *const u8, usize, usize) -> u32,
> = None;

unsafe fn init_gtk_symbols() {
    if REAL_BUILDER_ADD_FROM_STRING_FN.is_none() {
        let gtk = dlopen(b"/usr/lib/libgtk-x11-2.0.so.0\0".as_ptr(), 1);
        if gtk != 0 {
            let sym_add = dlsym(gtk, b"gtk_builder_add_from_string\0".as_ptr());
            if sym_add != 0 {
                REAL_BUILDER_ADD_FROM_STRING_FN = Some(core::mem::transmute(sym_add));
            }
            let sym_get = dlsym(gtk, b"gtk_builder_get_object\0".as_ptr());
            if sym_get != 0 {
                GTK_GET_OBJECT_FN = Some(core::mem::transmute(sym_get));
            }
        }
    }

    if G_SIGNAL_CONNECT_FN.is_none() {
        let gobj = dlopen(b"/usr/lib/libgobject-2.0.so.0\0".as_ptr(), 1);
        if gobj != 0 {
            let sym_conn = dlsym(gobj, b"g_signal_connect_data\0".as_ptr());
            if sym_conn != 0 {
                G_SIGNAL_CONNECT_FN = Some(core::mem::transmute(sym_conn));
            }
        }
    }

    if SET_ACTIVE_FN.is_none() {
        let sym_set = dlsym(0, b"ink_row_toggle_button_set_active\0".as_ptr());
        if sym_set != 0 {
            SET_ACTIVE_FN = Some(core::mem::transmute(sym_set));
        } else {
            SET_ACTIVE_FN = Some(core::mem::transmute(0x0023a589usize));
        }
    }

    if GET_ACTIVE_FN.is_none() {
        let sym_get = dlsym(0, b"ink_row_toggle_button_get_active\0".as_ptr());
        if sym_get != 0 {
            GET_ACTIVE_FN = Some(core::mem::transmute(sym_get));
        } else {
            GET_ACTIVE_FN = Some(core::mem::transmute(0x0023a565usize));
        }
    }
}

unsafe extern "C" fn on_sync_media_toggled(widget: usize, _pspec: usize, _user_data: usize) {
    let get_fn = GET_ACTIVE_FN.unwrap_or(core::mem::transmute(0x0023a565usize));
    let active = get_fn(widget);
    log_str(b"[libk5compat] User tapped Sync Media toggle on screen -> ");
    if active != 0 {
        log_str(b"ON (true)\n");
    } else {
        log_str(b"OFF (false)\n");
    }
    write_config_sync_media(active != 0);
    patch_sync_media_instruction(active != 0);
}

#[no_mangle]
pub unsafe extern "C" fn gtk_builder_add_from_string(
    builder: usize,
    buffer: *const u8,
    length: usize,
    error: usize,
) -> u32 {
    ensure_initialized();
    init_gtk_symbols();

    let real_fn = match REAL_BUILDER_ADD_FROM_STRING_FN {
        Some(f) => f,
        None => return 0,
    };

    let orig_len = if length == usize::MAX || (length as isize) < 0 {
        cstr_len(buffer)
    } else {
        length
    };

    let content = core::slice::from_raw_parts(buffer, orig_len);
    let is_settings = find_subslice(content, b"sync_server_toggle").is_some();
    let has_toggle = find_subslice(content, b"sync_media_toggle").is_some();

    // If SettingsView and toggle XML not yet embedded in buffer, dynamically inject it:
    let res = if is_settings && !has_toggle {
        log_str(b"[libk5compat] Injecting sync_media_toggle into SettingsView template\n");
        static mut MOD_XML_BUF: [u8; 16384] = [0u8; 16384];

        if let Some(hbox2_pos) = find_subslice(content, b"id=\"hbox2\"") {
            let mut child_pos = hbox2_pos;
            while child_pos > 6 {
                if content[child_pos - 7..child_pos] == *b"<child>" {
                    child_pos -= 7;
                    break;
                }
                child_pos -= 1;
            }

            let snippet = b"<child><object class=\"InkRowToggleButton\" id=\"sync_media_toggle\"><property name=\"label\">Sync media</property><property name=\"description\">download images &amp; audio</property></object><packing><property name=\"expand\">False</property><property name=\"fill\">False</property></packing></child>";

            let mut out_len = 0usize;
            copy_slice(&mut MOD_XML_BUF, &mut out_len, &content[..child_pos]);
            copy_slice(&mut MOD_XML_BUF, &mut out_len, snippet);
            copy_slice(&mut MOD_XML_BUF, &mut out_len, &content[child_pos..]);
            if out_len < MOD_XML_BUF.len() {
                MOD_XML_BUF[out_len] = 0;
            }
            real_fn(builder, MOD_XML_BUF.as_ptr(), out_len, error)
        } else {
            real_fn(builder, buffer, length, error)
        }
    } else {
        real_fn(builder, buffer, length, error)
    };

    // If this was SettingsView, configure the toggle widget:
    if is_settings {
        if let Some(get_obj_fn) = GTK_GET_OBJECT_FN {
            let name = b"sync_media_toggle\0";
            let toggle = get_obj_fn(builder, name.as_ptr());
            if toggle != 0 {
                log_str(b"[libk5compat] Initialized sync_media_toggle widget in SettingsView\n");
                let is_enabled = read_config_sync_media();
                let set_fn = SET_ACTIVE_FN.unwrap_or(core::mem::transmute(0x0023a589usize));
                set_fn(toggle, if is_enabled { 1 } else { 0 });

                if let Some(connect_fn) = G_SIGNAL_CONNECT_FN {
                    let sig = b"notify::active\0";
                    connect_fn(toggle, sig.as_ptr(), Some(on_sync_media_toggled), toggle, 0, 0);
                }
            }
        }
    }

    res
}
