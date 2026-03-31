# =============================================================================
# h4kscape-client — Static web client served by nginx
# Multi-stage: build client.js, then serve from nginx
# =============================================================================

FROM node:22-bookworm AS build

RUN apt-get update && apt-get install -y --no-install-recommends python3 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# Build arguments (override at build time for different server targets)
ARG SERVER_URL=https://scape.t3ks.com
ARG OAUTH_ENABLED=true
ARG OAUTH_LOGTO_ENDPOINT=https://auth.h4ks.com
ARG OAUTH_APP_ID=bc40c9vfeg5i43m9j8bws
ARG OAUTH_CALLBACK_URL=https://scape.h4ks.com/auth-callback.html
ARG NODE_ID=10
ARG LOWMEM=0
ARG MEMBERS=true

ENV SERVER_URL=$SERVER_URL \
    OAUTH_ENABLED=$OAUTH_ENABLED \
    OAUTH_LOGTO_ENDPOINT=$OAUTH_LOGTO_ENDPOINT \
    OAUTH_APP_ID=$OAUTH_APP_ID \
    OAUTH_CALLBACK_URL=$OAUTH_CALLBACK_URL \
    NODE_ID=$NODE_ID \
    LOWMEM=$LOWMEM \
    MEMBERS=$MEMBERS

RUN bash build-client.sh

# ── Serve with nginx ─────────────────────────────────────────
FROM nginx:alpine

COPY --from=build /build/dist/ /usr/share/nginx/html/

# SPA-friendly nginx config: serve index.html for unknown routes
RUN printf 'server {\n\
    listen 80;\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
    location ~* \\.(js|wasm|sf2|ico)$ {\n\
        expires 1y;\n\
        add_header Cache-Control "public, immutable";\n\
    }\n\
}\n' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
