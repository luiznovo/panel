# Script para testar e resolver problemas do Docker no Windows

Write-Host "=== TESTE DE CONFIGURAÇÃO DOCKER ===" -ForegroundColor Cyan

# Verificar se Docker está rodando
Write-Host "1. Verificando Docker..." -ForegroundColor Yellow
try {
    docker --version
    Write-Host "✅ Docker está funcionando" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker não está instalado ou não está rodando" -ForegroundColor Red
    exit 1
}

# Verificar se Docker Compose está disponível
Write-Host "2. Verificando Docker Compose..." -ForegroundColor Yellow
try {
    docker compose version
    Write-Host "✅ Docker Compose está funcionando" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker Compose não está disponível" -ForegroundColor Red
    exit 1
}

# Verificar estrutura de arquivos
Write-Host "3. Verificando estrutura de arquivos..." -ForegroundColor Yellow
$filesToCheck = @(
    "Dockerfile",
    "docker-compose.yml",
    "package.json",
    "index.js",
    ".env",
    "nginx\nginx.conf",
    "nginx\sites\gpanel.conf"
)

foreach ($file in $filesToCheck) {
    if (Test-Path $file) {
        Write-Host "✅ $file existe" -ForegroundColor Green
    } else {
        Write-Host "❌ $file não encontrado" -ForegroundColor Red
    }
}

# Verificar diretórios
Write-Host "4. Verificando diretórios..." -ForegroundColor Yellow
$dirsToCheck = @(
    "nginx",
    "nginx\sites",
    "nginx\ssl",
    "data",
    "logs",
    "uploads"
)

foreach ($dir in $dirsToCheck) {
    if (Test-Path $dir -PathType Container) {
        Write-Host "✅ Diretório $dir existe" -ForegroundColor Green
    } else {
        Write-Host "❌ Diretório $dir não encontrado" -ForegroundColor Red
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "✅ Diretório $dir criado" -ForegroundColor Green
    }
}

# Limpar containers e imagens antigas
Write-Host "5. Limpando containers antigos..." -ForegroundColor Yellow
docker compose down --remove-orphans 2>$null
docker system prune -f

# Tentar build
Write-Host "6. Tentando build..." -ForegroundColor Yellow
try {
    docker compose build --no-cache
    Write-Host "✅ Build realizado com sucesso" -ForegroundColor Green
} catch {
    Write-Host "❌ Erro no build" -ForegroundColor Red
    exit 1
}

# Tentar iniciar
Write-Host "7. Tentando iniciar containers..." -ForegroundColor Yellow
try {
    docker compose up -d
    Write-Host "✅ Containers iniciados com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "❌ Erro ao iniciar containers" -ForegroundColor Red
    Write-Host "Logs do erro:" -ForegroundColor Yellow
    docker compose logs
    exit 1
}

Write-Host "8. Status dos containers:" -ForegroundColor Yellow
docker compose ps

Write-Host "9. Logs dos containers:" -ForegroundColor Yellow
docker compose logs --tail=20

Write-Host "=== TESTE CONCLUÍDO ===" -ForegroundColor Cyan
Write-Host "Acesse http://localhost:8080 para testar o painel" -ForegroundColor Green
Write-Host "Porta 8080 (HTTP) e 8443 (HTTPS) estão sendo usadas para evitar conflitos" -ForegroundColor Yellow