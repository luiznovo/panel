# 🔒 Correções de Segurança Implementadas

Este documento descreve todas as vulnerabilidades corrigidas e melhorias de segurança implementadas no painel.

## 📋 Vulnerabilidades Corrigidas

### 1. ✅ Mudança de Plano Sem Pagamento
**Status:** CORRIGIDO  
**Localização:** `routes/api.js` linha 827  
**Correção:** Bloqueio de mudança de plano para usuários gratuitos com mensagem de manutenção.

```javascript
// Verificação adicionada
if (user.plan === 'Gratuito' && plan !== 'Gratuito') {
    return res.status(503).json({
        success: false,
        error: 'Sistema de upgrade de planos em manutenção'
    });
}
```

### 2. ✅ Proteção CSRF
**Status:** IMPLEMENTADO  
**Localização:** `index.js`  
**Correção:** Middleware CSRF com exceções para APIs e WebSockets.

```javascript
// Token CSRF disponível em todas as views
res.locals.csrfToken = req.csrfToken();
```

**Como usar em formulários:**
```html
<%- include('partials/csrf-token') %>
```

### 3. ✅ Validação de API Key Melhorada
**Status:** IMPLEMENTADO  
**Localização:** `routes/api.js`  
**Melhorias:**
- Hash das API keys com bcrypt
- Rate limiting (10 tentativas por 15 min)
- Logs de auditoria completos
- Verificação de expiração e status
- Rastreamento de uso

### 4. ✅ Rate Limiting Abrangente
**Status:** IMPLEMENTADO  
**Localização:** `index.js`  
**Configuração:**
- Geral: 100 req/15min por IP
- Autenticação: 5 tentativas/15min
- APIs: 30 req/min
- Exceção para comunicação Wings

### 5. ✅ Logs de Auditoria Melhorados
**Status:** IMPLEMENTADO  
**Localização:** `handlers/auditlog.js`  
**Recursos:**
- Logs em arquivo e banco de dados
- Classificação por severidade
- Alertas para ações críticas
- Limpeza automática (90 dias)
- Filtros de busca

### 6. ✅ Sanitização de Erros
**Status:** IMPLEMENTADO  
**Localização:** `routes/api.js`, `utils/securityMiddleware.js`  
**Correção:** Mensagens de erro sanitizadas em produção.

### 7. ✅ Controle de Acesso Centralizado
**Status:** IMPLEMENTADO  
**Localização:** `utils/securityMiddleware.js`  
**Recursos:**
- Middleware centralizado de autenticação
- Logs automáticos de tentativas de acesso
- Verificação de privilégios melhorada

## 🛠️ Novos Recursos de Segurança

### Middleware de Segurança
```javascript
const { isAuthenticated, isAdmin, logSensitiveAction } = require('./utils/securityMiddleware');

// Uso em rotas
router.post('/sensitive-action', isAdmin, logSensitiveAction('action_name'), handler);
```

### Sistema de Auditoria
```javascript
const { logAudit } = require('./handlers/auditlog');

// Log de ação
logAudit(userId, username, 'action:type', ipAddress, metadata);

// Buscar logs
const logs = await getAuditLogs({
    userId: 'user123',
    action: 'login',
    severity: 'critical',
    startDate: '2024-01-01',
    limit: 50
});
```

### Migração de API Keys
```bash
# Executar migração uma vez
node utils/migrateApiKeys.js
```

```javascript
// Criar nova API key hasheada
const { createHashedApiKey } = require('./utils/migrateApiKeys');
const newKey = await createHashedApiKey('Nome da Key', userId, expiresAt);
console.log('Nova key:', newKey.plainKey); // Mostrar apenas uma vez
```

## 🔧 Configurações de Segurança

### Variáveis de Ambiente
```env
NODE_ENV=production  # Para sanitização de erros
```

### Rate Limiting
```javascript
// Configurações personalizáveis em index.js
const generalRateLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutos
    max: 100, // máximo de requests
    skip: (req) => {
        // Lógica para pular rate limiting
        return req.headers['user-agent']?.includes('axios') && 
               req.ip === '127.0.0.1';
    }
});
```

## 📊 Monitoramento

### Logs de Auditoria
- **Localização:** `storage/logs/audit-YYYY-MM-DD.log`
- **Banco:** Tabela `audit_logs`
- **Severidades:** `info`, `warning`, `critical`

### Alertas Críticos
Ações que geram alertas automáticos:
- Tentativas de login falhadas
- Acesso negado a áreas administrativas
- Mudanças de plano bloqueadas
- Erros de validação
- API keys inválidas

### Métricas de Segurança
```javascript
// Buscar tentativas de login falhadas
const failedLogins = await getAuditLogs({
    action: 'login:failed',
    startDate: new Date(Date.now() - 24*60*60*1000).toISOString()
});

// Buscar acessos administrativos
const adminAccess = await getAuditLogs({
    action: 'admin:access_granted',
    startDate: new Date(Date.now() - 7*24*60*60*1000).toISOString()
});
```

## 🚨 Ações de Emergência

### Desabilitar API Key
```javascript
const { disableApiKey } = require('./utils/migrateApiKeys');
await disableApiKey('key-id', 'admin-user-id');
```

### Limpar Cache de Rate Limiting
```javascript
// Em caso de emergência, reiniciar o servidor limpa os caches
// Ou implementar endpoint administrativo para limpeza manual
```

### Verificar Logs Críticos
```bash
# Buscar alertas críticos nos logs
grep "🚨 ALERTA DE SEGURANÇA" storage/logs/audit-*.log

# Buscar tentativas de login falhadas
grep "login:failed" storage/logs/audit-*.log
```

## 📝 Checklist de Segurança

- [x] Mudança de plano bloqueada para usuários gratuitos
- [x] Proteção CSRF implementada
- [x] API keys hasheadas e com rate limiting
- [x] Rate limiting geral implementado
- [x] Logs de auditoria completos
- [x] Mensagens de erro sanitizadas
- [x] Controle de acesso centralizado
- [x] Middleware de segurança criado
- [x] Sistema de alertas implementado
- [x] Documentação de segurança criada

## 🔄 Próximos Passos

1. **Executar migração de API keys:** `node utils/migrateApiKeys.js`
2. **Adicionar tokens CSRF em formulários existentes**
3. **Configurar alertas externos** (Discord, Slack, email)
4. **Implementar rotação automática de API keys**
5. **Adicionar autenticação 2FA obrigatória para admins**
6. **Configurar backup automático dos logs de auditoria**

## 📞 Suporte

Em caso de problemas de segurança:
1. Verificar logs de auditoria
2. Revisar configurações de rate limiting
3. Validar funcionamento do CSRF
4. Confirmar que API keys estão hasheadas

---

**⚠️ IMPORTANTE:** Todas as correções foram implementadas mantendo compatibilidade com a comunicação Wings e funcionalidades existentes.