# configuration.py
from pydantic_settings import BaseSettings


class Configuration(BaseSettings):
    """Agent configuration loaded from environment variables."""

    # LLM connection settings (compatible with Ollama / OpenAI-compatible endpoints)
    llm_model: str = "ibm/granite4:3b"
    llm_api_base: str = "http://host.docker.internal:11434/v1"
    llm_api_key: str = "dummy"

    # Server binding
    host: str = "0.0.0.0"
    port: int = 8000

    # Optional public endpoint override for the AgentCard URL
    agent_endpoint: str = ""
