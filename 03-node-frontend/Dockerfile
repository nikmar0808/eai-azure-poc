FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev \
    && rm -rf /usr/local/lib/node_modules/npm \
              /usr/local/bin/npm \
              /usr/local/bin/npx
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
