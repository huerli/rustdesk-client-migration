use std::{
    collections::BTreeSet,
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};

use hbb_common::{config::Config, log, tokio::runtime::Builder, webrtc::WebRTCStream};

const POLL_INTERVAL: Duration = Duration::from_secs(3);
const SETTLE_SAMPLES: u8 = 2;
static MONITOR_STARTED: AtomicBool = AtomicBool::new(false);

struct ChangeDetector {
    stable: Option<String>,
    pending: Option<(String, u8)>,
}

impl ChangeDetector {
    fn new(stable: Option<String>) -> Self {
        Self {
            stable,
            pending: None,
        }
    }

    fn observe(&mut self, current: Option<&str>) -> Option<(String, String)> {
        let current = current?;
        if self.stable.as_deref() == Some(current) {
            self.pending = None;
            return None;
        }
        match self.pending.as_mut() {
            Some((candidate, samples)) if candidate == current => *samples += 1,
            _ => self.pending = Some((current.to_owned(), 1)),
        }
        if self
            .pending
            .as_ref()
            .map(|(_, samples)| *samples < SETTLE_SAMPLES)
            .unwrap_or(true)
        {
            return None;
        }
        let current = current.to_owned();
        self.pending = None;
        self.stable
            .replace(current.clone())
            .map(|previous| (previous, current))
    }
}

/// A stable description of the host's routable interfaces. TUN adapters and loopback are
/// deliberately excluded: they follow the underlying network and would make a proxy restart look
/// like a physical network change.
fn network_fingerprint() -> Option<String> {
    let mut parts = BTreeSet::new();
    for interface in default_net::get_interfaces() {
        if !interface.is_up() || interface.is_loopback() || interface.is_tun() {
            continue;
        }
        let mut addresses = Vec::new();
        for network in &interface.ipv4 {
            if !network.addr.is_loopback() && !network.addr.is_link_local() {
                addresses.push(format!("v4={}", network.addr));
            }
        }
        // IPv6 privacy addresses rotate independently of the physical link. Only use them as the
        // identity when the interface has no IPv4 address at all.
        if addresses.is_empty() {
            for network in &interface.ipv6 {
                let ip = network.addr;
                if !ip.is_loopback() && !ip.is_unicast_link_local() {
                    addresses.push(format!("v6={ip}"));
                }
            }
        }
        if addresses.is_empty() {
            continue;
        }
        addresses.sort();
        let mac = interface
            .mac_addr
            .map(|mac| mac.address())
            .unwrap_or_default();
        let gateway = interface
            .gateway
            .as_ref()
            .map(|gateway| format!("gw={}", gateway.ip_addr))
            .unwrap_or_default();
        parts.insert(format!(
            "{}|{}|{}|{}",
            interface.name,
            mac,
            addresses.join(","),
            gateway
        ));
    }
    if parts.is_empty() {
        return None;
    }
    Some(parts.into_iter().collect::<Vec<_>>().join("||"))
}

fn reset_network_state(previous: &str, current: &str) {
    log::info!("Local network changed; resetting cached NAT and WebRTC state");
    log::debug!("Network fingerprint: {previous} -> {current}");

    // Both values describe the network that just disappeared. Clear them before probing so a
    // failed probe cannot leave the next connection using the old mapping.
    Config::set_nat_type(0);
    Config::set_option("local-ip-addr".to_owned(), String::new());
    crate::common::clear_ipv6_network_cache();
    #[cfg(not(target_os = "ios"))]
    crate::rendezvous_mediator::notify_network_state_changed();

    std::thread::spawn(|| {
        let Ok(runtime) = Builder::new_current_thread().enable_all().build() else {
            return;
        };
        runtime.block_on(WebRTCStream::clear_cached_sessions_after_network_change());
    });

    // These already run their probes on worker threads and are safe to use from the monitor.
    crate::common::test_nat_type();
    crate::common::test_rendezvous_server();
}

/// Monitor physical network identity without polling the Internet. A second identical sample is
/// required so transient changes during DHCP or VPN setup do not tear down a healthy session.
pub fn start_monitor() {
    if MONITOR_STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(|| {
        let mut changes = ChangeDetector::new(network_fingerprint());
        loop {
            std::thread::sleep(POLL_INTERVAL);
            if let Some((previous, current)) = changes.observe(network_fingerprint().as_deref()) {
                reset_network_state(&previous, &current);
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::ChangeDetector;

    #[test]
    fn network_change_requires_two_samples() {
        let mut changes = ChangeDetector::new(Some("old".to_owned()));
        assert_eq!(changes.observe(Some("new")), None);
        assert_eq!(
            changes.observe(Some("new")),
            Some(("old".to_owned(), "new".to_owned()))
        );
        assert_eq!(changes.observe(Some("new")), None);
    }

    #[test]
    fn transient_change_does_not_reset() {
        let mut changes = ChangeDetector::new(Some("old".to_owned()));
        assert_eq!(changes.observe(Some("transient")), None);
        assert_eq!(changes.observe(Some("old")), None);
        assert_eq!(changes.observe(Some("transient")), None);
        assert_eq!(changes.observe(None), None);
    }
}
