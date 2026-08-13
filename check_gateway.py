"""Check that the gateway works. Run this before building the agent."""

import asyncio

import requests
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

import settings


def get_token():
    """Log in to Cognito and get a token for the gateway."""
    response = requests.post(
        settings.TOKEN_URL,
        data={
            "grant_type": "client_credentials",
            "scope": settings.SCOPE,
        },
        auth=(settings.CLIENT_ID, settings.CLIENT_SECRET),
        timeout=15,
    )
    if response.status_code != 200:
        print("   Cognito rejected the login--00.")
        print("   Status:", response.status_code)
        print("   Reply :", response.text)
        raise SystemExit("Fix the problem above, then run this again.")
    return response.json()["access_token"]


async def main():
    print("1. Getting a token from Cognito...")
    token = get_token()
    print("   OK\n")

    print("2. Connecting to the gateway...")
    headers = {"Authorization": f"Bearer {token}"}
    async with streamablehttp_client(settings.GATEWAY_URL, headers=headers) as (
        read,
        write,
        _,
    ):
        async with ClientSession(read, write) as session:
            await session.initialize()
            print("   OK\n")

            print("3. Listing the tools the gateway offers...")
            tools = await session.list_tools()
            for tool in tools.tools:
                print(f"   - {tool.name}")
            print()

            print("4. Calling the weather tool for Gurugram...")
            result = await session.call_tool(
                "weather___getWeather", {"q": "Gurugram,IN", "units": "metric"}
            )
            print(result.content[0].text[:400])


asyncio.run(main())