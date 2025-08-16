# Multi-stage build para otimização
FROM node:18-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Estágio de produção
FROM node:18-alpine AS production

RUN addgroup -g 1001 -S nodejs
RUN adduser -S gpanel -u 1001

WORKDIR /app

# Copiar dependências do builder
COPY --from=builder /app/node_modules ./node_modules
COPY --chown=gpanel:nodejs . .

# Criar diretórios necessários
RUN mkdir -p data logs uploads && chown -R gpanel:nodejs data logs uploads

USER gpanel

EXPOSE 3000

CMD ["node", "index.js"]