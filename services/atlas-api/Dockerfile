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

FROM node:22-alpine AS prod-deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM gcr.io/distroless/nodejs22-debian13:nonroot AS runtime
WORKDIR /app

ENV NODE_ENV=production

COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

EXPOSE 3303

LABEL org.opencontainers.image.title="atlas-api" \
      org.opencontainers.image.description="Atlas Platform API service" \
      org.opencontainers.image.vendor="Codegenitor" \
      org.opencontainers.image.source="https://github.com/your-org/atlas-platform" \
      org.opencontainers.image.licenses="ISC"

CMD ["dist/index.js"]