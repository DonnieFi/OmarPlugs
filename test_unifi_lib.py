#!/usr/bin/env python3
"""unifi_lib: project system/clients without talking to a controller."""
from pathlib import Path
import tempfile

from unifi_lib import (
    _discover,
    _host_known,
    classify_client,
    client_stem,
    fmt_mac,
    _project_client,
    _project_device,
    _project_system,
    _read_secrets_file,
    unifi_config,
)


SYSTEM = {
    "hardware": {"shortname": "UDRULT"},
    "name": "redUltra",
    "mac": "1C6A1B18B4D9",
}


def test_project_system() -> None:
    out = _project_system(SYSTEM)
    assert out["name"] == "redUltra"
    assert out["model"] == "UCG Ultra"
    assert out["mac"] == "1c:6a:1b:18:b4:d9"


def test_project_device_and_client() -> None:
    ap = _project_device({"name": "office", "type": "uap", "mac": "aabbccddeeff", "state": 1, "ip": "192.168.1.8"})
    assert ap["kind"] == "ap" and ap["state"] == "up"
    sta = _project_client({"hostname": "tv", "ip": "192.168.1.40", "mac": "112233445566", "is_wired": False})
    assert sta["wireless"] is True
    assert sta["name"] == "tv"
    # UniFi OS local API uses macAddress / ipAddress
    os_cli = _project_client(
        {"name": "homeassistant be:b6", "type": "WIRED", "ipAddress": "192.168.1.178", "macAddress": "dc:a6:32:27:be:b6"}
    )
    assert os_cli["ip"] == "192.168.1.178"
    assert os_cli["mac"] == "dc:a6:32:27:be:b6"
    assert os_cli["wireless"] is False


def test_client_stem_and_classify() -> None:
    assert client_stem("homeassistant be:b6") == "homeassistant"
    assert client_stem("yanagiba 09:ac") == "yanagiba"
    assert classify_client({"name": "yanagiba 09:ac", "wireless": False}) == "machine"
    assert classify_client({"name": "homeassistant be:b6", "wireless": False}) == "machine"
    assert classify_client({"name": "Wyze Cam 81:4f", "wireless": False}) is None
    assert classify_client({"name": "aka ee:af", "wireless": True}) == "host"


def test_discover_skips_known_and_noise() -> None:
    unifi = {
        "url": "https://192.168.1.1",
        "name": "redUltra",
        "mac": "1c:6a:1b:18:b4:d9",
        "clients": [
            {"name": "deba 2e:a6", "ip": "192.168.1.10", "mac": "aa:bb:cc:dd:ee:ff", "wireless": False},
            {"name": "Living TV", "ip": "192.168.1.77", "mac": "11:22:33:44:55:66", "wireless": True},
            {"name": "homeassistant be:b6", "ip": "192.168.1.178", "mac": "dc:a6:32:27:be:b6", "wireless": False},
            {"name": "yanagiba 09:ac", "ip": "192.168.1.92", "mac": "8c:dc:d4:4e:09:ac", "wireless": False},
        ],
    }
    known = {
        "ips": {"192.168.1.1", "192.168.1.10"},
        "macs": set(),
        "hosts": {"deba"},
    }
    found = _discover(unifi, known)
    labels = [x["label"] for x in found]
    assert "redUltra" not in labels
    assert "deba" not in labels
    assert "Living TV" not in labels
    assert "homeassistant" in labels
    assert "yanagiba" in labels
    ha = next(x for x in found if x["label"] == "homeassistant")
    assert ha["type"] == "machine" and ha["ip"] == "192.168.1.178"
    assert _host_known("aka ee:ae", {"hosts": {"aka"}}) is True


def test_config_default_url() -> None:
    assert unifi_config({})["url"] == "https://192.168.1.1"
    assert unifi_config({"settings": {"unifi": {"url": "https://udm.lan"}}})["url"] == "https://udm.lan"


def test_fmt_mac() -> None:
    assert fmt_mac("1C6A1B18B4D9") == "1c:6a:1b:18:b4:d9"


def test_read_secrets_dotenv_and_json() -> None:
    with tempfile.TemporaryDirectory() as td:
        base = Path(td)
        envf = base / "unifi.env"
        envf.write_text("UNIFI_KEY=abc123\n", encoding="utf-8")
        assert _read_secrets_file(envf)["UNIFI_KEY"] == "abc123"
        jsf = base / "unifi.json"
        jsf.write_text('{"apiKey":"xyz"}', encoding="utf-8")
        assert _read_secrets_file(jsf)["apiKey"] == "xyz"


if __name__ == "__main__":
    test_project_system()
    test_project_device_and_client()
    test_client_stem_and_classify()
    test_discover_skips_known_and_noise()
    test_config_default_url()
    test_fmt_mac()
    test_read_secrets_dotenv_and_json()
    print("ok")
