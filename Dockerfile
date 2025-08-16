# Multi-stage build para otimização
FROM node:20-bookworm AS builder

# Instalar dependências necessárias para compilação
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package*.json ./
# Instalar dependências e recompilar better-sqlite3
RUN npm ci --only=production && npm rebuild better-sqlite3

# Estágio de produção
FROM node:20-bookworm AS production

# Instalar dependências de runtime
RUN apt-get update && apt-get install -y \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1001 nodejs
RUN useradd -r -u 1001 -g nodejs gpanel

WORKDIR /app

# Copiar dependências do builder
COPY --from=builder /app/node_modules ./node_modules
COPY --chown=gpanel:nodejs . .

# Recompilar better-sqlite3 no ambiente de produção
RUN npm rebuild better-sqlite3

# Criar diretórios necessários
RUN mkdir -p data logs uploads && chown -R gpanel:nodejs data logs uploads

USER gpanel

EXPOSE 3000

CMD ["node", "index.js"]