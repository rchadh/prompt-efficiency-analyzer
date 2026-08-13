"""Lab 2 weather agent - now with memory."""

import sys
import uuid

import requests
from bedrock_agentcore.memory import MemoryClient
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from mcp.client.streamable_http import streamablehttp_client
from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp import MCPClient

import settings

INSTRUCTIONS = """You are a weather assistant.

Rules:
- You do not know the weather. Always use your tool to find it.
- Never guess a temperature.
- If the city name could match several places, ask which one the user means.
- Say which city you looked up, so the user can spot a wrong match.
- Keep answers to two or three sentences.
- You can see earlier messages in this conversation. Use them. If the user
  says "there" or "that city", they mean the city discussed earlier.
"""

memory = MemoryClient(region_name=settings.REGION)


# ---------- gateway ----------

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
    if response.status_code != 200:
        print("Cognito rejected the login:", response.status_code, response.text)
        raise SystemExit(1)
    return response.json()["access_token"]


def make_gateway_client():
    token = get_token()
    return MCPClient(
        lambda: streamablehttp_client(
            settings.GATEWAY_URL,
            headers={"Authorization": f"Bearer {token}"},
        )
    )


# ---------- memory ----------

def load_history(actor_id, session_id, k=10):
    """Read the last k turns of this conversation back from AgentCore Memory."""
    try:
        turns = memory.get_last_k_turns(
            memory_id=settings.MEMORY_ID,
            actor_id=actor_id,
            session_id=session_id,
            k=k,
        )
    except Exception as error:
        print(f"[memory] nothing to load yet ({error})")
        return []

    messages = []
    for turn in turns:
        for item in turn:
            role = "assistant" if item.get("role") == "ASSISTANT" else "user"
            text = item.get("content", {}).get("text", "")
            if text:
                messages.append({"role": role, "content": [{"text": text}]})
    return messages


def save_turn(actor_id, session_id, question, answer):
    """Write this question and answer into AgentCore Memory."""
    memory.create_event(
        memory_id=settings.MEMORY_ID,
        actor_id=actor_id,
        session_id=session_id,
        messages=[(question, "USER"), (answer, "ASSISTANT")],
    )


# ---------- agent ----------

def build_agent(tools, history):
    return Agent(
        model=BedrockModel(model_id=settings.MODEL_ID, region_name=settings.REGION),
        system_prompt=INSTRUCTIONS,
        tools=tools,
        messages=history,
    )


# ---------- running on your laptop ----------

def main():
    session_id = "local-session-1"
    for index, argument in enumerate(sys.argv):
        if argument == "--session" and index + 1 < len(sys.argv):
            session_id = sys.argv[index + 1]

    actor_id = "rahul"
    print(f"Session: {session_id}")
    print("Connecting to the gateway...")

    gateway = make_gateway_client()
    with gateway:
        tools = gateway.list_tools_sync()
        history = load_history(actor_id, session_id)
        print(f"Loaded {len(history)} earlier messages.\n")

        agent = build_agent(tools, history)

        print("Ask me about the weather. Type quit to exit.\n")
        while True:
            question = input("You: ").strip()
            if question.lower() in ("quit", "exit"):
                break
            if not question:
                continue
            answer = str(agent(question))
            print(f"\nAgent: {answer}\n")
            save_turn(actor_id, session_id, question, answer)


# ---------- running on AgentCore Runtime ----------

app = BedrockAgentCoreApp()


@app.entrypoint
def invoke(payload, context=None):
    question = payload.get("prompt", "")
    actor_id = payload.get("actor_id", "rahul")
    session_id = getattr(context, "session_id", None) or str(uuid.uuid4())

    gateway = make_gateway_client()
    with gateway:
        history = load_history(actor_id, session_id)
        agent = build_agent(gateway.list_tools_sync(), history)
        answer = str(agent(question))

    save_turn(actor_id, session_id, question, answer)
    return {"result": answer, "session_id": session_id}


if __name__ == "__main__":
    if "--chat" in sys.argv:
        main()
    else:
        app.run()