FROM node:22-alpine

WORKDIR /app

# Install Truffle globally
RUN npm install -g truffle@5.11.5

# Install netcat for the wait-for-ganache loop
RUN apk add --no-cache netcat-openbsd

# Copy project files
COPY contracts/ ./contracts/
COPY migrations/ ./migrations/
COPY truffle-config.js ./
COPY deploy.sh ./deploy.sh
RUN chmod +x ./deploy.sh

CMD ["/bin/sh", "./deploy.sh"]
