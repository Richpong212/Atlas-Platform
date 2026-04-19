## What we’re adding

- production-ready `Dockerfile`
- `.dockerignore`
- non-root runtime user
- OCI metadata labels
- image tagging rules you can use locally and in CI

---

## Recommended structure

At the root of `atlas-api`:

```text
atlas-api/
├── Dockerfile
├── .dockerignore
├── package.json
├── package-lock.json
├── tsconfig.json
└── src/
```

---

## 1. Production-ready `Dockerfile`

Use this exact file:

```dockerfile
# syntax=docker/dockerfile:1

FROM node:22-alpine AS base
WORKDIR /app

FROM base AS deps
COPY package*.json ./
RUN npm ci

FROM deps AS build
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production

RUN addgroup -S nodejs && adduser -S atlas -G nodejs

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=build /app/dist ./dist

USER atlas

EXPOSE 3303

LABEL org.opencontainers.image.title="atlas-api" \
      org.opencontainers.image.description="Atlas Platform API service" \
      org.opencontainers.image.vendor="Codegenitor" \
      org.opencontainers.image.source="https://github.com/your-org/atlas-platform" \
      org.opencontainers.image.licenses="ISC"

CMD ["node", "dist/index.js"]
```

---

## Why this is production-grade

### Multi-stage build

We separate:

- dependency install
- build
- runtime

That keeps the final image cleaner.

### Non-root user

This line makes the container safer:

```dockerfile
USER atlas
```

So the app does not run as root inside the container.

### Production-only dependencies

This line is important:

```dockerfile
RUN npm ci --omit=dev
```

It keeps dev dependencies out of the final image.

### Smaller base image

`node:22-alpine` keeps the image lighter than a full Debian image.

---

## 2. `.dockerignore`

Use this exact file:

```gitignore
node_modules
dist
npm-debug.log
.git
.gitignore
Dockerfile
.dockerignore
README.md
.env
.env.*
coverage
.vscode
.idea
*.tsbuildinfo
```

---

## Why this matters

Without `.dockerignore`, Docker may send junk into the build context:

- local `node_modules`
- git history
- editor files
- `.env`

That makes builds slower, dirtier, and riskier.

---

## 3. Non-root user standard

You asked specifically for non-root user.

This is already handled here:

```dockerfile
RUN addgroup -S nodejs && adduser -S atlas -G nodejs
USER atlas
```

That means:

- create group `nodejs`
- create user `atlas`
- run app as `atlas`

That is the correct baseline standard for application containers.

---

## 4. Metadata labels

You asked for metadata labels.

These are OCI labels:

```dockerfile
LABEL org.opencontainers.image.title="atlas-api" \
      org.opencontainers.image.description="Atlas Platform API service" \
      org.opencontainers.image.vendor="Codegenitor" \
      org.opencontainers.image.source="https://github.com/your-org/atlas-platform" \
      org.opencontainers.image.licenses="ISC"
```

You can improve them later in CI by adding:

- revision / git SHA
- version
- created timestamp

Example CI-injected labels later:

```dockerfile
LABEL org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.revision=$GIT_SHA
```

For now, the static labels above are enough.

---

## 5. Image tagging rules

Do **not** rely only on `latest`.

Use a tagging standard like this:

### Local dev

```bash
docker build -t atlas-api:dev .
```

### Environment tag

```bash
docker tag atlas-api:dev 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:dev
```

### Commit SHA tag

```bash
docker tag atlas-api:dev 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:git-abc1234
```

### Latest tag

```bash
docker tag atlas-api:dev 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
```

---

## Recommended tagging policy

Use at least these tags on every CI build:

- `latest` → convenience only
- `git-<shortsha>` → immutable traceable tag
- optional environment tag like `dev`, `staging`, `prod`

### Example

```bash
docker build -t atlas-api:dev .

docker tag atlas-api:dev 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
docker tag atlas-api:dev 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:git-abc1234
docker tag atlas-api:dev 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:dev
```

Then push all:

```bash
docker push 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
docker push 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:git-abc1234
docker push 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:dev
```

---

## 6. Build command

From inside `atlas-api`:

```bash
docker build -t atlas-api:dev .
```

Run locally:

```bash
docker run --rm -p 3303:3303 atlas-api:dev
```

---

## 7. ECR push flow

Use the correct account you already confirmed:

```bash
aws ecr get-login-password --region us-east-1 \
| docker login \
  --username AWS \
  --password-stdin 307946673392.dkr.ecr.us-east-1.amazonaws.com

docker build -t atlas-api:dev .

docker tag atlas-api:dev 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
docker tag atlas-api:dev 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:dev

docker push 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:latest
docker push 307946673392.dkr.ecr.us-east-1.amazonaws.com/atlas-dev-api:dev
```

---

## 8. Small improvement to your package.json

Since your app entry is `dist/index.js`, make this cleaner:

```json
"main": "dist/index.js"
```

And ideally add:

```json
"scripts": {
  "build": "tsc",
  "start": "node dist/index.js"
}
```

You already mostly have that.

---

## 9. Phase 4 done checklist

You are done with Phase 4 when:

- `Dockerfile` exists
- `.dockerignore` exists
- container runs as non-root
- image has OCI labels
- you stop using only `latest`
- image builds and runs locally
- image pushes to ECR successfully

---

## Final files

### `Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1

FROM node:22-alpine AS base
WORKDIR /app

FROM base AS deps
COPY package*.json ./
RUN npm ci

FROM deps AS build
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production

RUN addgroup -S nodejs && adduser -S atlas -G nodejs

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=build /app/dist ./dist

USER atlas

EXPOSE 3303

LABEL org.opencontainers.image.title="atlas-api" \
      org.opencontainers.image.description="Atlas Platform API service" \
      org.opencontainers.image.vendor="Codegenitor" \
      org.opencontainers.image.source="https://github.com/your-org/atlas-platform" \
      org.opencontainers.image.licenses="ISC"

CMD ["node", "dist/index.js"]
```

### `.dockerignore`

```gitignore
node_modules
dist
npm-debug.log
.git
.gitignore
Dockerfile
.dockerignore
README.md
.env
.env.*
coverage
.vscode
.idea
*.tsbuildinfo
```

### create both quickly

```bash
touch Dockerfile .dockerignore
```
