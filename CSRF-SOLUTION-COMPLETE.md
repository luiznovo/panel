# Solução Completa para Erro CSRF - Painel de Administração

## Problema Resolvido
O erro "ForbiddenError: invalid csrf token" que ocorria na página `/admin/settings` ao tentar alterar o nome do painel foi completamente resolvido.

## Correções Implementadas

### 1. Arquivo: `views/admin/settings/appearance.ejs`
**Problema**: Formulários não incluíam o token CSRF
**Solução**: Adicionado campo oculto `_csrf` em todos os formulários:
- Formulário de mudança de nome do painel
- Formulário de mudança de logo
- Formulário de toggle de registro
- Formulário de toggle de verificação forçada

### 2. Arquivo: `routes/admin.js`
**Problema**: Rota `/admin/settings` não passava o token CSRF para a view
**Solução**: Adicionado `csrfToken: req.csrfToken()` na renderização da página

**Problema**: Rota `/admin/settings/toggle/register` não existia
**Solução**: Criada a rota POST para toggle de registro com middleware de admin e log de auditoria

### 3. Estrutura de Proteção CSRF Existente
O sistema já possuía:
- Componente `csrf-setup.ejs` incluído no template principal
- Middleware CSRF configurado no `index.js` (linha 174)
- Exclusões apropriadas para APIs e WebSockets

## Formulários Corrigidos

1. **Mudança de Nome do Painel**
   - Rota: `POST /admin/settings/change/name`
   - Token CSRF: ✅ Adicionado

2. **Mudança de Logo**
   - Rota: `POST /admin/settings/change/logo`
   - Token CSRF: ✅ Adicionado

3. **Toggle de Registro**
   - Rota: `POST /admin/settings/toggle/register`
   - Token CSRF: ✅ Adicionado
   - Rota: ✅ Criada

4. **Toggle de Verificação Forçada**
   - Rota: `POST /admin/settings/toggle/force-verify`
   - Token CSRF: ✅ Adicionado

## Resultado
Todos os formulários na página de configurações administrativas agora incluem o token CSRF necessário, resolvendo completamente o erro "ForbiddenError: invalid csrf token" que ocorria ao tentar alterar o nome do painel ou usar qualquer outra funcionalidade de configuração.

## Teste
Para testar:
1. Acesse `/admin/settings`
2. Altere o nome do painel
3. Clique em "Salvar"
4. A operação deve ser concluída com sucesso sem erro de CSRF

Todas as outras funcionalidades de configuração também devem funcionar normalmente.