#!/usr/bin/env python3
"""Validate SOPS configuration and encrypted secret files.

This script enforces a few guard rails called out in the refactor plan:
  * `.sops.yaml` must list at least one real age public key (no `example` placeholders).
  * Every creation rule must reference at least one age key.
  * `config/secrets.yaml` must stay encrypted and reference known recipients.

Run it after editing `.sops.yaml` or rotating secrets:
    python scripts/secrets/lint.py
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable, List, Tuple

try:  # Lazy dependency so we only import PyYAML when needed.
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover - runtime guard
    sys.stderr.write(
        "PyYAML is required for scripts/secrets/lint.py.\n"
        "Install it via 'pip install pyyaml' or use 'nix develop' before rerunning.\n"
    )
    raise SystemExit(2) from exc

AGE_KEY_RE = re.compile(r"^age1[0-9a-z]{8,}$")


class LintResult:
    def __init__(self) -> None:
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.passed_checks: List[str] = []

    def add_error(self, message: str) -> None:
        self.errors.append(message)

    def add_ok(self, message: str) -> None:
        self.passed_checks.append(message)

    def add_warning(self, message: str) -> None:
        self.warnings.append(message)

    def exit_code(self) -> int:
        return 1 if self.errors else 0


def read_yaml(path: Path, description: str) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"{description} not found at {path}")
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)  # type: ignore[no-any-unimported]
    return data or {}


def collect_age_keys(keys_node: Iterable) -> Tuple[List[str], List[str]]:
    valid: List[str] = []
    errors: List[str] = []
    if not keys_node:
        errors.append(".sops.yaml: keys list is empty")
        return valid, errors
    for raw in keys_node:
        if not isinstance(raw, str):
            errors.append(".sops.yaml: keys entries must be strings")
            continue
        if "example" in raw:
            errors.append(f"Placeholder key still present: {raw}")
            continue
        if not AGE_KEY_RE.match(raw):
            errors.append(f"Invalid age public key format: {raw}")
            continue
        valid.append(raw)
    if not valid:
        errors.append("No usable age keys discovered in .sops.yaml")
    return valid, errors


def validate_creation_rules(rules: Iterable, known_keys: Iterable[str]) -> List[str]:
    errors: List[str] = []
    known = set(known_keys)
    for idx, rule in enumerate(rules or [], start=1):
        if not isinstance(rule, dict):
            errors.append(f"creation_rules[{idx}] must be a mapping")
            continue
        if not rule.get("path_regex"):
            errors.append(f"creation_rules[{idx}] missing path_regex")
        key_groups = rule.get("key_groups")
        if not key_groups:
            errors.append(f"creation_rules[{idx}] missing key_groups")
            continue
        for group_idx, group in enumerate(key_groups, start=1):
            if not isinstance(group, dict):
                errors.append(
                    f"creation_rules[{idx}].key_groups[{group_idx}] must be a mapping"
                )
                continue
            age_keys = group.get("age")
            if not age_keys:
                errors.append(
                    f"creation_rules[{idx}].key_groups[{group_idx}] missing age list"
                )
                continue
            for key in age_keys:
                if not isinstance(key, str):
                    errors.append(
                        f"creation_rules[{idx}].key_groups[{group_idx}] contains non-string key"
                    )
                    continue
                if "example" in key:
                    errors.append(
                        f"creation_rules[{idx}] references placeholder key '{key}'"
                    )
                if not AGE_KEY_RE.match(key):
                    errors.append(
                        f"creation_rules[{idx}] references malformed key '{key}'"
                    )
                if known and key not in known:
                    errors.append(
                        f"creation_rules[{idx}] references key '{key}' not listed under top-level keys"
                    )
    return errors


def validate_secrets_file(path: Path, known_keys: Iterable[str]) -> Tuple[List[str], List[str]]:
    errors: List[str] = []
    oks: List[str] = []
    data = read_yaml(path, "Encrypted secrets file")
    sops_meta = data.get("sops")
    if not isinstance(sops_meta, dict):
        errors.append(
            f"{path}: missing 'sops' metadata block – file is not encrypted via sops"
        )
        return oks, errors
    recipients = []
    for entry in sops_meta.get("age", []) or []:
        if isinstance(entry, dict) and entry.get("recipient"):
            recipients.append(entry["recipient"])
    if not recipients:
        errors.append(f"{path}: sops.age recipients list is empty")
    missing = [r for r in recipients if r not in set(known_keys)]
    if missing:
        errors.append(
            f"{path}: recipients not present in .sops.yaml keys: {', '.join(missing)}"
        )
    else:
        oks.append(
            f"{path}: all sops recipients are defined in .sops.yaml ({len(recipients)} total)"
        )
    if not sops_meta.get("mac"):
        errors.append(f"{path}: sops metadata missing MAC – re-encrypt the file")
    if not sops_meta.get("version"):
        errors.append(f"{path}: sops metadata missing version field")
    return oks, errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lint SOPS configuration and encrypted secret files",
    )
    parser.add_argument(
        "--sops-config",
        default=Path(".sops.yaml"),
        type=Path,
        help="Path to the .sops.yaml file (default: %(default)s)",
    )
    parser.add_argument(
        "--secrets-file",
        default=Path("config/secrets.yaml"),
        type=Path,
        help="Encrypted secrets file to validate (default: %(default)s)",
    )
    args = parser.parse_args()

    result = LintResult()
    try:
        sops_config = read_yaml(args.sops_config, ".sops.yaml")
    except FileNotFoundError as exc:
        result.add_error(str(exc))
        report(result)
        return result.exit_code()

    known_keys, key_errors = collect_age_keys(sops_config.get("keys", []))
    if key_errors:
        for err in key_errors:
            result.add_error(err)
    else:
        result.add_ok(f"Loaded {len(known_keys)} age key(s) from {args.sops_config}")

    creation_errors = validate_creation_rules(
        sops_config.get("creation_rules", []), known_keys
    )
    for err in creation_errors:
        result.add_error(err)
    if not creation_errors:
        result.add_ok("All creation_rules define concrete age key references")

    try:
        secret_oks, secret_errors = validate_secrets_file(args.secrets_file, known_keys)
    except FileNotFoundError as exc:
        result.add_error(str(exc))
    else:
        for msg in secret_oks:
            result.add_ok(msg)
        for err in secret_errors:
            result.add_error(err)

    report(result)
    return result.exit_code()


def report(result: LintResult) -> None:
    if result.passed_checks:
        sys.stdout.write("\n".join(f"✓ {msg}" for msg in result.passed_checks) + "\n")
    if result.warnings:
        sys.stdout.write("\n".join(f"⚠ {msg}" for msg in result.warnings) + "\n")
    if result.errors:
        sys.stderr.write("\n".join(f"✗ {msg}" for msg in result.errors) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
