use base::message_proto::{key_event, ControlKey, KeyEvent, KeyboardMode};
use std::time::{Duration, Instant};

const MAX_SHIFT_TAP_DURATION: Duration = Duration::from_millis(500);
const FOCUS_SETTLE_DELAY: Duration = Duration::from_millis(250);

const MAC_VK_RIGHT_COMMAND: u32 = 0x36;
const MAC_VK_COMMAND: u32 = 0x37;
const MAC_VK_SHIFT: u32 = 0x38;
const MAC_VK_OPTION: u32 = 0x3A;
const MAC_VK_CONTROL: u32 = 0x3B;
const MAC_VK_RIGHT_SHIFT: u32 = 0x3C;
const MAC_VK_RIGHT_OPTION: u32 = 0x3D;
const MAC_VK_RIGHT_CONTROL: u32 = 0x3E;

const WIN_SCANCODE_SHIFT_LEFT: u32 = 0x2A;

const MOD_CTRL_L: u8 = 1 << 0;
const MOD_CTRL_R: u8 = 1 << 1;
const MOD_ALT_L: u8 = 1 << 2;
const MOD_ALT_R: u8 = 1 << 3;
const MOD_META_L: u8 = 1 << 4;
const MOD_META_R: u8 = 1 << 5;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum ShiftSide {
    Left,
    Right,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum MacKeyClass {
    Shift(ShiftSide),
    OtherModifier(u8),
    OtherKey,
}

#[derive(Default)]
pub(crate) struct ShiftTapTracker {
    pending: Option<(ShiftSide, Instant)>,
    other_modifiers_down: u8,
}

impl ShiftTapTracker {
    pub(crate) fn on_key_event(&mut self, evt: &KeyEvent, now: Instant) -> bool {
        let non_shift_mod_in_evt = has_non_shift_modifier(evt);
        match classify_mac_key(evt) {
            MacKeyClass::Shift(side) => {
                if evt.down {
                    if self.other_modifiers_down != 0 || non_shift_mod_in_evt {
                        self.pending = None;
                    } else {
                        match self.pending {
                            None => self.pending = Some((side, now)),
                            Some((prev, _)) if prev != side => self.pending = None,
                            Some(_) => {}
                        }
                    }
                    false
                } else {
                    let pending = self.pending.take();
                    matches!(
                        pending,
                        Some((prev, pressed_at))
                            if prev == side
                                && self.other_modifiers_down == 0
                                && !non_shift_mod_in_evt
                                && now.saturating_duration_since(pressed_at)
                                    <= MAX_SHIFT_TAP_DURATION
                    )
                }
            }
            MacKeyClass::OtherModifier(bit) => {
                if evt.down {
                    self.other_modifiers_down |= bit;
                } else {
                    self.other_modifiers_down &= !bit;
                }
                self.pending = None;
                false
            }
            MacKeyClass::OtherKey => {
                self.pending = None;
                false
            }
        }
    }

    pub(crate) fn on_mouse_activity(&mut self) {
        self.pending = None;
    }

    pub(crate) fn reset(&mut self) {
        self.pending = None;
        self.other_modifiers_down = 0;
    }
}

fn has_non_shift_modifier(evt: &KeyEvent) -> bool {
    evt.modifiers.iter().any(|ck| {
        matches!(
            ck.enum_value(),
            Ok(ControlKey::Control
                | ControlKey::RControl
                | ControlKey::Alt
                | ControlKey::RAlt
                | ControlKey::Meta
                | ControlKey::RWin)
        )
    })
}

fn classify_mac_key(evt: &KeyEvent) -> MacKeyClass {
    match (&evt.union, evt.mode.enum_value_or(KeyboardMode::Legacy)) {
        (Some(key_event::Union::ControlKey(ck)), _) => match ck.enum_value() {
            Ok(ControlKey::Shift) => MacKeyClass::Shift(ShiftSide::Left),
            Ok(ControlKey::RShift) => MacKeyClass::Shift(ShiftSide::Right),
            Ok(ControlKey::Control) => MacKeyClass::OtherModifier(MOD_CTRL_L),
            Ok(ControlKey::RControl) => MacKeyClass::OtherModifier(MOD_CTRL_R),
            Ok(ControlKey::Alt | ControlKey::Option) => MacKeyClass::OtherModifier(MOD_ALT_L),
            Ok(ControlKey::RAlt) => MacKeyClass::OtherModifier(MOD_ALT_R),
            Ok(ControlKey::Meta) => MacKeyClass::OtherModifier(MOD_META_L),
            Ok(ControlKey::RWin) => MacKeyClass::OtherModifier(MOD_META_R),
            _ => MacKeyClass::OtherKey,
        },
        (Some(key_event::Union::Chr(code)), KeyboardMode::Map | KeyboardMode::Translate) => {
            match *code {
                MAC_VK_SHIFT => MacKeyClass::Shift(ShiftSide::Left),
                MAC_VK_RIGHT_SHIFT => MacKeyClass::Shift(ShiftSide::Right),
                MAC_VK_CONTROL => MacKeyClass::OtherModifier(MOD_CTRL_L),
                MAC_VK_RIGHT_CONTROL => MacKeyClass::OtherModifier(MOD_CTRL_R),
                MAC_VK_OPTION => MacKeyClass::OtherModifier(MOD_ALT_L),
                MAC_VK_RIGHT_OPTION => MacKeyClass::OtherModifier(MOD_ALT_R),
                MAC_VK_COMMAND => MacKeyClass::OtherModifier(MOD_META_L),
                MAC_VK_RIGHT_COMMAND => MacKeyClass::OtherModifier(MOD_META_R),
                _ => MacKeyClass::OtherKey,
            }
        }
        _ => MacKeyClass::OtherKey,
    }
}

pub(crate) fn select_macos_toggle_target(
    current_id: &str,
    current_is_ascii: bool,
    sources: &[(&str, bool)],
    last_ime_id: Option<&str>,
) -> Option<usize> {
    if !current_is_ascii {
        // Third-party macOS IMEs (e.g. Sogou, WeType, Rime) handle Shift internally.
        if !current_id.starts_with("com.apple.") {
            return None;
        }
        return sources
            .iter()
            .position(|(id, is_ascii)| {
                *is_ascii && *id != current_id && *id == "com.apple.keylayout.ABC"
            })
            .or_else(|| {
                sources
                    .iter()
                    .position(|(id, is_ascii)| *is_ascii && *id != current_id)
            });
    }

    if let Some(last) = last_ime_id {
        if let Some(idx) = sources
            .iter()
            .position(|(id, is_ascii)| !*is_ascii && *id == last)
        {
            return Some(idx);
        }
    }

    sources
        .iter()
        .position(|(id, is_ascii)| !*is_ascii && id.starts_with("com.apple."))
        .or_else(|| sources.iter().position(|(_, is_ascii)| !*is_ascii))
}

#[derive(Default)]
pub(crate) struct MacInputSourceSyncGate {
    focused_since: Option<Instant>,
    last_source_id: Option<String>,
}

impl MacInputSourceSyncGate {
    pub(crate) fn on_focus_change(
        &mut self,
        focused: bool,
        current_source_id: Option<String>,
        now: Instant,
    ) {
        if focused {
            if self.focused_since.is_none() {
                self.focused_since = Some(now);
            }
        } else {
            self.focused_since = None;
        }
        if current_source_id.is_some() {
            self.last_source_id = current_source_id;
        }
    }

    pub(crate) fn on_source_changed(&mut self, new_source_id: &str, now: Instant) -> bool {
        if self.last_source_id.as_deref() == Some(new_source_id) {
            return false;
        }
        self.last_source_id = Some(new_source_id.to_owned());
        let Some(since) = self.focused_since else {
            return false;
        };
        now.saturating_duration_since(since) >= FOCUS_SETTLE_DELAY
    }
}

pub(crate) fn windows_shift_tap_events(mode: KeyboardMode) -> [KeyEvent; 2] {
    let make = |down: bool| {
        let mut evt = KeyEvent::new();
        evt.down = down;
        match mode {
            KeyboardMode::Map | KeyboardMode::Translate => {
                evt.mode = mode.into();
                evt.set_chr(WIN_SCANCODE_SHIFT_LEFT);
            }
            KeyboardMode::Legacy | KeyboardMode::Auto => {
                evt.mode = KeyboardMode::Legacy.into();
                evt.set_control_key(ControlKey::Shift);
            }
        }
        evt
    };
    [make(true), make(false)]
}

#[cfg(target_os = "macos")]
mod macos_runtime {
    use super::{
        MacInputSourceSyncGate, ShiftTapTracker, windows_shift_tap_events,
    };
    use base::message_proto::KeyEvent;
    use dispatch::Queue;
    use hbb_common::log;
    use std::{
        ffi::c_void,
        sync::{
            atomic::{AtomicBool, Ordering},
            Mutex,
        },
        time::Instant,
    };

    lazy_static::lazy_static! {
        static ref SERVER_SHIFT_TAP: Mutex<ShiftTapTracker> = Mutex::new(ShiftTapTracker::default());
        static ref CLIENT_SOURCE_GATE: Mutex<MacInputSourceSyncGate> = Mutex::new(MacInputSourceSyncGate::default());
    }

    static CLIENT_OBSERVER_REGISTERED: AtomicBool = AtomicBool::new(false);

    pub(crate) fn on_macos_server_key(evt: &KeyEvent, peer_is_windows: bool) {
        let should_toggle = {
            let mut tracker = SERVER_SHIFT_TAP.lock().unwrap();
            if peer_is_windows {
                tracker.on_key_event(evt, Instant::now())
            } else {
                tracker.on_mouse_activity();
                false
            }
        };
        if should_toggle {
            let switched = crate::platform::macos::toggle_input_source();
            log::trace!("Windows Shift tap on macOS server: toggled={switched}");
        }
    }

    pub(crate) fn on_macos_server_mouse() {
        SERVER_SHIFT_TAP.lock().unwrap().on_mouse_activity();
    }

    pub(crate) fn reset_macos_server_state() {
        SERVER_SHIFT_TAP.lock().unwrap().reset();
    }

    pub(crate) fn on_macos_client_grab_change(focused: bool) {
        let now = Instant::now();
        Queue::main().exec_async(move || {
            let current_id = crate::platform::macos::current_input_source_id();
            CLIENT_SOURCE_GATE
                .lock()
                .unwrap()
                .on_focus_change(focused, current_id, now);
        });
    }

    extern "C" fn on_input_source_changed_cb(
        _center: *mut c_void,
        _observer: *mut c_void,
        _name: *const c_void,
        _object: *const c_void,
        _user_info: *const c_void,
    ) {
        let Some(new_id) = crate::platform::macos::current_input_source_id() else {
            return;
        };
        let should_sync = CLIENT_SOURCE_GATE
            .lock()
            .unwrap()
            .on_source_changed(&new_id, Instant::now());
        if !should_sync {
            return;
        }
        if !crate::keyboard::is_keyboard_hooked() {
            return;
        }
        if !crate::keyboard::get_peer_platform().eq_ignore_ascii_case("windows") {
            return;
        }
        if !crate::keyboard::is_allow_swap_key_enabled() {
            return;
        }
        let mode = crate::keyboard::get_keyboard_mode_enum(&crate::keyboard::get_keyboard_mode());
        for evt in windows_shift_tap_events(mode) {
            crate::keyboard::send_key_event(&evt);
        }
    }

    pub(crate) fn start_macos_client_observer() {
        if CLIENT_OBSERVER_REGISTERED
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            return;
        }
        Queue::main().exec_async(|| {
            let current_id = crate::platform::macos::current_input_source_id();
            CLIENT_SOURCE_GATE.lock().unwrap().on_focus_change(
                crate::keyboard::is_keyboard_hooked(),
                current_id,
                Instant::now(),
            );
            crate::platform::macos::register_input_source_change_observer(
                on_input_source_changed_cb,
            );
        });
    }
}

#[cfg(target_os = "macos")]
pub(crate) use macos_runtime::{
    on_macos_client_grab_change, on_macos_server_key, on_macos_server_mouse,
    reset_macos_server_state, start_macos_client_observer,
};

#[cfg(test)]
mod tests {
    use super::*;

    fn legacy_ck(ck: ControlKey, down: bool, mods: &[ControlKey]) -> KeyEvent {
        let mut evt = KeyEvent::new();
        evt.mode = KeyboardMode::Legacy.into();
        evt.down = down;
        evt.set_control_key(ck);
        evt.modifiers = mods.iter().copied().map(Into::into).collect();
        evt
    }

    fn map_code(code: u32, down: bool) -> KeyEvent {
        let mut evt = KeyEvent::new();
        evt.mode = KeyboardMode::Map.into();
        evt.down = down;
        evt.set_chr(code);
        evt
    }

    #[test]
    fn standalone_shift_tap_triggers_in_legacy_and_map_modes() {
        let mut tracker = ShiftTapTracker::default();
        let t0 = Instant::now();

        assert!(!tracker.on_key_event(&legacy_ck(ControlKey::Shift, true, &[]), t0));
        assert!(tracker.on_key_event(
            &legacy_ck(ControlKey::Shift, false, &[]),
            t0 + Duration::from_millis(80)
        ));

        assert!(!tracker.on_key_event(&map_code(MAC_VK_RIGHT_SHIFT, true), t0));
        assert!(tracker.on_key_event(
            &map_code(MAC_VK_RIGHT_SHIFT, false),
            t0 + Duration::from_millis(120)
        ));
    }

    #[test]
    fn shift_combo_mouse_or_long_hold_does_not_trigger() {
        let mut tracker = ShiftTapTracker::default();
        let t0 = Instant::now();

        // Shift + letter
        assert!(!tracker.on_key_event(&map_code(MAC_VK_SHIFT, true), t0));
        assert!(!tracker.on_key_event(&map_code(0x00, true), t0 + Duration::from_millis(20)));
        assert!(!tracker.on_key_event(&map_code(MAC_VK_SHIFT, false), t0 + Duration::from_millis(40)));

        // Ctrl held before Shift
        assert!(!tracker.on_key_event(&map_code(MAC_VK_CONTROL, true), t0));
        assert!(!tracker.on_key_event(&map_code(MAC_VK_SHIFT, true), t0 + Duration::from_millis(10)));
        assert!(!tracker.on_key_event(&map_code(MAC_VK_SHIFT, false), t0 + Duration::from_millis(30)));
        assert!(!tracker.on_key_event(&map_code(MAC_VK_CONTROL, false), t0 + Duration::from_millis(40)));

        // Shift + mouse click
        assert!(!tracker.on_key_event(&map_code(MAC_VK_SHIFT, true), t0));
        tracker.on_mouse_activity();
        assert!(!tracker.on_key_event(&map_code(MAC_VK_SHIFT, false), t0 + Duration::from_millis(50)));

        // Long hold (> 500ms)
        assert!(!tracker.on_key_event(&map_code(MAC_VK_SHIFT, true), t0));
        assert!(!tracker.on_key_event(
            &map_code(MAC_VK_SHIFT, false),
            t0 + Duration::from_millis(700)
        ));
    }

    #[test]
    fn macos_toggle_target_handles_apple_and_third_party_imes() {
        let sources = [
            ("com.apple.keylayout.ABC", true),
            ("com.apple.inputmethod.SCIM.ITABC", false),
            ("com.apple.inputmethod.TCIM.Pinyin", false),
        ];
        assert_eq!(
            select_macos_toggle_target("com.apple.inputmethod.SCIM.ITABC", false, &sources, None),
            Some(0)
        );
        assert_eq!(
            select_macos_toggle_target(
                "com.apple.keylayout.ABC",
                true,
                &sources,
                Some("com.apple.inputmethod.TCIM.Pinyin")
            ),
            Some(2)
        );

        let third_party = [
            ("com.apple.keylayout.ABC", true),
            ("com.sogou.inputmethod.sogou.pinyin", false),
        ];
        assert_eq!(
            select_macos_toggle_target(
                "com.sogou.inputmethod.sogou.pinyin",
                false,
                &third_party,
                None
            ),
            None
        );

        let english_only = [("com.apple.keylayout.ABC", true)];
        assert_eq!(
            select_macos_toggle_target("com.apple.keylayout.ABC", true, &english_only, None),
            None
        );
    }

    #[test]
    fn mac_client_source_gate_waits_for_focus_settle_and_dedups() {
        let mut gate = MacInputSourceSyncGate::default();
        let t0 = Instant::now();

        gate.on_focus_change(true, Some("com.apple.keylayout.ABC".into()), t0);
        // Too soon after focus gain (auto-restore window)
        assert!(!gate.on_source_changed(
            "com.apple.inputmethod.SCIM.ITABC",
            t0 + Duration::from_millis(50)
        ));
        // Duplicate notification after settle
        assert!(!gate.on_source_changed(
            "com.apple.inputmethod.SCIM.ITABC",
            t0 + Duration::from_millis(300)
        ));
        // Real user toggle after settle
        assert!(gate.on_source_changed(
            "com.apple.keylayout.ABC",
            t0 + Duration::from_millis(400)
        ));
        // Unfocused does not trigger
        gate.on_focus_change(false, Some("com.apple.keylayout.ABC".into()), t0 + Duration::from_millis(500));
        assert!(!gate.on_source_changed(
            "com.apple.inputmethod.SCIM.ITABC",
            t0 + Duration::from_millis(800)
        ));

        let map_evts = windows_shift_tap_events(KeyboardMode::Map);
        assert_eq!(map_evts[0].chr(), WIN_SCANCODE_SHIFT_LEFT);
        assert!(map_evts[0].down);
        assert!(!map_evts[1].down);

        let legacy_evts = windows_shift_tap_events(KeyboardMode::Legacy);
        assert_eq!(legacy_evts[0].control_key(), ControlKey::Shift);
        assert!(legacy_evts[0].down);
        assert!(!legacy_evts[1].down);
    }
}
