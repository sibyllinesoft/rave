#!/usr/bin/env python3
import json
import os
from pathlib import Path

CONFIG_PATH = Path("/var/lib/mattermost/config/config.json")
LOG_PATH = Path("/var/lib/rave/update-mattermost-config.log")
SITE_URL_DEFAULT = @SITE_URL@
BRAND_TEXT_DEFAULT = @BRAND_TEXT@
GITLAB_SETTINGS_DEFAULT = json.loads('@GITLAB_SETTINGS@')
SECRET_FALLBACK = @GITLAB_SECRET_FALLBACK@


def _resolve_secret() -> str:
    secret = os.environ.get("GITLAB_SECRET", "").strip()
    secret_file = os.environ.get("GITLAB_SECRET_FILE", "").strip()

    if not secret and secret_file:
        path = Path(secret_file)
        if path.is_file():
            secret = path.read_text(encoding="utf-8").strip()

    if not secret and isinstance(SECRET_FALLBACK, str):
        secret = SECRET_FALLBACK.strip()

    return secret


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
    gitlab_scope = os.environ.get("GITLAB_SCOPE", "read_user")
    auth_base = _trim(os.environ.get("GITLAB_AUTH_BASE"), site_url)
    api_base = _trim(os.environ.get("GITLAB_API_BASE"), site_url)
    redirect_uri = os.environ.get("GITLAB_REDIRECT", "")

    gitlab_settings = dict(GITLAB_SETTINGS_DEFAULT)
    gitlab_settings["Scope"] = gitlab_scope
    gitlab_settings["Secret"] = _resolve_secret()
    gitlab_settings["AuthEndpoint"] = f"{auth_base}/oauth/authorize"
    gitlab_settings["TokenEndpoint"] = f"{api_base}/oauth/token"
    gitlab_settings["UserAPIEndpoint"] = f"{api_base}/api/v4/user"
    if redirect_uri:
        gitlab_settings["RedirectUri"] = redirect_uri

    service = config.setdefault("ServiceSettings", {})
    service["SiteURL"] = site_url

    team = config.setdefault("TeamSettings", {})
    team["EnableCustomBrand"] = True
    team["CustomDescriptionText"] = ""
    team["CustomBrandText"] = brand_html

    gitlab = config.setdefault("GitLabSettings", {})
    gitlab.update(gitlab_settings)

    config.pop("GoogleSettings", None)

    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")
    LOG_PATH.write_text("updated:gitlab\n")


if __name__ == "__main__":
    main()
