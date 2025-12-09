FROM node:18

WORKDIR /app

# Copy package files
COPY package.json ./

# Install dependencies
RUN npm install

# Copy application
COPY public ./public
COPY src ./src

EXPOSE 3000

CMD ["npm", "start"]
