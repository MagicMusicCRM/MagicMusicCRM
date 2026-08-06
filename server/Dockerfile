FROM node:24.11.0-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM deps AS build
COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src ./src
RUN npm run build
RUN npm prune --omit=dev

FROM node:24.11.0-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

RUN apk upgrade --no-cache \
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx \
  && addgroup -g 10001 -S magiccrm \
  && adduser -u 10001 -S magiccrm -G magiccrm \
  && mkdir -p /opt/magicmusiccrm/storage/private \
  && chown -R magiccrm:magiccrm /opt/magicmusiccrm/storage

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json package-lock.json ./
COPY db/migrations ./db/migrations

USER magiccrm
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/health >/dev/null || exit 1

CMD ["node", "dist/main.js"]
