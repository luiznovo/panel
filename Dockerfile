# Multi-stage build para otimização de produção
# Stage 1: Build dependencies
FROM node:18-alpine AS builder

# Instalar dependências do sistema
RUN apk add --no-cache python3 make g++ sqlite

# Criar diretório de trabalho
WORKDIR /app

# Copiar arquivos de dependências
COPY package*.json ./

# Instalar dependências
RUN npm ci --only=production && npm cache clean --force

# Stage 2: Production image
FROM node:18-alpine AS production

# Instalar dependências do sistema necessárias
RUN apk add --no-cache \
    sqlite \
    dumb-init \
    curl \
    && addgroup -g 1001 -S nodejs \
    && adduser -S nodejs -u 1001

# Criar diretórios necessários
WORKDIR /app
RUN mkdir -p /app/data /app/logs /app/backups && \
    chown -R nodejs:nodejs /app

# Copiar node_modules do stage builder
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copiar código da aplicação
COPY --chown=nodejs:nodejs . .

# Remover arquivos desnecessários
RUN rm -rf .git .gitignore README.md *.md docker-compose*.yml Dockerfile* \
    && find . -name "*.log" -delete \
    && find . -name "*.tmp" -delete

# Criar arquivo de versão
RUN echo "$(date '+%Y-%m-%d %H:%M:%S') - $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" > /app/VERSION

# Configurar usuário não-root
USER nodejs

# Expor porta
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Usar dumb-init para gerenciamento de processos
ENTRYPOINT ["dumb-init", "--"]

# Comando padrão
CMD ["node", "index.js"]