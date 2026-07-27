"""Minimal REST client for the API endpoints this toolkit needs:
internal (pre-confirmed/pre-approved) account creation and token minting,
profile updates, the multi-tag tagsfeed timeline, and status creation.
"""

import time

import requests

from . import config


class ApiError(RuntimeError):
    def __init__(self, response):
        self.response = response
        try:
            payload = response.json()
        except ValueError:
            payload = {}
        self.error = payload.get("error", response.text)
        super().__init__(f"{response.status_code} {self.error}")


class MastodonClient:
    def __init__(self, base_url=None, access_token=None, internal_token=None):
        self.base_url = (base_url or config.require_base_url()).rstrip("/")
        self.session = requests.Session()
        self.access_token = access_token
        self.internal_token = internal_token or config.INTERNAL_API_TOKEN

    def _headers(self, token=None, internal=False):
        headers = {}
        if internal:
            headers["X-Internal-Token"] = self.internal_token
        else:
            bearer = token or self.access_token
            if bearer:
                headers["Authorization"] = f"Bearer {bearer}"
        return headers

    def _request(self, method, path, token=None, internal=False, retry_on_429=True, **kwargs):
        url = f"{self.base_url}{path}"
        headers = kwargs.pop("headers", {})
        headers.update(self._headers(token=token, internal=internal))
        response = self.session.request(method, url, headers=headers, timeout=30, **kwargs)

        if response.status_code == 429 and retry_on_429:
            wait = int(response.headers.get("X-RateLimit-Reset-After", "60")) or 60
            wait = max(wait, 1)
            print(f"  rate limited on {method} {path}, sleeping {wait}s...")
            time.sleep(wait)
            return self._request(method, path, token=token, internal=internal, retry_on_429=False, headers=headers, **kwargs)

        if not response.ok:
            raise ApiError(response)

        if not response.content:
            return {}
        return response.json()

    # -- internal account provisioning ---------------------------------

    def internal_create_account(self, username, email, confirmed=True, approved=True):
        return self._request(
            "POST",
            "/api/v1/internal/accounts",
            internal=True,
            json={
                "username": username,
                "email": email,
                "confirmed": confirmed,
                "approved": approved,
            },
        )

    def internal_create_token(self, account_id, scopes="read write"):
        return self._request(
            "POST",
            "/api/v1/internal/tokens",
            internal=True,
            json={"account_id": account_id, "scopes": scopes},
        )

    def update_credentials(self, token, display_name):
        return self._request(
            "PATCH",
            "/api/v1/accounts/update_credentials",
            token=token,
            data={"display_name": display_name},
        )

    # -- interest catalog ------------------------------------------------

    def list_interests(self, token=None):
        """GET /api/v1/interests -- the curated, unpaginated interest list
        (name, tags_count, last_status_at). Token-optional: works
        anonymously unless this instance disallows unauthenticated API
        access, in which case pass any account's access token."""
        return self._request("GET", "/api/v1/interests", token=token)

    def list_interest_tags(self, name, token=None):
        """GET /api/v1/interests/:name/tags -- public, but paginated
        (100/page via the standard Link-header cursor), unlike the
        internal-token-guarded unpaginated version. Walks every page and
        returns the full list of tag names for one interest."""
        names = []
        url = f"{self.base_url}/api/v1/interests/{name}/tags"
        params = {"limit": 100}
        headers = self._headers(token=token)

        while url:
            response = self.session.get(url, headers=headers, params=params, timeout=30)

            if response.status_code == 429:
                wait = int(response.headers.get("X-RateLimit-Reset-After", "60")) or 60
                time.sleep(max(wait, 1))
                continue

            if not response.ok:
                raise ApiError(response)

            names.extend(tag["name"] for tag in response.json())

            next_link = response.links.get("next")
            url = next_link["url"] if next_link else None
            params = None  # the next link already carries its own query params

        return names

    # -- timelines / statuses -----------------------------------------

    def tags_timeline(self, tags, token, max_id=None, limit=config.PAGE_LIMIT):
        payload = {"tags": tags, "limit": limit}
        if max_id:
            payload["max_id"] = max_id
        return self._request("POST", "/api/v1/timelines/tags", token=token, json=payload)

    def post_status(self, token, text, in_reply_to_id=None, visibility="public"):
        payload = {"status": text, "visibility": visibility}
        if in_reply_to_id:
            payload["in_reply_to_id"] = in_reply_to_id
        return self._request("POST", "/api/v1/statuses", token=token, json=payload)
