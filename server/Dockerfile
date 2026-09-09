FROM node:24-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY src ./src
RUN mkdir /app/data && chown node:node /app/data
USER node
ENV PORT=8080 DATABASE_PATH=/app/data/relay.sqlite
EXPOSE 8080
CMD ["node", "src/main.mjs"]
