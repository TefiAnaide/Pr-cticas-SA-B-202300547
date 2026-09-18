# ---- Stage "dev": usada por docker-compose (hot-reload con nodemon) ----
FROM node:22-alpine AS dev
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
EXPOSE 8080
CMD ["npm", "run", "dev"]

# ---- Stage "deps": solo dependencias de produccion ----
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# ---- Stage "runtime": imagen final para Kubernetes (target por defecto) ----
FROM node:22-alpine AS runtime
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
# npm viene con una version vendored de "tar" vulnerable (CVE-2026-59873);
# npm no se usa en runtime (CMD llama a node directo), asi que se elimina.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
COPY --from=deps /app/node_modules ./node_modules
COPY package*.json ./
COPY src ./src
USER app
EXPOSE 8080
CMD ["node", "src/server.js"]
