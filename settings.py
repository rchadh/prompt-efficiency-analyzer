GATEWAY_URL   = "https://lab1-gateway-imupjiqpny.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp"
TOKEN_URL     = "https://my-domain-bm4qo1oz.auth.us-east-1.amazoncognito.com/oauth2/token"
CLIENT_ID     = "1q50j5r649rrq4i3ccq7dvta1i"
CLIENT_SECRET = "1j78lrfkmtchkjjbvplklkki2pfclge9cgdjlcajlaftr9i2v5im"
SCOPE         = "lab1-gateway/genesis-gateway:invoke"
MEMORY_ID = "lab2_memory-vUJ9Bt2NMA"


REGION   = "us-east-1"
MODEL_ID = "openai.gpt-oss-120b-1:0"

import boto3, json

REGION = "us-east-1"          # change to your region
GATEWAY_ID = "your-gateway-id"  # from your Terraform output

ctrl = boto3.client("bedrock-agentcore-control", region_name=REGION)

resp = ctrl.get_gateway(gatewayIdentifier=GATEWAY_ID)
print(json.dumps(resp, indent=2, default=str))

-----------------------------------------------

# step2c_connect_none.py
import asyncio
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

GATEWAY_URL = "https://<your-gateway-id>.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp"

async def main():
    async with streamablehttp_client(GATEWAY_URL) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            for t in tools.tools:
                print(t.name)

asyncio.run(main())
