use core_foundation::{
    array::{CFArrayGetCount, CFArrayGetValueAtIndex, CFArrayRef},
    base::{CFRelease, CFType, CFTypeRef, TCFType},
    boolean::{CFBoolean, CFBooleanRef},
    dictionary::{CFDictionary, CFDictionaryRef},
    string::{CFString, CFStringRef},
};
use std::{ffi::c_void, ptr, sync::Mutex};

type TISInputSourceRef = *const c_void;
type CFNotificationCenterRef = *mut c_void;
type OSStatus = i32;

const CF_NOTIFICATION_SUSPENSION_BEHAVIOR_DELIVER_IMMEDIATELY: isize = 4;

#[link(name = "Carbon", kind = "framework")]
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    static kTISPropertyInputSourceCategory: CFStringRef;
    static kTISCategoryKeyboardInputSource: CFStringRef;
    static kTISPropertyInputSourceIsSelectCapable: CFStringRef;
    static kTISPropertyInputSourceIsEnabled: CFStringRef;
    static kTISPropertyInputSourceIsASCIICapable: CFStringRef;
    static kTISPropertyInputSourceID: CFStringRef;
    static kTISNotifySelectedKeyboardInputSourceChanged: CFStringRef;

    fn TISCopyCurrentKeyboardInputSource() -> TISInputSourceRef;
    fn TISCreateInputSourceList(
        properties: CFDictionaryRef,
        include_all_installed: u8,
    ) -> CFArrayRef;
    fn TISGetInputSourceProperty(
        input_source: TISInputSourceRef,
        property_key: CFStringRef,
    ) -> *const c_void;
    fn TISSelectInputSource(input_source: TISInputSourceRef) -> OSStatus;

    fn CFNotificationCenterGetDistributedCenter() -> CFNotificationCenterRef;
    fn CFNotificationCenterAddObserver(
        center: CFNotificationCenterRef,
        observer: *const c_void,
        call_back: extern "C" fn(
            *mut c_void,
            *mut c_void,
            *const c_void,
            *const c_void,
            *const c_void,
        ),
        name: CFStringRef,
        object: *const c_void,
        suspension_behavior: isize,
    );
}

static LAST_IME_ID: Mutex<Option<String>> = Mutex::new(None);
static OBSERVER_TOKEN: u8 = 0;

unsafe fn source_id(source: TISInputSourceRef) -> Option<String> {
    let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) as CFStringRef;
    if raw.is_null() {
        return None;
    }
    Some(CFString::wrap_under_get_rule(raw).to_string())
}

unsafe fn source_is_ascii(source: TISInputSourceRef) -> bool {
    let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
        as CFBooleanRef;
    !raw.is_null() && bool::from(CFBoolean::wrap_under_get_rule(raw))
}

pub(crate) fn current_input_source_id() -> Option<String> {
    unsafe {
        let current = TISCopyCurrentKeyboardInputSource();
        if current.is_null() {
            return None;
        }
        let id = source_id(current);
        CFRelease(current);
        id
    }
}

pub(crate) fn toggle_input_source() -> bool {
    unsafe {
        let current = TISCopyCurrentKeyboardInputSource();
        if current.is_null() {
            return false;
        }
        let current_id = source_id(current).unwrap_or_default();
        let current_is_ascii = source_is_ascii(current);
        CFRelease(current);

        if !current_is_ascii && current_id.starts_with("com.apple.") {
            *LAST_IME_ID.lock().unwrap() = Some(current_id.clone());
        }

        let pairs: [(CFString, CFType); 3] = [
            (
                CFString::wrap_under_get_rule(kTISPropertyInputSourceCategory),
                CFString::wrap_under_get_rule(kTISCategoryKeyboardInputSource).as_CFType(),
            ),
            (
                CFString::wrap_under_get_rule(kTISPropertyInputSourceIsSelectCapable),
                CFBoolean::true_value().as_CFType(),
            ),
            (
                CFString::wrap_under_get_rule(kTISPropertyInputSourceIsEnabled),
                CFBoolean::true_value().as_CFType(),
            ),
        ];
        let filter = CFDictionary::from_CFType_pairs(&pairs);

        let list = TISCreateInputSourceList(filter.as_concrete_TypeRef(), 0);
        if list.is_null() {
            return false;
        }

        let count = CFArrayGetCount(list);
        let mut entries: Vec<(TISInputSourceRef, String, bool)> = Vec::with_capacity(count as usize);
        for i in 0..count {
            let src = CFArrayGetValueAtIndex(list, i) as TISInputSourceRef;
            if src.is_null() {
                continue;
            }
            if let Some(id) = source_id(src) {
                let is_ascii = source_is_ascii(src);
                entries.push((src, id, is_ascii));
            }
        }

        let view: Vec<(&str, bool)> = entries
            .iter()
            .map(|(_, id, is_ascii)| (id.as_str(), *is_ascii))
            .collect();
        let last_ime = LAST_IME_ID.lock().unwrap().clone();
        let switched = match crate::keyboard::ime_switch::select_macos_toggle_target(
            &current_id,
            current_is_ascii,
            &view,
            last_ime.as_deref(),
        ) {
            Some(idx) => {
                let (target_src, ref target_id, target_is_ascii) = entries[idx];
                let status = TISSelectInputSource(target_src);
                if status == 0 && !target_is_ascii {
                    *LAST_IME_ID.lock().unwrap() = Some(target_id.clone());
                }
                status == 0
            }
            None => false,
        };

        CFRelease(list as CFTypeRef);
        switched
    }
}

pub(crate) fn register_input_source_change_observer(
    callback: extern "C" fn(
        *mut c_void,
        *mut c_void,
        *const c_void,
        *const c_void,
        *const c_void,
    ),
) {
    unsafe {
        let center = CFNotificationCenterGetDistributedCenter();
        if center.is_null() {
            return;
        }
        CFNotificationCenterAddObserver(
            center,
            &OBSERVER_TOKEN as *const u8 as *const c_void,
            callback,
            kTISNotifySelectedKeyboardInputSourceChanged,
            ptr::null(),
            CF_NOTIFICATION_SUSPENSION_BEHAVIOR_DELIVER_IMMEDIATELY,
        );
    }
}
