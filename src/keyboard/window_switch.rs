use base::message_proto::{key_event, ControlKey, KeyEvent, KeyboardMode};
use hbb_common::protobuf::EnumOrUnknown;

const MAC_VK_TAB: u32 = 0x30;
const MAC_VK_RIGHT_COMMAND: u32 = 0x36;
const MAC_VK_COMMAND: u32 = 0x37;
const MAC_VK_OPTION: u32 = 0x3A;
const MAC_VK_CONTROL: u32 = 0x3B;
const MAC_VK_RIGHT_OPTION: u32 = 0x3D;
const MAC_VK_RIGHT_CONTROL: u32 = 0x3E;

const WIN_SCANCODE_TAB: u32 = 0x0F;
const WIN_SCANCODE_CONTROL_LEFT: u32 = 0x1D;
const WIN_SCANCODE_ALT_LEFT: u32 = 0x38;
const WIN_SCANCODE_CONTROL_RIGHT: u32 = 0xE01D;
const WIN_SCANCODE_ALT_RIGHT: u32 = 0xE038;
const WIN_SCANCODE_META_LEFT: u32 = 0xE05B;
const WIN_SCANCODE_META_RIGHT: u32 = 0xE05C;

const MOD_A: u8 = 1 << 0;
const MOD_B: u8 = 1 << 1;
const MOD_C: u8 = 1 << 2;
const MOD_D: u8 = 1 << 3;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum Side {
    Left,
    Right,
}

#[derive(Default)]
pub(crate) struct WinAltTabToMacCmdTab {
    alt_down: Option<Side>,
    active: bool,
    other_modifiers_down: u8,
}

impl WinAltTabToMacCmdTab {
    pub(crate) fn transform(&mut self, evt: &KeyEvent) -> Vec<KeyEvent> {
        let mode = evt.mode.enum_value_or(KeyboardMode::Legacy);
        if let Some(side) = classify_mac_alt(evt, mode) {
            if evt.down {
                if self.active {
                    return Vec::new();
                }
                if self.other_modifiers_down == 0 && !has_ctrl_or_meta(&evt.modifiers) {
                    self.alt_down = Some(side);
                } else {
                    self.alt_down = None;
                }
                return vec![evt.clone()];
            } else {
                self.alt_down = None;
                if self.active {
                    self.active = false;
                    return vec![make_mac_cmd_event(mode, false)];
                }
                return vec![evt.clone()];
            }
        }

        if let Some(bit) = classify_mac_ctrl_or_meta(evt, mode) {
            if evt.down {
                self.other_modifiers_down |= bit;
            } else {
                self.other_modifiers_down &= !bit;
            }
            return vec![evt.clone()];
        }

        if self.active {
            return vec![rewrite_mac_active_event(evt, mode)];
        }

        if is_mac_tab_down(evt, mode)
            && self.other_modifiers_down == 0
            && !has_ctrl_or_meta(&evt.modifiers)
        {
            let side = self.alt_down.or_else(|| legacy_alt_side(&evt.modifiers));
            if let Some(side) = side {
                self.alt_down = Some(side);
                self.active = true;
                return vec![
                    make_mac_alt_event(mode, side, false),
                    make_mac_cmd_event(mode, true),
                    rewrite_mac_active_event(evt, mode),
                ];
            }
        }

        vec![evt.clone()]
    }

    pub(crate) fn reset(&mut self) {
        self.alt_down = None;
        self.active = false;
        self.other_modifiers_down = 0;
    }
}

#[derive(Default)]
pub(crate) struct MacCmdTabToWinAltTab {
    cmd_down: Option<Side>,
    active: bool,
    other_modifiers_down: u8,
}

impl MacCmdTabToWinAltTab {
    /// Returns `Some(events)` when the event(s) are already wire-ready and must bypass
    /// `modifier_swap::swap_key_event`; returns `None` to keep the normal swap path.
    pub(crate) fn intercept(&mut self, evt: &KeyEvent) -> Option<Vec<KeyEvent>> {
        let mode = evt.mode.enum_value_or(KeyboardMode::Legacy);
        if let Some(side) = classify_win_meta(evt, mode) {
            if evt.down {
                if self.active {
                    return Some(Vec::new());
                }
                if self.other_modifiers_down == 0 && !has_ctrl_or_alt(&evt.modifiers) {
                    self.cmd_down = Some(side);
                } else {
                    self.cmd_down = None;
                }
                return None;
            } else {
                self.cmd_down = None;
                if self.active {
                    self.active = false;
                    return Some(vec![make_win_alt_event(mode, false)]);
                }
                return None;
            }
        }

        if let Some(bit) = classify_win_ctrl_or_alt(evt, mode) {
            if evt.down {
                self.other_modifiers_down |= bit;
            } else {
                self.other_modifiers_down &= !bit;
            }
            return None;
        }

        if self.active {
            return Some(vec![rewrite_win_active_event(evt, mode)]);
        }

        if is_win_tab_down(evt, mode)
            && self.other_modifiers_down == 0
            && !has_ctrl_or_alt(&evt.modifiers)
        {
            let side = self.cmd_down.or_else(|| legacy_meta_side(&evt.modifiers));
            if let Some(side) = side {
                self.cmd_down = Some(side);
                self.active = true;
                return Some(vec![
                    make_win_ctrl_event(mode, side, false),
                    make_win_alt_event(mode, true),
                    rewrite_win_active_event(evt, mode),
                ]);
            }
        }

        None
    }

    pub(crate) fn reset(&mut self) {
        self.cmd_down = None;
        self.active = false;
        self.other_modifiers_down = 0;
    }
}

fn has_ctrl_or_meta(modifiers: &[EnumOrUnknown<ControlKey>]) -> bool {
    modifiers.iter().any(|ck| {
        matches!(
            ck.enum_value(),
            Ok(ControlKey::Control
                | ControlKey::RControl
                | ControlKey::Meta
                | ControlKey::RWin)
        )
    })
}

fn has_ctrl_or_alt(modifiers: &[EnumOrUnknown<ControlKey>]) -> bool {
    modifiers.iter().any(|ck| {
        matches!(
            ck.enum_value(),
            Ok(ControlKey::Control
                | ControlKey::RControl
                | ControlKey::Alt
                | ControlKey::RAlt
                | ControlKey::Option)
        )
    })
}

fn legacy_alt_side(modifiers: &[EnumOrUnknown<ControlKey>]) -> Option<Side> {
    for ck in modifiers {
        match ck.enum_value() {
            Ok(ControlKey::Alt | ControlKey::Option) => return Some(Side::Left),
            Ok(ControlKey::RAlt) => return Some(Side::Right),
            _ => {}
        }
    }
    None
}

fn legacy_meta_side(modifiers: &[EnumOrUnknown<ControlKey>]) -> Option<Side> {
    for ck in modifiers {
        match ck.enum_value() {
            Ok(ControlKey::Meta) => return Some(Side::Left),
            Ok(ControlKey::RWin) => return Some(Side::Right),
            _ => {}
        }
    }
    None
}

fn classify_mac_alt(evt: &KeyEvent, mode: KeyboardMode) -> Option<Side> {
    match (&evt.union, mode) {
        (Some(key_event::Union::ControlKey(ck)), _) => match ck.enum_value() {
            Ok(ControlKey::Alt | ControlKey::Option) => Some(Side::Left),
            Ok(ControlKey::RAlt) => Some(Side::Right),
            _ => None,
        },
        (Some(key_event::Union::Chr(code)), KeyboardMode::Map | KeyboardMode::Translate) => {
            match *code {
                MAC_VK_OPTION => Some(Side::Left),
                MAC_VK_RIGHT_OPTION => Some(Side::Right),
                _ => None,
            }
        }
        _ => None,
    }
}

fn classify_mac_ctrl_or_meta(evt: &KeyEvent, mode: KeyboardMode) -> Option<u8> {
    match (&evt.union, mode) {
        (Some(key_event::Union::ControlKey(ck)), _) => match ck.enum_value() {
            Ok(ControlKey::Control) => Some(MOD_A),
            Ok(ControlKey::RControl) => Some(MOD_B),
            Ok(ControlKey::Meta) => Some(MOD_C),
            Ok(ControlKey::RWin) => Some(MOD_D),
            _ => None,
        },
        (Some(key_event::Union::Chr(code)), KeyboardMode::Map | KeyboardMode::Translate) => {
            match *code {
                MAC_VK_CONTROL => Some(MOD_A),
                MAC_VK_RIGHT_CONTROL => Some(MOD_B),
                MAC_VK_COMMAND => Some(MOD_C),
                MAC_VK_RIGHT_COMMAND => Some(MOD_D),
                _ => None,
            }
        }
        _ => None,
    }
}

fn is_mac_tab_down(evt: &KeyEvent, mode: KeyboardMode) -> bool {
    if !evt.down {
        return false;
    }
    match (&evt.union, mode) {
        (Some(key_event::Union::ControlKey(ck)), _) => ck.enum_value() == Ok(ControlKey::Tab),
        (Some(key_event::Union::Chr(code)), KeyboardMode::Map | KeyboardMode::Translate) => {
            *code == MAC_VK_TAB
        }
        (Some(key_event::Union::Seq(seq)), KeyboardMode::Translate) => seq == "\t",
        _ => false,
    }
}

fn make_mac_alt_event(mode: KeyboardMode, side: Side, down: bool) -> KeyEvent {
    let mut evt = KeyEvent::new();
    evt.down = down;
    match mode {
        KeyboardMode::Map | KeyboardMode::Translate => {
            evt.mode = mode.into();
            evt.set_chr(match side {
                Side::Left => MAC_VK_OPTION,
                Side::Right => MAC_VK_RIGHT_OPTION,
            });
        }
        KeyboardMode::Legacy | KeyboardMode::Auto => {
            evt.mode = KeyboardMode::Legacy.into();
            evt.set_control_key(match side {
                Side::Left => ControlKey::Alt,
                Side::Right => ControlKey::RAlt,
            });
        }
    }
    evt
}

fn make_mac_cmd_event(mode: KeyboardMode, down: bool) -> KeyEvent {
    let mut evt = KeyEvent::new();
    evt.down = down;
    match mode {
        KeyboardMode::Map | KeyboardMode::Translate => {
            evt.mode = mode.into();
            evt.set_chr(MAC_VK_COMMAND);
        }
        KeyboardMode::Legacy | KeyboardMode::Auto => {
            evt.mode = KeyboardMode::Legacy.into();
            evt.set_control_key(ControlKey::Meta);
        }
    }
    evt
}

fn rewrite_mac_active_event(evt: &KeyEvent, mode: KeyboardMode) -> KeyEvent {
    let mut out = evt.clone();
    if mode == KeyboardMode::Translate {
        if let Some(key_event::Union::Seq(seq)) = &out.union {
            if seq == "\t" {
                out.set_chr(MAC_VK_TAB);
            }
        }
    }
    for modifier in &mut out.modifiers {
        if matches!(
            modifier.enum_value(),
            Ok(ControlKey::Alt | ControlKey::RAlt | ControlKey::Option)
        ) {
            *modifier = ControlKey::Meta.into();
        }
    }
    out
}

fn classify_win_meta(evt: &KeyEvent, mode: KeyboardMode) -> Option<Side> {
    match (&evt.union, mode) {
        (Some(key_event::Union::ControlKey(ck)), _) => match ck.enum_value() {
            Ok(ControlKey::Meta) => Some(Side::Left),
            Ok(ControlKey::RWin) => Some(Side::Right),
            _ => None,
        },
        (Some(key_event::Union::Chr(code)), KeyboardMode::Map | KeyboardMode::Translate) => {
            match *code {
                WIN_SCANCODE_META_LEFT => Some(Side::Left),
                WIN_SCANCODE_META_RIGHT => Some(Side::Right),
                _ => None,
            }
        }
        _ => None,
    }
}

fn classify_win_ctrl_or_alt(evt: &KeyEvent, mode: KeyboardMode) -> Option<u8> {
    match (&evt.union, mode) {
        (Some(key_event::Union::ControlKey(ck)), _) => match ck.enum_value() {
            Ok(ControlKey::Control) => Some(MOD_A),
            Ok(ControlKey::RControl) => Some(MOD_B),
            Ok(ControlKey::Alt | ControlKey::Option) => Some(MOD_C),
            Ok(ControlKey::RAlt) => Some(MOD_D),
            _ => None,
        },
        (Some(key_event::Union::Chr(code)), KeyboardMode::Map | KeyboardMode::Translate) => {
            match *code {
                WIN_SCANCODE_CONTROL_LEFT => Some(MOD_A),
                WIN_SCANCODE_CONTROL_RIGHT => Some(MOD_B),
                WIN_SCANCODE_ALT_LEFT => Some(MOD_C),
                WIN_SCANCODE_ALT_RIGHT => Some(MOD_D),
                _ => None,
            }
        }
        _ => None,
    }
}

fn is_win_tab_down(evt: &KeyEvent, mode: KeyboardMode) -> bool {
    if !evt.down {
        return false;
    }
    match (&evt.union, mode) {
        (Some(key_event::Union::ControlKey(ck)), _) => ck.enum_value() == Ok(ControlKey::Tab),
        (Some(key_event::Union::Chr(code)), KeyboardMode::Map | KeyboardMode::Translate) => {
            *code == WIN_SCANCODE_TAB
        }
        (Some(key_event::Union::Seq(seq)), KeyboardMode::Translate) => seq == "\t",
        _ => false,
    }
}

fn make_win_ctrl_event(mode: KeyboardMode, side: Side, down: bool) -> KeyEvent {
    let mut evt = KeyEvent::new();
    evt.down = down;
    match mode {
        KeyboardMode::Map | KeyboardMode::Translate => {
            evt.mode = mode.into();
            evt.set_chr(match side {
                Side::Left => WIN_SCANCODE_CONTROL_LEFT,
                Side::Right => WIN_SCANCODE_CONTROL_RIGHT,
            });
        }
        KeyboardMode::Legacy | KeyboardMode::Auto => {
            evt.mode = KeyboardMode::Legacy.into();
            evt.set_control_key(match side {
                Side::Left => ControlKey::Control,
                Side::Right => ControlKey::RControl,
            });
        }
    }
    evt
}

fn make_win_alt_event(mode: KeyboardMode, down: bool) -> KeyEvent {
    let mut evt = KeyEvent::new();
    evt.down = down;
    match mode {
        KeyboardMode::Map | KeyboardMode::Translate => {
            evt.mode = mode.into();
            evt.set_chr(WIN_SCANCODE_ALT_LEFT);
        }
        KeyboardMode::Legacy | KeyboardMode::Auto => {
            evt.mode = KeyboardMode::Legacy.into();
            evt.set_control_key(ControlKey::Alt);
        }
    }
    evt
}

fn rewrite_win_active_event(evt: &KeyEvent, mode: KeyboardMode) -> KeyEvent {
    let mut out = evt.clone();
    if mode == KeyboardMode::Translate {
        if let Some(key_event::Union::Seq(seq)) = &out.union {
            if seq == "\t" {
                out.set_chr(WIN_SCANCODE_TAB);
            }
        }
    }
    for modifier in &mut out.modifiers {
        if matches!(modifier.enum_value(), Ok(ControlKey::Meta | ControlKey::RWin)) {
            *modifier = ControlKey::Alt.into();
        }
    }
    out
}

#[cfg(target_os = "macos")]
mod macos_runtime {
    use super::{MacCmdTabToWinAltTab, WinAltTabToMacCmdTab};
    use base::message_proto::KeyEvent;
    use std::sync::Mutex;

    lazy_static::lazy_static! {
        static ref SERVER_ALT_TAB: Mutex<WinAltTabToMacCmdTab> = Mutex::new(WinAltTabToMacCmdTab::default());
        static ref CLIENT_CMD_TAB: Mutex<MacCmdTabToWinAltTab> = Mutex::new(MacCmdTabToWinAltTab::default());
    }

    pub(crate) fn transform_macos_server_key(evt: &KeyEvent) -> Vec<KeyEvent> {
        SERVER_ALT_TAB.lock().unwrap().transform(evt)
    }

    pub(crate) fn reset_macos_server_state() {
        SERVER_ALT_TAB.lock().unwrap().reset();
    }

    pub(crate) fn intercept_macos_client_key(evt: &KeyEvent) -> Option<Vec<KeyEvent>> {
        CLIENT_CMD_TAB.lock().unwrap().intercept(evt)
    }

    pub(crate) fn reset_macos_client_state() {
        CLIENT_CMD_TAB.lock().unwrap().reset();
    }
}

#[cfg(target_os = "macos")]
pub(crate) use macos_runtime::{
    intercept_macos_client_key, reset_macos_client_state, reset_macos_server_state,
    transform_macos_server_key,
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
    fn win_alt_tab_maps_to_mac_cmd_tab_in_map_and_legacy_modes() {
        let mut remapper = WinAltTabToMacCmdTab::default();

        // Map mode: Alt down -> Tab down -> Tab up -> Alt up
        let out = remapper.transform(&map_code(MAC_VK_OPTION, true));
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].chr(), MAC_VK_OPTION);

        let out = remapper.transform(&map_code(MAC_VK_TAB, true));
        assert_eq!(out.len(), 3);
        assert_eq!((out[0].chr(), out[0].down), (MAC_VK_OPTION, false));
        assert_eq!((out[1].chr(), out[1].down), (MAC_VK_COMMAND, true));
        assert_eq!((out[2].chr(), out[2].down), (MAC_VK_TAB, true));

        let out = remapper.transform(&map_code(MAC_VK_TAB, false));
        assert_eq!(out.len(), 1);
        assert_eq!((out[0].chr(), out[0].down), (MAC_VK_TAB, false));

        // Repeat Alt down is suppressed while active
        assert!(remapper.transform(&map_code(MAC_VK_OPTION, true)).is_empty());

        let out = remapper.transform(&map_code(MAC_VK_OPTION, false));
        assert_eq!(out.len(), 1);
        assert_eq!((out[0].chr(), out[0].down), (MAC_VK_COMMAND, false));

        // Legacy mode: Alt + Shift + Tab preserves Shift and replaces Alt -> Meta
        let _ = remapper.transform(&legacy_ck(ControlKey::Alt, true, &[]));
        let out = remapper.transform(&legacy_ck(
            ControlKey::Tab,
            true,
            &[ControlKey::Alt, ControlKey::Shift],
        ));
        assert_eq!(out.len(), 3);
        assert_eq!((out[0].control_key(), out[0].down), (ControlKey::Alt, false));
        assert_eq!((out[1].control_key(), out[1].down), (ControlKey::Meta, true));
        assert_eq!(
            out[2].modifiers,
            vec![ControlKey::Meta.into(), ControlKey::Shift.into()]
        );

        let out = remapper.transform(&legacy_ck(ControlKey::Alt, false, &[]));
        assert_eq!(out.len(), 1);
        assert_eq!((out[0].control_key(), out[0].down), (ControlKey::Meta, false));
    }

    #[test]
    fn non_tab_alt_combos_and_ctrl_alt_tab_pass_through() {
        let mut remapper = WinAltTabToMacCmdTab::default();

        // Alt + F4 passes through untouched
        let out = remapper.transform(&legacy_ck(ControlKey::Alt, true, &[]));
        assert_eq!(out[0].control_key(), ControlKey::Alt);
        let out = remapper.transform(&legacy_ck(ControlKey::F4, true, &[ControlKey::Alt]));
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].modifiers, vec![ControlKey::Alt.into()]);
        let out = remapper.transform(&legacy_ck(ControlKey::Alt, false, &[]));
        assert_eq!(out[0].control_key(), ControlKey::Alt);

        // Ctrl + Alt + Tab is not rewritten
        let _ = remapper.transform(&map_code(MAC_VK_CONTROL, true));
        let _ = remapper.transform(&map_code(MAC_VK_OPTION, true));
        let out = remapper.transform(&map_code(MAC_VK_TAB, true));
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].chr(), MAC_VK_TAB);
    }

    #[test]
    fn mac_cmd_tab_maps_to_win_alt_tab_and_releases_swapped_ctrl() {
        let mut remapper = MacCmdTabToWinAltTab::default();

        // Cmd down goes through normal swap_modifier_key (becomes Ctrl down on Windows)
        assert!(remapper.intercept(&map_code(WIN_SCANCODE_META_LEFT, true)).is_none());

        // Tab down switches Windows from Ctrl -> Alt + Tab
        let out = remapper
            .intercept(&map_code(WIN_SCANCODE_TAB, true))
            .expect("Cmd+Tab should activate");
        assert_eq!(out.len(), 3);
        assert_eq!((out[0].chr(), out[0].down), (WIN_SCANCODE_CONTROL_LEFT, false));
        assert_eq!((out[1].chr(), out[1].down), (WIN_SCANCODE_ALT_LEFT, true));
        assert_eq!((out[2].chr(), out[2].down), (WIN_SCANCODE_TAB, true));

        // Cmd up releases Alt on Windows
        let out = remapper
            .intercept(&map_code(WIN_SCANCODE_META_LEFT, false))
            .expect("Cmd up should release Alt");
        assert_eq!(out.len(), 1);
        assert_eq!((out[0].chr(), out[0].down), (WIN_SCANCODE_ALT_LEFT, false));
    }
}
