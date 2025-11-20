#!/usr/bin/env python3
import json
import os
from pathlib import Path

CONFIG_PATH = Path("/var/lib/mattermost/config/config.json")
LOG_PATH = Path("/var/lib/rave/update-mattermost-config.log")
SITE_URL_DEFAULT = @SITE_URL@
BRAND_TEXT_DEFAULT = @BRAND_TEXT@
GITLAB_SETTINGS_DEFAULT = json.loads('@GITLAB_SETTINGS@')
GITLAB_ENABLED_DEFAULT = @GITLAB_ENABLED_DEFAULT@
SECRET_FALLBACK = @GITLAB_SECRET_FALLBACK@
OPENID_SETTINGS_DEFAULT = json.loads('@OPENID_SETTINGS@')
OPENID_ENABLED_DEFAULT = @OPENID_ENABLED_DEFAULT@
OPENID_SECRET_FALLBACK = @OPENID_SECRET_FALLBACK@


def _resolve_secret(value_key: str, file_key: str, fallback: str) -> str:
    secret = os.environ.get(value_key, "").strip()
    secret_file = os.environ.get(file_key, "").strip()

    if not secret and secret_file:
        path = Path(secret_file)
        if path.is_file():
            secret = path.read_text(encoding="utf-8").strip()

    if not secret and isinstance(fallback, str):
        secret = fallback.strip()

    return secret


def _bool_env(var: str, default: bool) -> bool:
    value = os.environ.get(var)
    if value is None:
        return bool(default)
    return value.lower() in {"1", "true", "yes", "on"}


def _trim(value: str, fallback: str) -> str:
    candidate = (value or fallback).rstrip("/")
    return candidate or fallback.rstrip("/")


def main() -> None:
    if not CONFIG_PATH.exists():
        LOG_PATH.write_text("config.json missing\n")
        return

    config = json.loads(CONFIG_PATH.read_text())

    site_url = os.environ.get("SITE_URL", SITE_URL_DEFAULT).rstrip("/")
    brand_html = os.environ.get("BRAND_HTML") or BRAND_TEXT_DEFAULT
    gitlab_enabled = _bool_env("GITLAB_ENABLED", GITLAB_ENABLED_DEFAULT)
    openid_enabled = _bool_env("OPENID_ENABLED", OPENID_ENABLED_DEFAULT)

    gitlab_scope = os.environ.get("GITLAB_SCOPE", "read_user")
    auth_base = _trim(os.environ.get("GITLAB_AUTH_BASE"), site_url)
    api_base = _trim(os.environ.get("GITLAB_API_BASE"), site_url)
    redirect_uri = os.environ.get("GITLAB_REDIRECT", "")

    service = config.setdefault("ServiceSettings", {})
    service["SiteURL"] = site_url

    team = config.setdefault("TeamSettings", {})
    team["EnableCustomBrand"] = True
    team["CustomDescriptionText"] = ""
    team["CustomBrandText"] = brand_html

    sections = []

    gitlab = config.setdefault("GitLabSettings", {})
    if gitlab_enabled:
        gitlab_settings = dict(GITLAB_SETTINGS_DEFAULT)
        gitlab_settings["Enable"] = True
        gitlab_settings["Scope"] = gitlab_scope
        gitlab_settings["Secret"] = _resolve_secret("GITLAB_SECRET", "GITLAB_SECRET_FILE", SECRET_FALLBACK)
        gitlab_settings["AuthEndpoint"] = f"{auth_base}/oauth/authorize"
        gitlab_settings["TokenEndpoint"] = f"{api_base}/oauth/token"
        gitlab_settings["UserAPIEndpoint"] = f"{api_base}/api/v4/user"
        if redirect_uri:
            gitlab_settings["RedirectUri"] = redirect_uri
        gitlab.update(gitlab_settings)
        sections.append("gitlab")
    else:
        gitlab["Enable"] = False
        sections.append("gitlab-disabled")

    openid = config.setdefault("OpenIdSettings", {})
    if openid_enabled and isinstance(OPENID_SETTINGS_DEFAULT, dict):
        openid_settings = dict(OPENID_SETTINGS_DEFAULT)
        openid_settings["Enable"] = True
        openid_settings["Secret"] = _resolve_secret("OPENID_SECRET", "OPENID_SECRET_FILE", OPENID_SECRET_FALLBACK)
        openid_settings["Scope"] = os.environ.get("OPENID_SCOPE", openid_settings.get("Scope", "openid profile email"))
        for env_key, field in [
            ("OPENID_DISCOVERY", "DiscoveryEndpoint"),
            ("OPENID_AUTH_ENDPOINT", "AuthEndpoint"),
            ("OPENID_TOKEN_ENDPOINT", "TokenEndpoint"),
            ("OPENID_USER_ENDPOINT", "UserAPIEndpoint"),
            ("OPENID_BUTTON_TEXT", "ButtonText"),
            ("OPENID_BUTTON_COLOR", "ButtonColor"),
        ]:
            value = os.environ.get(env_key)
            if value:
                openid_settings[field] = value
        client_id = os.environ.get("OPENID_CLIENT_ID")
        if client_id:
            openid_settings["Id"] = client_id
        openid.update(openid_settings)
        sections.append("openid")
    else:
        openid["Enable"] = False
        sections.append("openid-disabled")

    config.pop("GoogleSettings", None)

    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")
    LOG_PATH.write_text("updated:" + ",".join(sections) + "\n")


if __name__ == "__main__":
    main()
