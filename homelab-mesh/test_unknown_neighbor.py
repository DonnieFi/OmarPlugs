#!/usr/bin/env python3
"""unknown neighbor notify fires once per new lladdr (OmarPlugs-5oy.21)."""
from notify_lib import apply_unknown_neighbor_alerts, empty_notify_state


def test_unknown_neighbor_once() -> None:
    inv = {"schemaVersion": 2, "nodes": [], "settings": {}}
    state = empty_notify_state()
    glance = {
        "lan_meta": {
            "unknown_hosts": [
                {"ip": "192.168.1.77", "mac": "aa:bb:cc:dd:ee:77"},
            ]
        }
    }
    sent = apply_unknown_neighbor_alerts(state, inv, glance)
    assert len(sent) == 1
    assert sent[0]["kind"] == "unknown_neighbor"
    again = apply_unknown_neighbor_alerts(state, inv, glance)
    assert again == []


def test_unknown_neighbor_mute_setting() -> None:
    inv = {"schemaVersion": 2, "nodes": [], "settings": {"unknownNeighborNotify": False}}
    state = empty_notify_state()
    glance = {"lan_meta": {"unknown_hosts": [{"ip": "192.168.1.9", "mac": "11:22:33:44:55:66"}]}}
    assert apply_unknown_neighbor_alerts(state, inv, glance) == []


if __name__ == "__main__":
    test_unknown_neighbor_once()
    test_unknown_neighbor_mute_setting()
    print("ok")
