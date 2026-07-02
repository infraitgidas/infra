from __future__ import annotations

from typing import List, Optional
from pydantic import BaseModel


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    message: str = "Logged in"


class UserInfo(BaseModel):
    username: str
    groups: List[str]


class ToolResponse(BaseModel):
    name: str
    url: str
    icon: str
    description: str


class DashboardData(BaseModel):
    username: str
    groups: List[str]
    tools: List[ToolResponse]


class ErrorResponse(BaseModel):
    detail: str
