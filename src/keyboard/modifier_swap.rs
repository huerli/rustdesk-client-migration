use base::{
    config::keys::OPTION_SWAP_CONTROL_COMMAND_KEY,
    message_proto::{key_event, ControlKey, KeyEvent, KeyboardMode},
};
use hbb_common::{config::PeerConfig, protobuf::EnumOrUnknown};
use rdev::Key;

use crate::common::{PLATFORM_LINUX, PLATFORM_MACOS, PLATFORM_WINDOWS};

const AUTO_SWAP: bool = cfg!(all(
    feature = "flutter",
    any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows"
    )
));

pub(crate) fn enabled(config: &PeerConfig) -> bool {
    enabled_for(std::env::consts::OS, config, AUTO_SWAP)
}

pub(crate) fn toggle(config: &mut PeerConfig) {
    let enabled = !enabled(config);
    config.allow_swap_key.v = enabled;
    if uses_desktop_default(&config.info.platform) {
        // The legacy bool cannot distinguish its default false from a new opt-out.
        config.options.insert(
            OPTION_SWAP_CONTROL_COMMAND_KEY.to_owned(),
            if enabled { "Y" } else { "N" }.to_owned(),
        );
    }
}

pub(crate) fn uses_desktop_default(peer: &str) -> bool {
    AUTO_SWAP && crosses_mac_desktops(std::env::consts::OS, peer)
}

fn enabled_for(local: &str, config: &PeerConfig, auto_swap: bool) -> bool {
    if auto_swap && crosses_mac_desktops(local, &config.info.platform) {
        return !matches!(
            config
                .options
                .get(OPTION_SWAP_CONTROL_COMMAND_KEY)
                .map(String::as_str),
            Some("N")
        );
    }
    config.allow_swap_key.v
}

fn crosses_mac_desktops(local: &str, peer: &str) -> bool {
    matches!(
        (local, peer),
        ("macos", PLATFORM_LINUX | PLATFORM_WINDOWS) | ("linux" | "windows", PLATFORM_MACOS)
    )
}

pub(crate) fn swap_key_event(event: &mut KeyEvent, peer: &str) {
    match &mut event.union {
        Some(key_event::Union::ControlKey(key)) => swap_modifiers(std::slice::from_mut(key)),
        // Legacy Chr contains a character. Map and Translate Chr contain peer keycodes.
        Some(key_event::Union::Chr(code))
            if matches!(
                event.mode.enum_value(),
                Ok(KeyboardMode::Map | KeyboardMode::Translate)
            ) =>
        {
            if let Some(swapped) = swap_keycode(*code, peer) {
                *code = swapped;
            }
        }
        _ => {}
    }
    swap_modifiers(&mut event.modifiers);
}

pub(crate) fn swap_modifiers(modifiers: &mut [EnumOrUnknown<ControlKey>]) {
    for modifier in modifiers {
        let key = match modifier.enum_value() {
            Ok(ControlKey::Control) => ControlKey::Meta,
            Ok(ControlKey::Meta) => ControlKey::Control,
            Ok(ControlKey::RControl) => ControlKey::RWin,
            Ok(ControlKey::RWin) => ControlKey::RControl,
            _ => continue,
        };
        *modifier = key.into();
    }
}

fn swap_keycode(code: u32, peer: &str) -> Option<u32> {
    let swap = |key| match key {
        Key::ControlLeft => Some(Key::MetaLeft),
        Key::MetaLeft => Some(Key::ControlLeft),
        Key::ControlRight => Some(Key::MetaRight),
        Key::MetaRight => Some(Key::ControlRight),
        _ => None,
    };
    if peer.eq_ignore_ascii_case(PLATFORM_WINDOWS) {
        rdev::win_scancode_from_key(swap(rdev::win_key_from_scancode(code))?)
    } else if peer.eq_ignore_ascii_case(PLATFORM_MACOS) || peer.eq_ignore_ascii_case("macos") {
        rdev::macos_keycode_from_key(swap(rdev::macos_key_from_code(code as _))?).map(u32::from)
    } else {
        rdev::linux_keycode_from_key(swap(rdev::linux_key_from_code(code))?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_mac_pairs_swap_by_default_and_honor_opt_out() {
        let mut config = PeerConfig::default();
        config.allow_swap_key.v = false;
        for (local, peer) in [
            ("macos", PLATFORM_WINDOWS),
            ("macos", PLATFORM_LINUX),
            ("windows", PLATFORM_MACOS),
            ("linux", PLATFORM_MACOS),
        ] {
            config.info.platform = peer.to_owned();
            assert!(enabled_for(local, &config, true), "{local} -> {peer}");
            assert!(!enabled_for(local, &config, false));
            config
                .options
                .insert(OPTION_SWAP_CONTROL_COMMAND_KEY.into(), "N".into());
            assert!(!enabled_for(local, &config, true), "{local} -> {peer}");
            config.options.remove(OPTION_SWAP_CONTROL_COMMAND_KEY);
        }
        assert!(!enabled_for("macos", &config, true));
        config.info.platform = PLATFORM_WINDOWS.to_owned();
        assert!(!enabled_for("linux", &config, true));

        if AUTO_SWAP {
            if cfg!(not(target_os = "macos")) {
                config.info.platform = PLATFORM_MACOS.to_owned();
            }
            toggle(&mut config);
            let saved = serde_json::to_string(&config).unwrap();
            let mut reloaded = serde_json::from_str::<PeerConfig>(&saved).unwrap();
            assert!(!enabled(&reloaded));
            toggle(&mut reloaded);
            assert!(enabled(&reloaded));
        }
    }

    #[test]
    fn mapped_shortcuts_swap_left_and_right_modifiers_independently() {
        for (peer, ctrl, cmd) in [
            (PLATFORM_WINDOWS, [0x1d, 0xe01d], [0xe05b, 0xe05c]),
            (PLATFORM_LINUX, [37, 105], [133, 134]),
            (PLATFORM_MACOS, [59, 62], [55, 54]),
        ] {
            for (ctrl, cmd) in ctrl.into_iter().zip(cmd) {
                let mut event = KeyEvent::new();
                event.mode = KeyboardMode::Map.into();
                for down in [true, false] {
                    event.down = down;
                    event.set_chr(ctrl);
                    swap_key_event(&mut event, peer);
                    assert_eq!(event.chr(), cmd, "{peer}");
                    swap_key_event(&mut event, peer);
                    assert_eq!(event.chr(), ctrl, "{peer}");
                    assert_eq!(event.down, down);
                }
            }
        }
    }

    #[test]
    fn legacy_shortcut_keeps_the_character_and_remaps_its_modifier() {
        let mut event = KeyEvent::new();
        event.mode = KeyboardMode::Legacy.into();
        event.set_chr('i' as u32); // Also the X11 code for right Control.
        event.modifiers = vec![ControlKey::RWin.into(), ControlKey::Shift.into()];
        swap_key_event(&mut event, PLATFORM_LINUX);
        assert_eq!(event.chr(), 'i' as u32);
        assert_eq!(
            event.modifiers,
            vec![ControlKey::RControl.into(), ControlKey::Shift.into()]
        );
    }
}
