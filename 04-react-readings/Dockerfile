# Stage 1: build the static assets. This stage's own image is discarded
# after the build — only the dist/ output crosses into Stage 2.
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: the actual runtime image — nginx only, no Node, no source code,
# no node_modules. Meaningfully smaller and a smaller attack surface than
# shipping the build tooling itself.
FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 80
