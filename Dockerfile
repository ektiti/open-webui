# syntax=docker/dockerfile:1
# 1
######## WebUI frontend ########
FROM --platform=$BUILDPLATFORM node:22-alpine3.20 AS build

WORKDIR /app
RUN apk add --no-cache git
COPY package.json package-lock.json ./
RUN npm ci --force
COPY . .
RUN npm run build

######## WebUI backend ########
FROM python:3.11.14-slim-bookworm AS base

ARG UID=0
ARG GID=0

ENV PYTHONUNBUFFERED=1
ENV ENV=prod
ENV PORT=8080
ENV OLLAMA_BASE_URL=""
ENV OPENAI_API_BASE_URL=""
ENV OPENAI_API_KEY=""
ENV WEBUI_SECRET_KEY=""
ENV SCARF_NO_ANALYTICS=true
ENV DO_NOT_TRACK=true
ENV ANONYMIZED_TELEMETRY=false

WORKDIR /app/backend
ENV HOME=/root

RUN if [ $UID -ne 0 ]; then \
    if [ $GID -ne 0 ]; then addgroup --gid $GID app; fi; \
    adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

RUN mkdir -p $HOME/.cache/chroma
RUN echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id
RUN chown -R $UID:$GID /app $HOME

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git build-essential pandoc gcc netcat-openbsd curl jq \
    libmariadb-dev python3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt

RUN set -e; \
    pip3 install --no-cache-dir uv; \
    pip3 install 'torch<=2.9.1' --index-url https://download.pytorch.org/whl/cpu --no-cache-dir; \
    uv pip install --system -r requirements.txt --no-cache-dir; \
    mkdir -p /app/backend/data; chown -R $UID:$GID /app/backend/data/; \
    rm -rf /var/lib/apt/lists/*

COPY --chown=$UID:$GID --from=build /app/build /app/build
COPY --chown=$UID:$GID --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=build /app/package.json /app/package.json
COPY --chown=$UID:$GID ./backend .

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT:-8080}/health | jq -ne 'input.status == true' || exit 1

USER $UID:$GID
ENV WEBUI_BUILD_VERSION=slim-chat
ENV DOCKER=true

CMD ["bash", "start.sh"]
