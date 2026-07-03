from __future__ import annotations

from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings
from typing import List, Optional
import yaml
from pathlib import Path


class LDAPConfig(BaseModel):
    host: str = "192.168.1.117"
    port: int = 389
    use_ssl: bool = False
    bind_dn: str = "CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local"
    base_dn: str = "DC=GDC01,DC=local"
    user_search_filter: str = "(sAMAccountName={username})"
    group_attribute: str = "memberOf"


class PortalConfig(BaseModel):
    title: str = "Portal GIDAS"
    subtitle: str = ""
    logo: str = "logo-gidas.png"
    session_duration_hours: int = 8


class ToolItem(BaseModel):
    name: str
    url: str
    icon: str
    description: str = ""
    groups: List[str]
    proxy: bool = False
    slug: str = ""  # URL path for proxy (defaults to name.lower())


class AppConfig(BaseModel):
    portal: PortalConfig = PortalConfig()
    ldap: LDAPConfig = LDAPConfig()
    tools: List[ToolItem] = []


class Settings(BaseSettings):
    jwt_secret: str = Field(default="change-me-in-production", alias="JWT_SECRET")
    ldap_bind_password: str = Field(default="", alias="LDAP_BIND_PASSWORD")
    config_path: str = Field(default="config.yaml", alias="CONFIG_PATH")
    debug: bool = Field(default=False, alias="DEBUG")

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


def load_config(path: str | Path) -> AppConfig:
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")
    raw = yaml.safe_load(path.read_text())
    return AppConfig.model_validate(raw)
