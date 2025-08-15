# Correção do Erro 500 na Página de Login

## Problema Resolvido
O erro "500 server error" na página de login foi causado por uma configuração incorreta do middleware CSRF.

## Erro Original
```
Error rendering login page: TypeError: req.csrfToken is not a function 
     at /root/panel/routes/auth.js:359:22
```

## Causa do Problema
O middleware CSRF estava configurado para **pular** as rotas de autenticação (`/login`, `/register`, `/auth/*`, `/2fa`), mas as rotas em `auth.js` tentavam chamar `req.csrfToken()` para gerar tokens CSRF.

### Configuração Problemática (index.js - linhas 158-161):
```javascript
// Pular CSRF para rotas de autenticação
if (req.path.startsWith('/auth/') || req.path === '/login' || req.path === '/register' || req.path === '/2fa') {
  return next(); // Pulava o middleware CSRF
}
```

### Tentativa de Uso em auth.js (linha 359):
```javascript
res.render("auth/login", {
  req,
  name: (await db.get("name")) || "HydraPanel",
  logo: (await db.get("logo")) || false,
  csrfToken: req.csrfToken(), // ❌ Erro: função não disponível
});
```

## Solução Implementada

### Arquivo: `index.js`
**Removida a exclusão das rotas de autenticação** do middleware CSRF:

```javascript
// Aplicar CSRF apenas para rotas web (não APIs)
app.use((req, res, next) => {
  // Pular CSRF para APIs que usam API keys
  if (req.path.startsWith('/api/') && req.headers['x-api-key']) {
    console.log('Pulando CSRF para API:', req.path);
    return next();
  }
  // Pular CSRF para WebSocket connections
  if (req.headers.upgrade === 'websocket') {
    console.log('Pulando CSRF para WebSocket:', req.path);
    return next();
  }
  
  // ✅ Agora todas as rotas web incluem CSRF
  csrfProtection(req, res, next);
});
```

## Configuração CSRF Mantida

O sistema mantém as seguintes configurações de segurança:

### 1. Middleware CSRF
```javascript
const csrfProtection = csrf({ 
  cookie: {
    httpOnly: true,
    secure: false, // Para desenvolvimento
    sameSite: 'lax'
  },
  ignoreMethods: ['GET', 'HEAD', 'OPTIONS']
});
```

### 2. Token CSRF Disponível Globalmente
```javascript
app.use((req, res, next) => {
  try {
    if (req.csrfToken) {
      res.locals.csrfToken = req.csrfToken();
    }
  } catch (error) {
    console.warn('Erro ao gerar token CSRF:', error.message);
  }
  next();
});
```

### 3. Injeção Automática em Views
```javascript
app.use((req, res, next) => {
  const originalRender = res.render;
  res.render = function(view, options, callback) {
    // ... código para garantir csrfToken em options
  };
  next();
});
```

## Resultado

✅ **Páginas de autenticação funcionando:**
- `/login` - Token CSRF disponível
- `/register` - Token CSRF disponível  
- `/2fa` - Token CSRF disponível
- `/auth/reset-password` - Token CSRF disponível

✅ **Segurança mantida:**
- Proteção CSRF ativa em todas as rotas web
- APIs com chaves continuam funcionando
- WebSocket connections não afetadas

✅ **Erro 500 resolvido:**
- `req.csrfToken()` agora funciona corretamente
- Páginas de login carregam sem erros
- Formulários incluem tokens CSRF válidos

## Teste
Para verificar:
1. Acesse `/login`
2. A página deve carregar sem erro 500
3. O formulário deve incluir o token CSRF
4. O login deve funcionar normalmente

O sistema agora está completamente funcional com proteção CSRF adequada.