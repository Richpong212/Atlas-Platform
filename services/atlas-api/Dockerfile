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