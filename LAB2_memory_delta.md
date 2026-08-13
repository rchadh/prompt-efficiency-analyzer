# Lab 2 — Give your agent a memory

**This builds on Lab 1. Do not create anything new except one memory store.**

You already have: the folder, the venv, `settings.py`, `weather_agent.py`, the
gateway, Cognito, and a deployed runtime. All of that stays as it is.

## What you will add

Right now your agent forgets everything the moment you close it.

```
You:   What is the weather in Gurugram?
Agent: It is 34°C in Gurugram with haze.
You:   Is that hotter than usual?
Agent: Hotter than usual where?          <- it forgot
```

After this lab it remembers. Not just within one chat, but across restarts.

**New AWS resource:** one memory store.
**Files you change:** `settings.py` and `weather_agent.py`.
**Time:** about 40 minutes.

---

## Step 1. Create the memory store

1. AWS Console → **Bedrock AgentCore** → left menu → **Memory**.
2. Click **Create memory**.
3. Name: `lab2_memory`
4. **Do not add any strategies.** You may see options for summarisation, user
   preferences, or semantic memory. Leave all of them off.
5. Event expiry: 7 days.
6. Click **Create**. Wait for status **Active**. Takes about a minute.

**Write down the Memory ID.** It looks like `lab2_memory-AbCdEf1234`.

### Why no strategies

A memory store with no strategies just saves the conversation as it happened.
Nothing is processed. That is short-term memory, and it is all a chat agent
needs to follow a conversation.

Strategies are the long-term part. They run a model over your conversations in
the background to pull out facts and preferences, so the agent remembers things
weeks later. That is a real capability but it has its own failure modes, and
you want to look at those on their own. That is Lab 5 territory.

---

## Step 2. Add the memory ID to settings.py

```
notepad settings.py
```

Add one line at the bottom:

```python
MEMORY_ID = "PASTE_YOUR_MEMORY_ID_HERE"
```

Save and close.

---

## Step 3. Replace weather_agent.py

**Clear the whole file and paste this in.** Do not try to edit the old one line
by line. That is what caused your indentation error last time.

```
notepad weather_agent.py
```

Press **Ctrl+A**, then **Delete**. The file should be empty. Now paste:

```python
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
```

Save and close.

### What changed from Lab 1

Four things, and nothing else:

1. `load_history()` reads past turns from AgentCore Memory.
2. `save_turn()` writes each new turn back.
3. `build_agent()` passes that history to Strands as `messages=`.
4. `main()` accepts a `--session` argument so you can return to a conversation.

---

## Step 4. Test it on your laptop

Open Command Prompt, go to your folder, activate the venv:

```
cd C:\path\to\agentcore-lab1
.venv\Scripts\activate
```

Run a chat:

```
python weather_agent.py --chat --session lab2-test
```

Have this conversation:

```
You: What is the weather in Gurugram?
	You: Is it humid there?
```

The second question has no city in it. The agent should still know you mean
Gurugram.

**Now the real test.** Type `quit`. Then start it again with the same session:

```
python weather_agent.py --chat --session lab2-test
```

It should say `Loaded 4 earlier messages.` Then ask:

```
You: Which city did I ask about last time?
```

It should answer Gurugram. That is memory working across restarts.

### If something goes wrong

| What you see | What it means | Fix |
|---|---|---|
| `Loaded 0 earlier messages` on the second run | The session name did not match | Use the exact same `--session` value both times |
| `AccessDeniedException` on `create_event` | Your AWS user cannot write to memory | Add `bedrock-agentcore:CreateEvent` and `bedrock-agentcore:ListEvents` to your IAM user |
| `ResourceNotFoundException` | Wrong memory ID | Re-copy it from the console, including the part after the dash |
| Agent replies in the wrong order or repeats itself | History came back newest-first | In `load_history`, change `for turn in turns:` to `for turn in reversed(turns):` |
| Memory works but the agent still asks "which city?" | The instructions are not strong enough | Fine. Note it. This is a real finding about prompt versus memory. |

---

## Step 5. Let the deployed agent use memory

Your runtime has its own IAM role, and right now that role cannot touch memory.

1. AWS Console → **IAM** → **Roles**.
2. Search for the role created for `lab1_weather_agent`. The name usually
   contains `AmazonBedrockAgentCoreRuntime` or your agent name.
3. Click it → **Add permissions** → **Create inline policy** → **JSON** tab.
4. Delete what is there and paste this. Replace `YOUR_ACCOUNT_NUMBER`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:CreateEvent",
        "bedrock-agentcore:ListEvents",
        "bedrock-agentcore:GetEvent",
        "bedrock-agentcore:ListSessions",
        "bedrock-agentcore:GetMemory"
      ],
      "Resource": "arn:aws:bedrock-agentcore:us-east-1:YOUR_ACCOUNT_NUMBER:memory/*"
    }
  ]
}
```

5. Name it `lab2-memory-access`. Click **Create policy**.

---

## Step 6. Redeploy

```
agentcore launch
```

Wait for it to finish. Then test, using the same session ID twice:

```
agentcore invoke --session-id lab2aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "{\"prompt\": \"What is the weather in Gurugram?\"}"
```

```
agentcore invoke --session-id lab2aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "{\"prompt\": \"Which city did I just ask about?\"}"
```

The second call should answer Gurugram.

**Note the long session ID.** AgentCore Runtime requires session IDs of at
least 33 characters. A short one will be rejected. That is why it looks silly.

**If it fails,** read the logs:

```
aws logs tail "/aws/bedrock-agentcore/runtimes/YOUR_AGENT_ID-DEFAULT" --since 10m --region us-east-1
```

Use the same agent ID you used for Lab 1 debugging.

---

## Step 7. See the memory in the console

AWS Console → **Bedrock AgentCore** → **Memory** → `lab2_memory`.

You should be able to browse actors, sessions and the events inside them. Your
`lab2-test` session from Step 4 and your long runtime session from Step 6
should both be there.

---

## What to take away

Two things worth noting for your platform architecture work:

**The session ID is the boundary.** Everything about who sees what comes down
to the `actor_id` and `session_id` you pass. Get those wrong in a real system
and one customer sees another customer's conversation. In Lab 1 there was no
such risk because nothing was stored. That changes the moment you add memory,
and it is worth deciding early who owns generating those IDs.

**Nothing was summarised.** Every turn is stored in full and replayed in full.
That works at ten turns. At two hundred turns you will blow the context window
and the cost. The fix is a summarisation strategy, which is the long-term
memory feature. You now have a concrete reason to want it, which is a better
place to learn it from than a feature list.

**Next:** Lab 3, where you build your own MCP server and add it to the same
gateway as a second target.
