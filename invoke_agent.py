"""
Invoke an AgentCore Runtime agent over the HTTPS InvokeAgentRuntime endpoint
using a JWT bearer token.

Why not boto3? A runtime configured with JWT (OAuth) inbound auth cannot be
called through boto3 - the bedrock-agentcore client signs with SigV4 and has
no parameter for a bearer token. You must call the HTTPS endpoint directly.

Usage (Windows):
    cd C:\\agentcore-lab1
    .venv\\Scripts\\activate
    pip install requests boto3
    python invoke_agent.py "What is the weather in Delhi?"
"""

import json
import sys
import urllib.parse
import uuid

import boto3
import requests

import settings


def get_bearer_token():
    """Fetch a Cognito access token.

    Uses client-credentials if COGNITO_CLIENT_SECRET is set, otherwise
    falls back to the user login flow.
    """
    if settings.COGNITO_CLIENT_SECRET:
        resp = requests.post(
            settings.COGNITO_TOKEN_URL,
            data={"grant_type": "client_credentials", "scope": settings.COGNITO_SCOPE},
            auth=(settings.COGNITO_CLIENT_ID, settings.COGNITO_CLIENT_SECRET),
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["access_token"]

    cognito = boto3.client("cognito-idp", region_name=settings.REGION)
    resp = cognito.initiate_auth(
        ClientId=settings.COGNITO_CLIENT_ID,
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={
            "USERNAME": settings.COGNITO_USERNAME,
            "PASSWORD": settings.COGNITO_PASSWORD,
        },
    )
    return resp["AuthenticationResult"]["AccessToken"]


def new_session_id():
    """AgentCore requires a session id of 33 characters or more.

    Two hex UUIDs give 64 characters, comfortably over the limit.
    Reuse the same value across calls to stay on one runtime session.
    """
    return uuid.uuid4().hex + uuid.uuid4().hex


def build_url():
    """Assemble the invocation URL.

    The ARN must be FULLY url-encoded - every ':' and '/' escaped.
    Leaving off safe='' is the usual cause of a 404 here.
    """
    escaped_arn = urllib.parse.quote(settings.AGENT_ARN, safe="")
    return (
        f"https://bedrock-agentcore.{settings.REGION}.amazonaws.com"
        f"/runtimes/{escaped_arn}/invocations?qualifier={settings.QUALIFIER}"
    )


def invoke(prompt, session_id=None):
    token = get_bearer_token()
    url = build_url()

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id": session_id or new_session_id(),
        "X-Amzn-Trace-Id": f"local-{uuid.uuid4().hex[:12]}",
    }

    # Whatever keys you put here are the keys your agent reads from `payload`.
    # There is no fixed schema - "prompt" is only a convention.
    body = {"prompt": prompt}

    resp = requests.post(
        url,
        headers=headers,
        data=json.dumps(body),
        timeout=180,
        stream=True,
    )

    print(f"Status: {resp.status_code}")

    if resp.status_code != 200:
        print(resp.text[:1000])
        _explain_error(resp.status_code)
        return

    content_type = resp.headers.get("Content-Type", "")

    if "text/event-stream" in content_type:
        # Streaming agent - server-sent events.
        for line in resp.iter_lines(decode_unicode=True):
            if line and line.startswith("data: "):
                print(line[6:], flush=True)
    else:
        print(json.dumps(resp.json(), indent=2))


def _explain_error(status):
    hints = {
        404: "ARN was probably not url-encoded. Check quote(arn, safe='').",
        403: "Session id is likely under 33 characters.",
        401: "Missing/expired token, or iss / client_id do not match the "
             "runtime authorizer. Decode the token at jwt.io and compare.",
    }
    if status in hints:
        print(f"\nHint: {hints[status]}")


if __name__ == "__main__":
    question = sys.argv[1] if len(sys.argv) > 1 else "What is the weather in Delhi?"
    invoke(question)
