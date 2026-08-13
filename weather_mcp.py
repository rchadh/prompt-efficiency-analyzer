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