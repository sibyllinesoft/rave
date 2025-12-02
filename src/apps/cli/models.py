"""Pydantic models shared by the CLI."""

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator


class VMPorts(BaseModel):
    """Validated port mapping for a VM."""

    model_config = ConfigDict(extra="allow")

    http: int = Field(..., ge=1, le=65535)
    https: int = Field(..., ge=1, le=65535)
    ssh: int = Field(..., ge=1, le=65535)
    test: int = Field(..., ge=1, le=65535)

    @field_validator("http", "https", "ssh", "test")
    @classmethod
    def ensure_port(cls, value: int) -> int:
        if not isinstance(value, int):
            raise TypeError("Port values must be integers")
        return value


class VMConfigModel(BaseModel):
    """Canonical VM configuration representation."""

    model_config = ConfigDict(extra="allow")

    name: str
    image_path: str
    profile: Optional[str] = None
    profile_attr: Optional[str] = None
    ports: VMPorts
    keypair: Optional[str] = None
    auto_registered: bool = False
    status: Optional[str] = None
    created_at: Optional[float] = None
    updated_at: Optional[float] = None

    @field_validator("name", "image_path")
    @classmethod
    def not_blank(cls, value: str) -> str:
        if not value or not str(value).strip():
            raise ValueError("value cannot be blank")
        return value
