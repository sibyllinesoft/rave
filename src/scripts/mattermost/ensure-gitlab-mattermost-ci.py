import json
import os
import time
from pathlib import Path
from typing import Any, Dict, Iterable

import requests
from requests import Session


def read_first_line(path: str) -> str:
    try:
        data = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"required secret file missing: {path}")
    value = data.strip()
    if not value:
        raise SystemExit(f"secret file {path} was empty")
    return value


def parse_verify_flag(raw: str) -> Any:
    value = raw.strip().lower()
    if value in ("", "false", "0", "no", "off"):
        return False
    if value in ("true", "1", "yes", "on"):
        return True
    return raw


def wait_for_api(session: Session, url: str, name: str, *, attempts: int = 60, delay: float = 5.0) -> None:
    for _ in range(attempts):
        try:
            response = session.get(url, timeout=5)
            if response.status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(delay)
    raise SystemExit(f"{name} API did not become ready: {url}")


def mattermost_login(session: Session, base_url: str, login_ids: Iterable[str], password: str) -> None:
    for login_id in login_ids:
        if not login_id:
            continue
        try:
            response = session.post(
                f"{base_url}/api/v4/users/login",
                json={"login_id": login_id, "password": password},
                timeout=10,
            )
        except requests.RequestException as exc:
            last_error = exc
            continue

        if response.status_code == 200:
            token = response.headers.get("Token")
            if not token:
                last_error = RuntimeError("Mattermost login response missing session token")
                break
            session.headers["Authorization"] = f"Bearer {token}"
            return

        last_error = RuntimeError(f"Mattermost login failed: {response.status_code} {response.text}")

    if 'last_error' in locals():
        raise SystemExit(str(last_error))
    raise SystemExit("Mattermost login failed: no login IDs were provided")


def ensure_team(session: Session, base_url: str, name: str, display_name: str) -> Dict[str, Any]:
    response = session.get(f"{base_url}/api/v4/teams/name/{name}", timeout=10)
    if response.status_code == 200:
        return response.json()
    if response.status_code != 404:
        raise SystemExit(f"failed to query team '{name}': {response.status_code} {response.text}")

    response = session.post(
        f"{base_url}/api/v4/teams",
        json={"name": name, "display_name": display_name, "type": "O"},
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise SystemExit(f"failed to create Mattermost team '{name}': {response.status_code} {response.text}")
    return response.json()


def ensure_channel(session: Session, base_url: str, team_id: str, name: str, display_name: str) -> Dict[str, Any]:
    response = session.get(
        f"{base_url}/api/v4/teams/{team_id}/channels/name/{name}",
        timeout=10,
    )
    if response.status_code == 200:
        return response.json()
    if response.status_code != 404:
        raise SystemExit(f"failed to query channel '{name}': {response.status_code} {response.text}")

    response = session.post(
        f"{base_url}/api/v4/channels",
        json={"team_id": team_id, "name": name, "display_name": display_name, "type": "O"},
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise SystemExit(f"failed to create Mattermost channel '{name}': {response.status_code} {response.text}")
    return response.json()


def list_incoming_hooks(session: Session, base_url: str) -> Iterable[Dict[str, Any]]:
    page = 0
    per_page = 200
    while True:
        response = session.get(
            f"{base_url}/api/v4/hooks/incoming",
            params={"page": page, "per_page": per_page},
            timeout=10,
        )
        if response.status_code != 200:
            raise SystemExit(f"failed to list Mattermost incoming hooks: {response.status_code} {response.text}")
        hooks = response.json()
        if not hooks:
            break
        yield from hooks
        if len(hooks) < per_page:
            break
        page += 1


def ensure_incoming_hook(
    session: Session,
    base_url: str,
    team_id: str,
    channel_id: str,
    display_name: str,
    username: str,
) -> Dict[str, Any]:
    for hook in list_incoming_hooks(session, base_url):
        if hook.get("channel_id") == channel_id and hook.get("display_name") == display_name:
            return hook

    response = session.post(
        f"{base_url}/api/v4/hooks/incoming",
        json={
            "team_id": team_id,
            "channel_id": channel_id,
            "display_name": display_name,
            "description": "GitLab CI pipeline notifications",
            "username": username,
        },
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise SystemExit(f"failed to create Mattermost incoming webhook: {response.status_code} {response.text}")
    return response.json()


def fetch_all_projects(session: Session, base_url: str) -> Iterable[Dict[str, Any]]:
    page = 1
    per_page = 100
    while True:
        response = session.get(
            f"{base_url}/projects",
            params={"membership": True, "simple": True, "per_page": per_page, "page": page},
            timeout=10,
        )
        if response.status_code != 200:
            raise SystemExit(f"failed to list GitLab projects: {response.status_code} {response.text}")
        chunk = response.json()
        if not chunk:
            break
        yield from chunk
        if len(chunk) < per_page:
            break
        page += 1


def configure_project_integration(
    session: Session,
    base_url: str,
    project_id: int,
    webhook_url: str,
    channel_name: str,
    username: str,
) -> None:
    payload = {
        "webhook": webhook_url,
        "username": username,
        "channel": f"#{channel_name}",
        "notify_only_broken_pipelines": False,
        "branches_to_be_notified": "all",
        "push_events": False,
        "issues_events": False,
        "confidential_issues_events": False,
        "merge_requests_events": True,
        "tag_push_events": True,
        "note_events": False,
        "confidential_note_events": False,
        "pipeline_events": True,
        "wiki_page_events": False,
        "job_events": True,
        "deployment_events": True,
        "active": True,
    }
    response = session.put(
        f"{base_url}/projects/{project_id}/services/mattermost",
        json=payload,
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise SystemExit(
            f"failed to configure Mattermost integration for project {project_id}: "
            f"{response.status_code} {response.text}"
        )


def main() -> None:
    mattermost_base = os.environ.get("MATTERMOST_BASE_URL", "http://127.0.0.1:8065").rstrip("/")
    mattermost_site = os.environ.get("MATTERMOST_SITE_URL", mattermost_base).rstrip("/")
    mattermost_team_name = os.environ["MATTERMOST_TEAM_NAME"]
    mattermost_team_display = os.environ["MATTERMOST_TEAM_DISPLAY_NAME"]
    mattermost_channel_name = os.environ["MATTERMOST_CHANNEL_NAME"]
    mattermost_channel_display = os.environ["MATTERMOST_CHANNEL_DISPLAY_NAME"]
    mattermost_hook_display = os.environ.get("MATTERMOST_HOOK_DISPLAY_NAME", "GitLab CI Builds")
    mattermost_username = os.environ.get("MATTERMOST_HOOK_USERNAME", "gitlab-ci")
    mattermost_verify = parse_verify_flag(os.environ.get("MATTERMOST_VERIFY_TLS", "false"))

    mattermost_username_file = os.environ["MATTERMOST_ADMIN_USERNAME_FILE"]
    mattermost_password_file = os.environ["MATTERMOST_ADMIN_PASSWORD_FILE"]
    mattermost_email_file = os.environ.get("MATTERMOST_ADMIN_EMAIL_FILE", "")
    gitlab_token_file = os.environ["GITLAB_API_TOKEN_FILE"]
    gitlab_base = os.environ.get("GITLAB_API_BASE_URL", "https://localhost:8443/gitlab/api/v4").rstrip("/")
    gitlab_verify = parse_verify_flag(os.environ.get("GITLAB_VERIFY_TLS", "false"))

    mm_username = read_first_line(mattermost_username_file)
    mm_password = read_first_line(mattermost_password_file)
    mm_email = ""
    if mattermost_email_file:
        try:
            mm_email = read_first_line(mattermost_email_file)
        except SystemExit:
            mm_email = ""
    gitlab_token = read_first_line(gitlab_token_file)

    mm_session = requests.Session()
    mm_session.verify = mattermost_verify
    wait_for_api(mm_session, f"{mattermost_base}/api/v4/system/ping", "Mattermost")
    login_candidates = []
    seen = set()
    for candidate in (mm_email, mm_username):
        candidate = candidate.strip()
        if candidate and candidate not in seen:
            login_candidates.append(candidate)
            seen.add(candidate)
    mattermost_login(mm_session, mattermost_base, login_candidates, mm_password)

    team = ensure_team(mm_session, mattermost_base, mattermost_team_name, mattermost_team_display)
    channel = ensure_channel(mm_session, mattermost_base, team["id"], mattermost_channel_name, mattermost_channel_display)
    hook = ensure_incoming_hook(
        mm_session,
        mattermost_base,
        team["id"],
        channel["id"],
        mattermost_hook_display,
        mattermost_username,
    )
    hook_id = hook["id"]
    webhook_internal = f"{mattermost_base}/hooks/{hook_id}"

    gitlab_session = requests.Session()
    gitlab_session.headers["PRIVATE-TOKEN"] = gitlab_token
    gitlab_session.verify = gitlab_verify
    wait_for_api(gitlab_session, f"{gitlab_base}/version", "GitLab")

    projects = list(fetch_all_projects(gitlab_session, gitlab_base))
    for project in projects:
        configure_project_integration(
            gitlab_session,
            gitlab_base,
            project["id"],
            webhook_internal,
            mattermost_channel_name,
            mattermost_hook_display,
        )

    print(f"[ci-bridge] Mattermost webhook {hook_id} linked to channel '{mattermost_channel_name}' in team '{mattermost_team_name}'")
    print(f"[ci-bridge] Configured {len(projects)} GitLab project(s) for Mattermost notifications")

    summary = {
        "mattermost_team": mattermost_team_name,
        "mattermost_channel": mattermost_channel_name,
        "incoming_hook": hook_id,
        "configured_projects": [p["path_with_namespace"] for p in projects],
        "webhook_url_internal": webhook_internal,
        "webhook_url_external": f"{mattermost_site}/hooks/{hook_id}",
    }
    output_path = Path("/var/lib/rave/gitlab-mattermost-ci.json")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    output_path.chmod(0o600)


if __name__ == "__main__":
    main()
