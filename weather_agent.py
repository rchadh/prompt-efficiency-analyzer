
"""Lab 1 weather agent."""

import requests
from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp import MCPClient
from mcp.client.streamable_http import streamablehttp_client
from bedrock_agentcore.runtime import BedrockAgentCoreApp

import settings

INSTRUCTIONS = """You are a weather assistant.

Rules:
- You do not know the weather. Always use your tool to find it.
- Never guess a temperature.
- If the city name could match several places, ask which one the user means.
- Say which city you looked up, so the user can spot a wrong match.
- Keep answers to two or three sentences.
"""
app = BedrockAgentCoreApp()

@app.entrypoint
def invoke(payload, context=None):
    """Runtime calls this. payload comes from whoever invokes the agent."""
    question = payload.get("prompt", "")
    gateway = make_gateway_client()
    with gateway:
        agent = Agent(
            model=BedrockModel(
                model_id=settings.MODEL_ID, region_name=settings.REGION
            ),
            system_prompt=INSTRUCTIONS,
            tools=gateway.list_tools_sync(),
        )
        return {"result": str(agent(question))}

def get_token():
    response = requests.post(
        settings.TOKEN_URL,
        data={
            "grant_type": "client_credentials",
            "client_id": settings.CLIENT_ID,
            "client_secret": settings.CLIENT_SECRET,
            "scope": settings.SCOPE,
        },
        timeout=15,
    )
    response.raise_for_status()
    return response.json()["access_token"]


def make_gateway_client():
    token = get_token()
    return MCPClient(
        lambda: streamablehttp_client(
            settings.GATEWAY_URL,
            headers={"Authorization": f"Bearer {token}"},
        )
    )


def main():
    print("Connecting to the gateway123...")
    gateway = make_gateway_client()

    with gateway:
        tools = gateway.list_tools_sync()
        print(f"Tools available: {[t.tool_name for t in tools]}\n")

        agent = Agent(
            model=BedrockModel(
                model_id=settings.MODEL_ID, region_name=settings.REGION
            ),
            system_prompt=INSTRUCTIONS,
            tools=tools,
        )

        print("Ask me about the weather. Type quit to exit.\n")
        while True:
            question = input("You: ").strip()
            if question.lower() in ("quit", "exit"):
                break
            if not question:
                continue
            answer = agent(question)
            print(f"\nAgent: {answer}\n")


if __name__ == "__main__":
    import sys

    if "--chat" in sys.argv:
        main()             # local interactive testing
    else:
        app.run()          # default — this is what Runtime needs