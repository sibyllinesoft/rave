#!/usr/bin/env python3
import json
from pathlib import Path

CONFIG_PATH = Path("/var/lib/mattermost/config/config.json")
LOG_PATH = Path("/var/lib/rave/update-mattermost-config.log")
SITE_URL = @SITE_URL@
BRAND_TEXT = @BRAND_TEXT@
GITLAB_SETTINGS = json.loads('@GITLAB_SETTINGS@')


def main() -> None:
    if not CONFIG_PATH.exists():
        LOG_PATH.write_text("config.json missing\n")
        return

    config = json.loads(CONFIG_PATH.read_text())

    service = config.setdefault("ServiceSettings", {})
    service["SiteURL"] = SITE_URL

    team = config.setdefault("TeamSettings", {})
    team["EnableCustomBrand"] = True
    team["CustomDescriptionText"] = ""
    team["CustomBrandText"] = BRAND_TEXT

    gitlab = config.setdefault("GitLabSettings", {})
    gitlab.update(GITLAB_SETTINGS)

    config.pop("GoogleSettings", None)

    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")
    LOG_PATH.write_text("updated:gitlab\n")


if __name__ == "__main__":
    main()
