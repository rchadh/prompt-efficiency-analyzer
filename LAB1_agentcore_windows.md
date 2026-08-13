# Lab 1 — Weather chat agent on Amazon Bedrock AgentCore

**For Windows. No Docker needed.**

## What you will build

A chat agent that answers weather questions.

```
You:   What is the weather in Gurugram?
Agent: It is 34°C in Gurugram with haze.
```

The agent does not know the weather. It calls a tool. The tool is a real
weather API, published to the agent by AgentCore Gateway.

You will use four AgentCore features:

| Feature       | What it does here                                    |
| ------------- | ---------------------------------------------------- |
| Gateway       | Turns the weather API into a tool the agent can call |
| Identity      | Stores the weather API key and adds it to each call  |
| Runtime       | Hosts the agent in AWS                               |
| Observability | Shows you the traces of what happened                |

Not in this lab: custom MCP server, Memory, Evaluations. Those are Lab 2, 3
and 4. One thing at a time.

**Time:** about 90 minutes.

---

# Part A — Get ready

## Step 1. Get a free weather API key

1. Go to `https://openweathermap.org/api`
2. Create a free account.
3. Go to `https://home.openweathermap.org/api_keys`
4. Copy the key. It looks like `a1b2c3d4e5f6...`

**Important:** a new key takes about 10 minutes to start working. Do this step
first so it is ready when you need it.

**Check it worked.** Open this URL in your browser. Replace `YOUR_KEY`:

```
https://api.openweathermap.org/data/2.5/weather?q=Gurugram&units=metric&appid=YOUR_KEY
```

You should see JSON with a temperature. If you see
`{"cod":401, "message":"Invalid API key..."}`, wait 10 minutes and try again.

---

## Step 2. Check your tools on Windows

Open **Command Prompt** (press Windows key, type `cmd`, press Enter).

Run these one at a time:

```
python --version
```
Need 3.10 or higher. If missing, install from `https://www.python.org/downloads/`
and tick **Add Python to PATH** during install.

```
aws --version
```
If missing, install the AWS CLI from
`https://awscli.amazonaws.com/AWSCLIV2.msi`, then close and reopen Command
Prompt.

```
aws sts get-caller-identity
```
This should print your AWS account number. If it does not, run `aws configure`
and enter your access key, secret key, region `us-east-1`, and output `json`.

**Write down your AWS account number.** You will need it later.

---

## Step 3. Turn on model access in Bedrock

1. Open the AWS Console. Make sure the region at the top right says
   **US East (N. Virginia) us-east-1**. Use this region for the whole lab.
2. Search for **Bedrock** and open it.
3. In the left menu click **Model access**.
4. Find **Claude Sonnet 4.5**. If it says *Access granted*, you are done.
5. If not, click **Modify model access**, tick it, and submit. It is usually
   approved in under a minute.

**If stuck:** if you cannot find that model, any Claude model will work. Just
note its exact model ID from the **Model catalog** page. You will paste it in
Step 9.

---

## Step 4. Make your project folder

In Command Prompt:

```
mkdir C:\agentcore-lab1
cd C:\agentcore-lab1
python -m venv .venv
.venv\Scripts\activate
```

Your prompt should now start with `(.venv)`.

**Note:** on Windows the command is `.venv\Scripts\activate`. The `source`
command you saw before is for Linux and Mac. It will not work here.

Now install the libraries:

```
pip install strands-agents mcp boto3 requests bedrock-agentcore bedrock-agentcore-starter-toolkit
```

This takes a few minutes.

**Check it worked:**

```
python -c "import strands, mcp, boto3; print('ok')"
```

Should print `ok`.

---

# Part B — Create AWS resources in the console

## Step 5. Store the weather API key in AgentCore Identity

This lets Gateway add your API key to every call, so the agent never sees it.

1. In the AWS Console, search for **Bedrock AgentCore** and open it.
2. Left menu → **Identity**.
3. Find the section for outbound credentials. Click **Add API key**.
4. Name: `lab1-weather-key`
5. API key: paste your OpenWeather key from Step 1.
6. Click **Add**.

**Write down** the credential provider name: `lab1-weather-key`

---

## Step 6. Create the API description file and upload it to S3

Gateway needs a description of the weather API. This is an OpenAPI file.

### 6a. Create the file

In Command Prompt (make sure you are in `C:\agentcore-lab1`):

```
notepad openweather.yaml
```

Notepad opens and asks to create a new file. Click **Yes**. Paste this in:

```yaml
openapi: 3.0.3
info:
  title: Weather
  version: "1.0"
servers:
  - url: https://api.openweathermap.org
paths:
  /data/2.5/weather:
    get:
      operationId: getWeather
      summary: Get the current weather for a city
      description: >-
        Returns the current temperature, conditions and humidity for a city.
        Use this whenever the user asks about weather anywhere.
      parameters:
        - name: q
          in: query
          required: true
          description: >-
            City name. You can add a country code, for example "Gurugram,IN"
            or "Austin,US". Use the country code when a city name is common.
          schema:
            type: string
        - name: units
          in: query
          required: false
          description: >-
            Use "metric" for Celsius or "imperial" for Fahrenheit.
          schema:
            type: string
            default: metric
      responses:
        "200":
          description: Current weather
          content:
            application/json:
              schema:
                type: object
```

Save the file (Ctrl+S) and close Notepad.

**Note on the API key:** the OpenWeather API needs a parameter called `appid`.
It is deliberately **not** in this file. Gateway adds it automatically from
Step 5. If you add it here, the agent will try to invent a key and every call
will fail with a 401 error.

### 6b. Upload it to S3

1. AWS Console → search **S3** → open it.
2. Click **Create bucket**.
3. Bucket name: `agentcore-lab1-` plus your AWS account number.
   Example: `agentcore-lab1-123456789012`
4. Region: **us-east-1**. Leave everything else default. Click **Create bucket**.
5. Open the bucket. Click **Upload** → **Add files**.
6. Select `C:\agentcore-lab1\openweather.yaml`. Click **Upload**.
7. Click on the uploaded file. Copy the **S3 URI**. It looks like
   `s3://agentcore-lab1-123456789012/openweather.yaml`

**Write down the S3 URI.**

---

## Step 7. Create the Gateway

This is the main step. Take your time.

1. AWS Console → **Bedrock AgentCore** → left menu → **Gateways**.
2. Click **Create gateway**.
3. **Name:** `lab1-gateway`
4. **Protocol:** MCP
5. **Service role:** choose *Create and use a new service role*.
6. **Semantic search:** leave it **OFF**. Once you turn it on for a gateway you
   cannot turn it off. You only have one tool, so you do not need it.
7. **Exception level:** set to **debug** if you see the option. This gives you
   real error messages instead of generic ones. It will save you time.
8. **Inbound authentication:** choose **Quick create with Cognito** (the wording
   may be slightly different, look for the option that creates Cognito for you).
   This creates the login setup automatically. Without it you would have to
   build a Cognito user pool by hand.
9. **Target** section. This is the weather API:
   - Target name: `weather`
   - Target type: **OpenAPI**
   - Schema: paste the S3 URI from Step 6b
   - Outbound authentication: **API key**
   - Credential provider: `lab1-weather-key`
   - Credential location: **Query parameter**
   - Parameter name: `appid`
10. Click **Create**.

Wait until the status says **Ready**. This takes a minute or two.

### What to write down

Open the gateway you just created. From the details page copy:

| What              | Looks like                                                                        |
| ----------------- | --------------------------------------------------------------------------------- |
| Gateway URL       | `https://lab1-gateway-xxxx.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp` |
| Cognito client ID | `1a2b3c4d5e6f7g8h9i0j`                                                            |
| Cognito token URL | `https://xxxx.auth.us-east-1.amazoncognito.com/oauth2/token`                      |
| Scope             | something like `lab1-gateway/invoke` or `default-m2m-resource-server-xxx/read`    |

You also need the **client secret**, which the gateway page may not show:

1. AWS Console → search **Cognito** → open it.
2. Click the user pool that was created (name contains `lab1` or `agentcore`).
3. Left menu → **App clients**. Click the client.
4. Find **Client secret** and click **Show client secret**. Copy it.

**Check it worked:** the gateway detail page should list one tool named
`weather___getWeather`. Note the three underscores. Gateway always names tools
as `targetname___operationid`.

---

# Part C — Build and run the agent

## Step 8. Save your settings

In Command Prompt:

```
notepad settings.py
```

Click **Yes** to create it. Paste this and fill in your five values:

```python
# Lab 1 settings. Paste your own values between the quotes.

GATEWAY_URL   = "PASTE_GATEWAY_URL_HERE"
TOKEN_URL     = "PASTE_COGNITO_TOKEN_URL_HERE"
CLIENT_ID     = "PASTE_CLIENT_ID_HERE"
CLIENT_SECRET = "PASTE_CLIENT_SECRET_HERE"
SCOPE         = "PASTE_SCOPE_HERE"

REGION   = "us-east-1"
MODEL_ID = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
```

Save and close.

**Note:** putting secrets in a file is fine for a lab on your own machine. In
real work these would come from Secrets Manager. We are keeping it simple here
so there is less to go wrong.

---

## Step 9. Test the gateway before writing the agent

Do not skip this. If the gateway is broken, you want to know now, not while
also debugging agent code.

```
notepad check_gateway.py
```

Paste this:

```python
"""Check that the gateway works. Run this before building the agent."""

import requests
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client
import asyncio

import settings


def get_token():
    """Log in to Cognito and get a token for the gateway."""
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
```

Save, close, and run it:

```
python check_gateway.py
```

**You should see** all four steps pass, one tool listed, and real weather JSON.

### If it fails

| Message                         | What it means                                  | Fix                                                            |
| ------------------------------- | ---------------------------------------------- | -------------------------------------------------------------- |
| `401` from Cognito at step 1    | Client ID, secret or scope is wrong            | Re-copy them from the Cognito console                          |
| `403` at step 2                 | The token is fine but the gateway rejected it  | Check the scope matches exactly what the gateway expects       |
| `invalid_scope`                 | Scope string is wrong                          | Cognito console → App clients → look at the exact scope listed |
| Step 3 lists no tools           | The target did not sync                        | Gateway console → Targets → check status and error message     |
| Step 4 returns 401 from weather | API key not active, or `appid` is in your YAML | Wait 10 min, and confirm `appid` is not in openweather.yaml    |

**Do not go to Step 10 until this script passes.**

---

## Step 10. Write the agent

```
notepad weather_agent.py
```

Paste this:

```python
"""Lab 1 weather agent."""

import requests
from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp import MCPClient
from mcp.client.streamable_http import streamablehttp_client

import settings

INSTRUCTIONS = """You are a weather assistant.

Rules:
- You do not know the weather. Always use your tool to find it.
- Never guess a temperature.
- If the city name could match several places, ask which one the user means.
- Say which city you looked up, so the user can spot a wrong match.
- Keep answers to two or three sentences.
"""


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
    print("Connecting to the gateway...")
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
    main()
	```

Save, close, and run:

```
python weather_agent.py
```

Try these:

```
What is the weather in Gurugram?
Is it hotter in Delhi or Mumbai right now?
What is the weather in Springfield?
```

The third one is a test. There are many places called Springfield. A good agent
asks which one you mean.

### If it fails

| Message | Fix |
|---|---|
| `AccessDeniedException` on Bedrock | Model access not granted. Go back to Step 3. |
| `ValidationException: model ID` | Wrong model ID in settings.py. Copy the exact ID from the Bedrock model catalog. |
| Agent answers without calling the tool | It is guessing. Tell it directly: "Use your tool to check." Then make the instructions stricter. |
| Import error on `strands` | Your virtual environment is not active. Run `.venv\Scripts\activate` again. |

---

# Part D — Deploy to AgentCore Runtime

Right now the agent runs on your laptop. Now put it in AWS.

## Step 11. Deploy

The AgentCore CLI packages your code and deploys it. It builds in AWS, so you
do **not** need Docker on Windows.

In Command Prompt, in `C:\agentcore-lab1`:

```
agentcore configure --entrypoint weather_agent.py --name lab1_weather_agent
```

Answer the prompts:
- Execution role: let it create one
- Requirements file: let it detect, or point at a `requirements.txt` if it asks
- Authorization: choose **IAM** for now (simplest)

Then deploy:

```
agentcore launch
```

This takes 5 to 10 minutes the first time. It uploads your code, builds it in
AWS CodeBuild, and creates the Runtime.

**Note:** the agent code needs a small change to run in Runtime. Runtime calls
your code instead of you typing at a prompt. Add this to the **bottom** of
`weather_agent.py`, above the `if __name__` block:

```python
from bedrock_agentcore.runtime import BedrockAgentCoreApp

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
```

And change the last block to:

```python
if __name__ == "__main__":
    import sys

    if "--serve" in sys.argv:
        app.run()          # used by Runtime
    else:
        main()             # used by you on your laptop
```

Re-run `agentcore launch` after making this change.

**Check it worked:**

```
agentcore invoke "{\"prompt\": \"What is the weather in Gurugram?\"}"
```

Note the backslashes before the quotes. Windows Command Prompt needs them.

---

## Step 12. Look at the traces

1. AWS Console → **CloudWatch**.
2. Left menu → **GenAI Observability**.
3. Find your agent. Open a session.

You will see the full trace: the question, the model's decision to call the
tool, the tool call and its timing, and the final answer.

**If you see nothing:** Transaction Search may be off. Go to CloudWatch →
**Application Signals** → **Transaction Search** → **Enable**. Then run the
agent again. Traces are not backfilled, so old runs will not appear.

---

# Clean up when you are done

Delete in this order:

1. AgentCore → Runtime → delete `lab1_weather_agent`
2. AgentCore → Gateways → delete the target, then the gateway
3. AgentCore → Identity → delete `lab1-weather-key`
4. Cognito → delete the user pool that was created
5. S3 → empty and delete the bucket

---

# What you learned, and what comes next

You have now seen the four pieces working together. The one worth thinking
about: your agent never saw the weather API key, and never knew the API's real
URL. It only saw a tool called `weather___getWeather`. That separation is the
whole reason Gateway exists, and it is what makes 1,600 APIs manageable.

**Lab 2:** add Memory, so the agent remembers the last city and you can ask
"and tomorrow?"

**Lab 3:** build your own MCP server and connect it to the same gateway. Then
compare it with this OpenAPI target.

**Lab 4:** add Evaluations to score how well the agent picks tools.
