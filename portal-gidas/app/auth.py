"""JWT auth utilities."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import List, Optional

import jwt
from fastapi import Request, HTTPException
from starlette.status import HTTP_401_UNAUTHORIZED

ALGORITHM = "HS256"
COOKIE_NAME = "gidas_session"


def create_token(
    username: str,
    groups: List[str],
    secret: str,
    duration_hours: int = 8,
) -> str:
    """Create signed JWT with user info."""
    now = datetime.now(timezone.utc)
    payload = {
        "sub": username,
        "groups": groups,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(hours=duration_hours)).timestamp()),
    }
    return jwt.encode(payload, secret, algorithm=ALGORITHM)


def decode_token(token: str, secret: str) -> dict:
    """Decode and verify JWT. Raises on invalid/expired."""
    try:
        return jwt.decode(token, secret, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail="Session expired") from exc
    except jwt.InvalidTokenError as exc:
        raise HTTPException(status_code=HTTP_401_UNAUTHORIZED, detail="Invalid session") from exc


def get_user_from_cookie(request: Request, secret: str) -> Optional[dict]:
    """Extract user payload from cookie, or None if not present."""
    token = request.cookies.get(COOKIE_NAME)
    if not token:
        return None
    try:
        return decode_token(token, secret)
    except HTTPException:
        return None
