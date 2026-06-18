FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ARG RELEASE_VERSION="main"

WORKDIR /app

# Copy project files
COPY pyproject.toml .
COPY src/ src/

# Install dependencies (uv creates a virtual environment automatically)
RUN uv sync --no-cache --locked --link-mode copy || uv sync --no-cache --link-mode copy

ENV PRODUCTION_MODE=True \
    RELEASE_VERSION=${RELEASE_VERSION} \
    HOST=0.0.0.0 \
    PORT=8000 \
    UV_CACHE_DIR=/app/.cache/uv

# Run as non-root (chown ensures /app/.cache/uv is writable)
RUN mkdir -p /app/.cache/uv && chown -R 1001:1001 /app
USER 1001

EXPOSE 8000

CMD ["uv", "run", "--no-sync", "server"]
