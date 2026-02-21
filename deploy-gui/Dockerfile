FROM node:22-alpine

# Install ssh client and shell tools
RUN apk add --no-cache openssh-client bash curl jq

WORKDIR /app

COPY package.json .
RUN npm install --production

COPY deploy-gui.js .

# Data volume for persisted settings
VOLUME ["/data"]

ENV DEPLOY_GUI_PORT=9999 \
    DATA_DIR=/data \
    NODE_ENV=production

EXPOSE 9999

# Run as a non-root user for security
RUN addgroup -S deployer && adduser -S deployer -G deployer
RUN mkdir -p /data /home/deployer/.ssh && chown -R deployer:deployer /data /home/deployer/.ssh
USER deployer

CMD ["node", "deploy-gui.js"]
