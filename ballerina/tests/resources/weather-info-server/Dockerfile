FROM node:18-alpine

WORKDIR /app

# Copy package files and install dependencies
COPY package.json tsconfig.json ./
RUN npm install

# Copy source and build
COPY src/ ./src/
RUN npm run build

EXPOSE 3000
CMD ["npm", "start"]
