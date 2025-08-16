#!/bin/bash

# Script para testar e resolver problemas do Docker

echo "=== TESTE DE CONFIGURAÇÃO DOCKER ==="

# Verificar se Docker está rodando
echo "1. Verificando Docker..."
docker --version
if [ $? -ne 0 ]; then
    echo "❌ Docker não está instalado ou não está rodando"
    exit 1
fi

# Verificar se Docker Compose está disponível
echo "2. Verificando Docker Compose..."
docker compose version
if [ $? -ne 0 ]; then
    echo "❌ Docker Compose não está disponível"
    exit 1
fi

# Verificar estrutura de arquivos
echo "3. Verificando estrutura de arquivos..."
files_to_check=(
    "Dockerfile"
    "docker-compose.yml"
    "package.json"
    "index.js"
    ".env"
    "nginx/nginx.conf"
    "nginx/sites/gpanel.conf"
)

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file existe"
    else
        echo "❌ $file não encontrado"
    fi
done

# Verificar diretórios
echo "4. Verificando diretórios..."
dirs_to_check=(
    "nginx"
    "nginx/sites"
    "nginx/ssl"
    "data"
    "logs"
    "uploads"
)

for dir in "${dirs_to_check[@]}"; do
    if [ -d "$dir" ]; then
        echo "✅ Diretório $dir existe"
    else
        echo "❌ Diretório $dir não encontrado"
        mkdir -p "$dir"
        echo "✅ Diretório $dir criado"
    fi
done

# Limpar containers e imagens antigas
echo "5. Limpando containers antigos..."
docker compose down --remove-orphans 2>/dev/null
docker system prune -f

# Tentar build
echo "6. Tentando build..."
docker compose build --no-cache
if [ $? -ne 0 ]; then
    echo "❌ Erro no build"
    exit 1
fi

# Tentar iniciar
echo "7. Tentando iniciar containers..."
docker compose up -d
if [ $? -ne 0 ]; then
    echo "❌ Erro ao iniciar containers"
    echo "Logs do erro:"
    docker compose logs
    exit 1
fi

echo "✅ Containers iniciados com sucesso!"
echo "8. Status dos containers:"
docker compose ps

echo "9. Logs dos containers:"
docker compose logs --tail=20

echo "=== TESTE CONCLUÍDO ==="