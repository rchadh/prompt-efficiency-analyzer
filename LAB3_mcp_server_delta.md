# Lab 3 — Build your own MCP server

**Builds on Labs 1 and 2. Your gateway, Cognito, memory store and agent all stay as they are.**

## What you will build

In Lab 1 you pointed the gateway at an OpenAPI file and AWS turned it into a
tool. You wrote no code for that tool.

Now you write the tool yourself. A small Python MCP server, hosted on AgentCore
Runtime, added to the **same gateway** as a second target.

After this lab your one gateway exposes tools from two different sources:

```
weather___getWeather          <- from the OpenAPI file (Lab 1)
wxmcp___get_weather           <- from your own code (Lab 3)
wxmcp___compare_cities        <- from your own code (Lab 3)
```

That third tool is the point. It does something the OpenAPI target cannot:
one tool call that fetches two cities and compares them. A raw API spec can
only give the agent what the API already has. A facade can give it what you
decide it should have.

**New AWS resources:** one Runtime (the MCP server), one gateway target.
**Time:** about 75 minutes.

**Not in this lab:** measuring which approach is better. That is Lab 4. Here
you just get both working side by side.

---

## Step 1. Make a separate folder

Do **not** build this inside your Lab 1 folder. Two agents sharing one
`.bedrock_agentcore.yaml` means plain `agentcore launch` redeploys the wrong
one, and the change appears to do nothing.

In Command Prompt:

```
cd C:\Users\rahul\OneDrive\Documents\AI\AWS\AgentCore-Labs
mkdir agentcore-lab3-mcp
cd agentcore-lab3-mcp
python -m venv .venv
.venv\Scripts\activate
pip install mcp httpx bedrock-agentcore bedrock-agentcore-starter-toolkit
```

**Check it worked:**

```
python -c "import mcp, httpx; print('ok')"
```

---

## Step 2. Save the API key

```
notepad mcp_settings.py
```

Paste, and fill in the same OpenWeather key you used in Lab 1:

```python
OPENWEATHER_API_KEY = "PASTE_YOUR_OPENWEATHER_KEY_HERE"
```

Save and close.

**Note the difference from Lab 1.** There, the gateway held the API key in a
credential provider and injected it. Here, your server holds its own key. Same
API, two ownership models. Remember this when you get to Lab 4 — it is one of
the real differences between the two patterns, and in a regulated environment
it is the one your security team will ask about.

For a lab, a key in a file is fine. In production this would come from Secrets
Manager.

---

## Step 3. Write the MCP server

```
notepad weather_mcp.py
```

Paste the whole thing:

```python
"""Weather MCP server, hosted on AgentCore Runtime."""

import httpx
from mcp.server.fastmcp import FastMCP

import mcp_settings

BASE_URL = "https://api.openweathermap.org"

# AgentCore Runtime expects an MCP server on 0.0.0.0 port 8000, serving
# streamable-http at /mcp, and stateless. Stateless matters: Runtime handles
# session isolation itself, so the server must not hold per-user state.
mcp = FastMCP(host="0.0.0.0", port=8000, stateless_http=True)


def fetch_weather(city: str, units: str) -> dict:
    """Call OpenWeather and trim the response down to what a model needs."""
    response = httpx.get(
        f"{BASE_URL}/data/2.5/weather",
        params={
            "q": city,
            "units": units,
            "appid": mcp_settings.OPENWEATHER_API_KEY,
        },
        timeout=10.0,
    )

    if response.status_code == 404:
        raise ValueError(f"No weather data found for '{city}'. Check the spelling.")
    if response.status_code == 401:
        raise ValueError("The weather API key was rejected.")
    if response.status_code == 429:
        raise ValueError("Weather provider rate limit reached. Try again shortly.")
    response.raise_for_status()

    raw = response.json()
    return {
        "city": raw.get("name"),
        "country": raw.get("sys", {}).get("country"),
        "conditions": (raw.get("weather") or [{}])[0].get("description"),
        "temp": raw.get("main", {}).get("temp"),
        "feels_like": raw.get("main", {}).get("feels_like"),
        "humidity_pct": raw.get("main", {}).get("humidity"),
        "wind_speed": raw.get("wind", {}).get("speed"),
        "units": units,
    }


@mcp.tool()
def get_weather(city: str, units: str = "metric") -> dict:
    """Get the current weather for a city.

    Args:
        city: City name. Add a country code when the name is common,
              for example "Gurugram,IN" or "Austin,US".
        units: "metric" for Celsius, "imperial" for Fahrenheit.
    """
    return fetch_weather(city, units)


@mcp.tool()
def compare_cities(city_a: str, city_b: str, units: str = "metric") -> dict:
    """Compare the current weather in two cities in a single call.

    Use this instead of calling get_weather twice when the user asks which
    of two places is hotter, colder, or more humid.

    Args:
        city_a: First city name.
        city_b: Second city name.
        units: "metric" for Celsius, "imperial" for Fahrenheit.
    """
    first = fetch_weather(city_a, units)
    second = fetch_weather(city_b, units)

    warmer = first["city"] if first["temp"] >= second["temp"] else second["city"]
    difference = round(abs(first["temp"] - second["temp"]), 1)

    return {
        "cities": [first, second],
        "warmer": warmer,
        "temp_difference": difference,
        "units": units,
    }


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

Save and close.

### What to notice

**The docstrings become the tool descriptions.** Word for word. In Lab 1 those
descriptions came from the `description` fields in your YAML file. Here they
are in the code, next to the logic, and they change when you change the code.

**You control the response shape.** OpenWeather returns around forty fields.
The agent sees seven. Everything you drop is context budget and cost you get
back on every single call.

**You control the errors.** A 404 becomes a plain sentence the model can read
and relay. In Lab 1 the model gets whatever the API sends.

---

## Step 4. Create requirements.txt

```
notepad requirements.txt
```

```
mcp
httpx
```

Save and close.

**Watch out:** Notepad may save this as `requirements.txt.txt`. Check with:

```
dir requirements*
```

If you see the double extension, fix it:

```
ren requirements.txt.txt requirements.txt
```

---

## Step 5. Deploy the MCP server

Note the `--protocol MCP` flag. That is what tells Runtime this is a tool
server, not an agent.

```
agentcore configure --entrypoint weather_mcp.py --name lab3_weather_mcp --protocol MCP
```

Answer the prompts:
- Execution role: let it create one
- Requirements file: `requirements.txt`
- Authorization: **IAM**

Then:

```
agentcore launch
```

Takes 5 to 10 minutes the first time.

**Record the Agent Runtime ARN** from the output. It looks like:

```
arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/lab3_weather_mcp-XyZ123
```

If you miss it:

```
type .bedrock_agentcore.yaml
```

**Check it worked:** AWS Console → Bedrock AgentCore → Runtime →
`lab3_weather_mcp` shows status **Ready**.

### If deployment fails

| Message | Fix |
|---|---|
| `--protocol not recognised` | Run `agentcore configure --help`. Older toolkit versions use a different flag name. |
| Build fails on requirements | Check for `requirements.txt.txt` (Step 4) |
| Runtime starts then stops | Check logs: `aws logs tail "/aws/bedrock-agentcore/runtimes/YOUR_RUNTIME_ID-DEFAULT" --since 15m --region us-east-1` |
| `ModuleNotFoundError: mcp_settings` | The file was not uploaded. Confirm it sits next to `weather_mcp.py` in the same folder. |

---

## Step 6. Let the gateway call your server

Your gateway has its own IAM role from Lab 1. It cannot invoke Runtime yet.

1. AWS Console → **IAM** → **Roles**
2. Search `AgentCore`. Find the **gateway** role, not the runtime role. If you
   are unsure which is which, open your gateway in the AgentCore console — the
   detail page shows its service role.
3. **Add permissions** → **Create inline policy** → **JSON**
4. Delete what is there, paste this, replacing `YOUR_ACCOUNT_NUMBER`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "bedrock-agentcore:InvokeAgentRuntime",
      "Resource": "arn:aws:bedrock-agentcore:us-east-1:YOUR_ACCOUNT_NUMBER:runtime/*"
    }
  ]
}
```

5. Name it `lab3-invoke-runtime` → **Create policy**

**This step is the most common reason the next step silently fails.** The
target gets created, then syncs zero tools, with no obvious error.

---

## Step 7. Add the MCP server as a second gateway target

1. AWS Console → **Bedrock AgentCore** → **Gateways** → open `lab1-gateway`
2. **Targets** → **Add target**
3. Target name: `wxmcp`
4. Target type: **MCP server**
5. Endpoint: look for a picker that lists your AgentCore Runtime resources and
   select `lab3_weather_mcp`. If there is no picker, enter the URL manually:

```
https://bedrock-agentcore.us-east-1.amazonaws.com/runtimes/URL_ENCODED_ARN/invocations?qualifier=DEFAULT
```

To URL-encode the ARN, replace every `:` with `%3A` and every `/` with `%2F`.

6. Outbound authentication: **IAM** (the gateway's own role)
7. Listing mode: leave **Default**
8. **Add**

**Check it worked.** The gateway should now list three tools:

```
weather___getWeather
wxmcp___get_weather
wxmcp___compare_cities
```

### If the target syncs no tools

| Cause | How to tell | Fix |
|---|---|---|
| Missing IAM permission | Most likely cause | Redo Step 6, wait 30 seconds for IAM to propagate |
| Runtime not Ready | Console shows a different status | Wait, or check runtime logs |
| Wrong endpoint URL | Target shows a connection error | Use the picker rather than typing the URL |
| Server not stateless | Tools list intermittently | Confirm `stateless_http=True` in your code |

---

## Step 8. Confirm from your Lab 1 folder

Go back to your Lab 1 folder and run the checker you already have:

```
cd ..\agentcore-lab1
.venv\Scripts\activate
python check_gateway.py
```

Step 3 of that script should now print all three tools.

Nothing in `check_gateway.py` changed. Same gateway, same token, same Cognito
client. You added a whole new tool source and the client did not notice. That
is what the gateway layer is buying you.

---

## Step 9. Let the agent choose which target to use

With both targets live, the agent sees two tools that fetch weather. For now
you want to be able to switch between them deliberately.

Open `settings.py` in your Lab 1 folder and add one line:

```python
# "weather" = OpenAPI target only, "wxmcp" = your MCP server only, "all" = both
TOOL_FILTER = "all"
```

Then open `weather_agent.py` and find this line inside `main()`:

```python
        tools = gateway.list_tools_sync()
```

Replace it with these four lines. Match the indentation exactly — eight spaces
before `tools`:

```python
        tools = gateway.list_tools_sync()
        if settings.TOOL_FILTER != "all":
            prefix = settings.TOOL_FILTER + "___"
            tools = [t for t in tools if t.tool_name.startswith(prefix)]
```

Do the same inside `invoke()`, where the tools are passed to `build_agent`.

**If you get an IndentationError,** do not hunt for it. Clear the file and
paste the whole thing fresh, as you did in Lab 2.

---

## Step 10. Try it

```
python weather_agent.py --chat --session lab3-test
```

Ask these three:

```
What is the weather in Gurugram?
Which is hotter right now, Delhi or Mumbai?
What is the weather in Wakanda?
```

Watch which tool it picks each time. The second question is the interesting
one — with both targets available, does the agent use `compare_cities` in one
call, or call a weather tool twice?

Then switch targets and repeat. Set `TOOL_FILTER = "weather"` in `settings.py`,
run again, ask the same three. Then `TOOL_FILTER = "wxmcp"` and repeat.

**Write down what you see.** Especially for the Wakanda question — compare
what the model says when the error came from your server versus from the raw
API. That difference is the whole argument for a facade, and seeing it once is
worth more than reading about it.

---

## Step 11. Redeploy the agent (optional)

If you want the deployed agent to see the new tools too:

```
agentcore launch
```

Run this from the **Lab 1 folder**, not the Lab 3 folder. If you are ever
unsure which agent you are deploying:

```
agentcore status
```

---

## What you now have

One gateway. Two targets. Three tools. One Cognito client. One agent that
does not know or care where any of its tools come from.

Two things worth noting for the platform work:

**Adding a tool source did not change the consumer.** No agent code changed to
get the new tools. No new credentials. No new endpoint. If your seventy domain
teams each publish a target to the gateways their consumers already use, this
is the property that makes it scale.

**Your facade could do something the spec could not.** `compare_cities` makes
two API calls behind one tool. A generated OpenAPI target can only expose what
the API already exposes. When you decide how to present 1,000-plus APIs to
agents, that is the trade: specs are nearly free but literal, facades cost
engineering but let you design the tool the agent actually needs.

**Next — Lab 4:** run the same question set against each target and measure
tool selection accuracy, latency, and token cost. That turns everything you
just noticed into numbers you can take to an architecture review.
