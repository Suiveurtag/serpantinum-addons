import json
from pathlib import Path
import tarfile
from unittest.mock import patch

import pytest

import package_remote
import remote_hyprland as hypr
import remote_install


RESCUE = [{"allow_input_capture": True, "dispatcher": "HL.Dispatcher(release_input_capture)",
           "key": "F12", "modmask": 65}]


def config_at(tmp_path):
    config = tmp_path / "hyprland.lua"
    config.write_text('require("config/settings")\n')
    return config


def test_bundle_contains_only_the_expected_regular_files(tmp_path):
    path = tmp_path / "adapter.tar.gz"
    package_remote.make_archive(path)
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        assert {m.name for m in members} == {"beamer-hyprland/" + name for name in remote_install.FILES}
        assert all(m.isfile() for m in members)
        assert archive.getmember("beamer-hyprland/build-clipboard.sh").mode & 0o111
    with pytest.raises(FileExistsError):
        package_remote.make_archive(path)


def test_install_keeps_original_and_verifies_rescue(tmp_path):
    config = config_at(tmp_path)
    before = config.read_bytes()
    with patch.object(hypr, "checked_config", return_value=config), \
         patch.object(hypr, "binds", side_effect=[[], RESCUE]), \
         patch.object(hypr, "call", return_value=""):
        receipt = hypr.install()
    assert receipt.backup.read_bytes() == before
    assert config.read_bytes().startswith(before.rstrip())
    include = tmp_path / "config/serpantinum_beamer_remote.lua"
    assert hypr.BIND in include.read_text()
    assert hypr.RULE in include.read_text()
    with patch.object(hypr, "checked_config", return_value=config), \
         patch.object(hypr, "binds", return_value=RESCUE):
        assert hypr.install() is None


def test_existing_shortcut_is_not_overwritten(tmp_path):
    config = config_at(tmp_path)
    with patch.object(hypr, "checked_config", return_value=config), \
         patch.object(hypr, "binds", return_value=[{"key": "F12", "modmask": 65}]):
        with pytest.raises(RuntimeError, match="déjà utilisé"):
            hypr.install()
    assert config.read_text() == 'require("config/settings")\n'
    assert not (tmp_path / "config/serpantinum_beamer_remote.lua").exists()


def test_reload_failure_restores_existing_configuration(tmp_path):
    config = config_at(tmp_path)
    before = config.read_bytes()
    with patch.object(hypr, "checked_config", return_value=config), \
         patch.object(hypr, "binds", side_effect=[[], []]), \
         patch.object(hypr, "call", return_value=""):
        with pytest.raises(RuntimeError, match="pas pu être activé"):
            hypr.install()
    assert config.read_bytes() == before
    assert not (tmp_path / "config/serpantinum_beamer_remote.lua").exists()


def test_unowned_include_is_not_modified(tmp_path):
    config = config_at(tmp_path)
    path = tmp_path / "config/serpantinum_beamer_remote.lua"
    path.parent.mkdir()
    path.write_text("# user data")
    with patch.object(hypr, "checked_config", return_value=config), \
         patch.object(hypr, "binds", return_value=[]):
        with pytest.raises(RuntimeError, match="existant conservé"):
            hypr.install()
    assert path.read_text() == "# user data"


def test_invalid_rescue_does_not_qualify():
    assert not remote_install.has_rescue_binding([{"key": "F12", "dispatcher": "release_input_capture"}])
    assert remote_install.has_rescue_binding(RESCUE)


def test_check_rescue_failure_is_non_mutating():
    result = type("Result", (), {"stdout": json.dumps([])})()
    with patch.object(remote_install.subprocess, "run", return_value=result):
        with pytest.raises(RuntimeError, match="Aucun raccourci"):
            remote_install.check_rescue()


def test_install_copies_only_bundle_and_refuses_modified_files(tmp_path, monkeypatch):
    data = tmp_path / "data"
    monkeypatch.setenv("XDG_DATA_HOME", str(data))
    desktop = data / "applications/serpantinum-beamer.desktop"
    state = tmp_path / "state/install.json"
    cache = tmp_path / "cache"

    def build(command, **kwargs):
        output = Path(command[1])
        for name in remote_install.setup.HELPERS:
            (output / name).write_bytes(name.encode())

    with patch.object(remote_install.setup, "check_dependencies"), \
         patch.object(remote_install.setup, "paths", return_value=(desktop, state, cache)), \
         patch.object(remote_install.subprocess, "run", side_effect=build), \
         patch.object(remote_install.remote_hyprland, "install", return_value=None), \
         patch.object(remote_install, "check_rescue"), \
         patch.object(remote_install.setup, "install", return_value=desktop):
        dest, got_desktop = remote_install.install()
        assert got_desktop == desktop
        assert {p.name for p in dest.iterdir()} == set(remote_install.FILES)
        (dest / "launcher.py").write_text("user modification")
        with pytest.raises(RuntimeError, match="différent, conservé"):
            remote_install.install()
        assert (dest / "launcher.py").read_text() == "user modification"


@pytest.mark.parametrize("failure", ["copy", "setup"])
def test_late_failure_rolls_back_hyprland_and_owned_copies(tmp_path, monkeypatch, failure):
    data = tmp_path / "data"
    monkeypatch.setenv("XDG_DATA_HOME", str(data))
    config = config_at(tmp_path)
    before = config.read_bytes()
    desktop, state, cache = data / "applications/app.desktop", tmp_path / "state.json", tmp_path / "cache"
    original_copy = remote_install.copy_owned
    count = 0

    def copy(source, dest):
        nonlocal count
        count += 1
        if failure == "copy" and count == 2:
            raise OSError("copy failure")
        original_copy(source, dest)

    def build(command, **kwargs):
        for name in remote_install.setup.HELPERS:
            (Path(command[1]) / name).write_bytes(name.encode())

    with patch.object(remote_install.setup, "check_dependencies"), \
         patch.object(remote_install.setup, "paths", return_value=(desktop, state, cache)), \
         patch.object(remote_install.subprocess, "run", side_effect=build), \
         patch.object(hypr, "checked_config", return_value=config), \
         patch.object(hypr, "binds", side_effect=[[], RESCUE]), \
         patch.object(hypr, "call", return_value=""), \
         patch.object(remote_install, "check_rescue"), \
         patch.object(remote_install, "copy_owned", side_effect=copy), \
         patch.object(remote_install.setup, "install", side_effect=OSError("setup failure")):
        with pytest.raises(RuntimeError, match="Modifications propres annulées"):
            remote_install.install()
    assert config.read_bytes() == before
    assert not (tmp_path / "config/serpantinum_beamer_remote.lua").exists()
    assert not (data / "beamer-hyprland-compat").exists()


def test_concurrent_changes_preserved_on_failure(tmp_path, monkeypatch):
    data = tmp_path / "data"
    monkeypatch.setenv("XDG_DATA_HOME", str(data))
    config = config_at(tmp_path)
    desktop, state, cache = data / "applications/app.desktop", tmp_path / "state.json", tmp_path / "cache"

    def build(command, **kwargs):
        for name in remote_install.setup.HELPERS:
            (Path(command[1]) / name).write_bytes(name.encode())

    def fail_after_edits(dest):
        (dest / "launcher.py").write_text("user modification")
        config.write_bytes(config.read_bytes() + b"-- concurrent edit\n")
        raise OSError("setup failure")

    with patch.object(remote_install.setup, "check_dependencies"), \
         patch.object(remote_install.setup, "paths", return_value=(desktop, state, cache)), \
         patch.object(remote_install.subprocess, "run", side_effect=build), \
         patch.object(hypr, "checked_config", return_value=config), \
         patch.object(hypr, "binds", side_effect=[[], RESCUE]), \
         patch.object(hypr, "call", return_value=""), \
         patch.object(remote_install, "check_rescue"), \
         patch.object(remote_install.setup, "install", side_effect=fail_after_edits):
        with pytest.raises(RuntimeError, match="modifiée entre-temps"):
            remote_install.install()
    assert config.read_text().endswith("-- concurrent edit\n")
    assert (tmp_path / "config/serpantinum_beamer_remote.lua").exists()
    assert (data / "beamer-hyprland-compat/launcher.py").read_text() == "user modification"
