# Use official Node.js image as base
FROM node:20-alpine

# Set working directory
WORKDIR /app


# Copy package.json and install dependencies
COPY package.json package-lock.json* ./
RUN npm install --omit-dev
RUN npm i pg -g


# Copy the server code
COPY ./socket.io/ ./socket.io/
# Copy the build .env file and load its variables
COPY .env.build2 ./.env

# Expose port 3001
EXPOSE 3001

# Start the server
CMD ["node", "socket.io/server.mjs"]