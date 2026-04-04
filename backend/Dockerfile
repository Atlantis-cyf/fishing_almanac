# Railway: use Docker builder so monorepo root (Flutter + Node) does not confuse Railpack.
FROM node:20-alpine
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY . .

ENV NODE_ENV=production
# Railway injects PORT; server.js uses process.env.PORT || 8080
EXPOSE 8080

CMD ["node", "server.js"]
