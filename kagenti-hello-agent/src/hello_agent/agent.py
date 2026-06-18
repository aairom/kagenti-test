"""
Hello Kagenti Agent  —  A simple A2A greeting agent.

Implements the Google A2A protocol (JSON-RPC over HTTP) so it can be
discovered and orchestrated by the Kagenti platform.
"""
import logging
import os
from textwrap import dedent

import uvicorn
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from a2a.helpers import (
    new_task_from_user_message,
    new_text_message,
    new_text_part,
)
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events.event_queue import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import (
    create_agent_card_routes,
    create_jsonrpc_routes,
)
from a2a.server.tasks import InMemoryTaskStore, TaskUpdater
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
    TaskState,
)
from hello_agent.llm import chat

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Agent Card
# ---------------------------------------------------------------------------

def get_agent_card(host: str, port: int) -> AgentCard:
    """Build and return the A2A AgentCard for this agent."""
    skill = AgentSkill(
        id="greeting",
        name="Greeting Skill",
        description="Greets the user by name and carries on a short friendly conversation.",
        tags=["greeting", "hello", "welcome", "demo"],
        examples=[
            "Hello!",
            "What is your name?",
            "Tell me about yourself",
            "Hi, I'm Alice",
        ],
    )

    endpoint = os.getenv(
        "AGENT_ENDPOINT", f"http://{host}:{port}"
    ).rstrip("/") + "/"

    return AgentCard(
        name="Hello Kagenti Agent",
        description=dedent(
            """\
            A simple greeting agent deployed on the Kagenti platform.

            ## What I can do
            - Greet you warmly by name
            - Hold a short friendly conversation
            - Demonstrate the Kagenti A2A protocol in action
            """
        ),
        version="1.0.0",
        default_input_modes=["text"],
        default_output_modes=["text"],
        capabilities=AgentCapabilities(streaming=False),
        skills=[skill],
        supported_interfaces=[
            AgentInterface(
                url=endpoint,
                protocol_binding="JSONRPC",
            )
        ],
    )


# ---------------------------------------------------------------------------
# Agent Executor
# ---------------------------------------------------------------------------

class HelloExecutor(AgentExecutor):
    """Handles A2A task execution for the Hello Kagenti Agent."""

    async def execute(
        self, context: RequestContext, event_queue: EventQueue
    ) -> None:
        task = context.current_task
        if not task:
            task = new_task_from_user_message(context.message)
            await event_queue.enqueue_event(task)

        updater = TaskUpdater(event_queue, task.id, task.context_id)

        user_input = context.get_user_input()
        logger.info(
            "Hello agent received: %r (context=%s)", user_input, task.context_id
        )

        await updater.update_status(
            TaskState.TASK_STATE_WORKING,
            new_text_message(
                "Thinking of the best way to say hello…",
                context_id=updater.context_id,
                task_id=updater.task_id,
            ),
        )

        try:
            reply = await chat(task.context_id, user_input)

            await updater.add_artifact([new_text_part(reply)])
            await updater.update_status(
                TaskState.TASK_STATE_INPUT_REQUIRED,
                new_text_message(
                    reply,
                    context_id=updater.context_id,
                    task_id=updater.task_id,
                ),
            )
        except Exception as exc:
            logger.exception("Hello agent execution error: %s", exc)
            await updater.add_artifact(
                [new_text_part("Sorry, something went wrong. Please try again.")]
            )
            await updater.failed()

    async def cancel(
        self, context: RequestContext, event_queue: EventQueue
    ) -> None:
        raise NotImplementedError("cancel is not supported")


# ---------------------------------------------------------------------------
# Health endpoint
# ---------------------------------------------------------------------------

async def health(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})


async def healthcheck(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})


# ---------------------------------------------------------------------------
# Entry-point
# ---------------------------------------------------------------------------

def run() -> None:
    """Start the A2A agent HTTP server."""
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))

    agent_card = get_agent_card(host, port)

    handler = DefaultRequestHandler(
        agent_executor=HelloExecutor(),
        task_store=InMemoryTaskStore(),
        agent_card=agent_card,
    )

    routes = [
        Route("/health", health, methods=["GET"]),
        Route("/healthcheck", healthcheck, methods=["GET"]),
    ]
    routes.extend(create_agent_card_routes(agent_card))
    # enable_v0_3_compat is required because Kagenti uses A2A 0.3 client libraries
    routes.extend(create_jsonrpc_routes(handler, "/", enable_v0_3_compat=True))

    app = Starlette(routes=routes)
    uvicorn.run(app, host=host, port=port)
