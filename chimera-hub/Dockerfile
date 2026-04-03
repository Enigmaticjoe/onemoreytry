FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache curl

COPY chimera-hub/package.json ./
RUN npm install --omit=dev

COPY chimera-hub/healthcheck.sh /app/healthcheck.sh
RUN chmod +x /app/healthcheck.sh

COPY chimera-hub/server.js /app/server.js

RUN mkdir -p /app/data
COPY config/node-inventory.env.example /app/data/node-inventory.env
COPY kvm-operator/policy_denylist.txt /app/data/policy_denylist.txt

EXPOSE 3099

CMD ["node", "server.js"]
