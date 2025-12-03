"""Pydantic settings for the RAVE CLI."""

from __future__ import annotations

from pathlib import Path
from typing import Dict

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class CLISettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="RAVE_",
        env_file=".env",
        extra="ignore",
    )

    default_profile: str = Field(
        "development", description="Default profile used when launching VMs."
    )
    config_dir: Path = Field(
        default=Path.home() / ".config" / "rave",
        description="Base directory for CLI state.",
    )
    port_http: int = Field(8081, description="Host HTTP port forwarded to the VM.")
    port_https: int = Field(8443, description="Host HTTPS port forwarded to the VM.")
    port_ssh: int = Field(2224, description="Host SSH port forwarded to the VM.")
    port_test: int = Field(8889, description="Host test port forwarded to the VM.")

    def port_config(self) -> Dict[str, int]:
        return {
            "http": self.port_http,
            "https": self.port_https,
            "ssh": self.port_ssh,
            "test": self.port_test,
        }
