# h4kscape-client

Web client for h4kscape (RuneScape 2 / 2004Scape). Builds to a static site
that connects to a remote game server.

Forked from [2004scape/Client2](https://github.com/2004scape/Client2) (Lost City).

The game server lives in a separate repository:
[h4ks-com/h4kscape-server](https://github.com/h4ks-com/h4kscape-server)

## Architecture

- **Client** (this repo) → static HTML/JS/WASM served at `scape.h4ks.com`
- **Server** (h4kscape-server) → game logic + data at `scape.t3ks.com`

The client fetches game data (cache files) over HTTP and connects via
WebSocket, both to the server. CORS on the server allows cross-origin
requests from the client domain.

## Building

```bash
npm install

# Build with defaults (server at scape.t3ks.com)
bash build-client.sh

# Build with custom server
SERVER_URL=https://myserver.example.com bash build-client.sh
```

Output goes to `dist/`. Serve it with any static file server.

### Environment Variables

| Variable | Default | Description |
|----------------------|--------------------------------------|--------------------------------------|
| `SERVER_URL` | `https://scape.t3ks.com` | Game server URL |
| `OAUTH_ENABLED` | `true` | Enable OAuth login |
| `OAUTH_LOGTO_ENDPOINT` | `https://auth.h4ks.com` | Logto auth endpoint |
| `OAUTH_APP_ID` | `bc40c9vfeg5i43m9j8bws` | Logto application ID |
| `OAUTH_CALLBACK_URL` | `https://scape.h4ks.com/auth-callback.html` | OAuth redirect URL |
| `NODE_ID` | `10` | World/node ID |
| `MEMBERS` | `true` | Members world |

## Docker

```bash
docker build -t h4kscape-client .
docker run -d -p 80:80 h4kscape-client
```

Override the server target at build time:

```bash
docker build \
  --build-arg SERVER_URL=https://myserver.example.com \
  -t h4kscape-client .
```

## CI/CD

The GitHub Actions workflow builds and pushes to Docker Hub on every push to
`main`. Requires a `DOCKERHUB_TOKEN` repository secret for the `mattfly` account.

## License

MIT — see [LICENSE](LICENSE). Originally by [Lost City / 2004scape](https://github.com/2004scape).
