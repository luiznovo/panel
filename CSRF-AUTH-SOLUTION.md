# Solução para Erro CSRF nas Páginas de Autenticação

## Problema Resolvido
O erro "ReferenceError: csrfToken is not defined" que ocorria na página de login foi completamente resolvido.

## Erro Original
```
ReferenceError: /root/panel/views/auth/login.ejs:7
     5|   <meta name="viewport" content="width=device-width, initial-scale=1.0">
     6|   <title><%= name %> - Login</title>
  >> 7|   <%- include('../components/csrf-setup') %>
     8|   <script src="https://cdn.tailwindcss.com"></script>

/root/panel/views/components/csrf-setup.ejs:5
     3|
     4| <!-- Meta tag for CSRF token -->
  >> 5| <meta name="csrf-token" content="<%= csrfToken %>">
     6|
     7| <!-- Global CSRF token variable -->
     8| <script>

csrfToken is not defined
```

## Correções Implementadas

### 1. Arquivo: `routes/auth.js`
**Problema**: Rotas de autenticação não passavam o token CSRF para as views
**Solução**: Adicionado `csrfToken: req.csrfToken()` em todas as rotas GET que renderizam páginas:

#### Rotas Corrigidas:
- `GET /login` - Página de login
- `GET /register` - Página de registro
- `GET /2fa` - Página de autenticação de dois fatores
- `GET /auth/reset-password` - Página de reset de senha
- `GET /auth/reset/:token` - Formulário de reset de senha

### 2. Proteção CSRF Existente
O formulário de login já possuía proteção condicional:
```html
<% if (typeof csrfToken !== 'undefined') { %>
<input type="hidden" name="_csrf" value="<%= csrfToken %>">
<% } %>
```

### 3. Componente CSRF Universal
O componente `csrf-setup.ejs` já estava sendo incluído corretamente nas páginas, mas faltava a variável `csrfToken` nas rotas.

## Estrutura de Segurança CSRF

### Páginas Protegidas:
1. **Login** (`/login`)
   - Token CSRF: ✅ Adicionado na rota
   - Formulário: ✅ Já incluía verificação condicional

2. **Registro** (`/register`)
   - Token CSRF: ✅ Adicionado na rota
   - Formulário: ✅ Protegido

3. **2FA** (`/2fa`)
   - Token CSRF: ✅ Adicionado na rota
   - Formulário: ✅ Protegido

4. **Reset de Senha** (`/auth/reset-password`)
   - Token CSRF: ✅ Adicionado na rota
   - Formulário: ✅ Protegido

5. **Formulário de Reset** (`/auth/reset/:token`)
   - Token CSRF: ✅ Adicionado na rota
   - Formulário: ✅ Protegido

## Resultado
Todas as páginas de autenticação agora incluem o token CSRF necessário, resolvendo completamente o erro "csrfToken is not defined" e mantendo a segurança adequada contra ataques CSRF.

## Teste
Para testar:
1. Acesse `/login`
2. A página deve carregar sem erros
3. O formulário de login deve funcionar normalmente
4. Todas as outras páginas de autenticação devem funcionar corretamente

O sistema agora está completamente protegido contra ataques CSRF em todas as páginas de autenticação.