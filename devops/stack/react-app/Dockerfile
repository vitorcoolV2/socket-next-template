# Use official Node.js image as base
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package.json and install dependencies
COPY package.json package-lock.json* ./
RUN npm install --prodution


# Copy all source and configuration files
COPY src/ src/
COPY public/ public/
COPY next.config.mjs ./  
COPY postcss.config.mjs tailwind.config.js* ./  
COPY tsconfig.json ./  

# Copy the build .env file and load its variables
COPY .env.build ./.env

# Build the Next.js app for production
# ONE LINE – loads .env AND makes the variable available to Next.js
RUN set -a && \
    . ./.env && \
    set +a && \
    npm run build                           

# Expose port 3000
EXPOSE 3000


CMD ["npm","start"]