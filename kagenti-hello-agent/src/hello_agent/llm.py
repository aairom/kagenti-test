# llm.py
import logging
from collections import defaultdict

from openai import AsyncOpenAI

from hello_agent.configuration import Configuration

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    "You are a friendly and concise greeting assistant. "
    "Your purpose is to greet users warmly and provide short, helpful responses. "
    "Guidelines:\n"
    "- Always start with a personalised greeting.\n"
    "- Ask the user's name if you don't know it yet.\n"
    "- Be brief: keep every response under 3 sentences.\n"
    "- If asked about your capabilities, explain you are a greeting agent running on Kagenti.\n"
    "- Always end with an encouraging or friendly closing.\n"
)

# In-memory conversation history keyed by context_id.
# NOTE: In production, replace with a persistent store.
_conversations: dict[str, list[dict[str, str]]] = defaultdict(list)


async def chat(context_id: str, user_message: str) -> str:
    """Send a user message and get a response, preserving per-context history."""
    config = Configuration()

    client = AsyncOpenAI(
        base_url=config.llm_api_base,
        api_key=config.llm_api_key,
    )

    history = _conversations[context_id]
    history.append({"role": "user", "content": user_message})

    messages = [{"role": "system", "content": SYSTEM_PROMPT}] + history

    logger.info(
        "Sending %d messages to LLM (context=%s, model=%s)",
        len(messages),
        context_id,
        config.llm_model,
    )

    response = await client.chat.completions.create(
        model=config.llm_model,
        messages=messages,
    )

    reply = response.choices[0].message.content
    history.append({"role": "assistant", "content": reply})

    logger.info("LLM reply (context=%s): %s", context_id, reply[:200])
    return reply
