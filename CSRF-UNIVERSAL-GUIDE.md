# Guia de Implementação Universal do CSRF

## Problema Resolvido

Este guia resolve o erro "ForbiddenError: invalid csrf token" que ocorre em várias partes do painel quando formulários não incluem o token CSRF necessário.

## Arquivos Criados

### 1. `/public/js/csrf-universal.js`
Script JavaScript universal que:
- Adiciona automaticamente tokens CSRF a todos os formulários
- Intercepta requisições fetch() e XMLHttpRequest para incluir tokens CSRF
- Observa formulários criados dinamicamente
- Funciona automaticamente sem necessidade de modificação manual

### 2. `/views/components/csrf-setup.ejs`
Componente EJS que:
- Define meta tag com token CSRF
- Cria variável global JavaScript com o token
- Inclui o script universal
- Fornece funções auxiliares para desenvolvimento

## Como Implementar

### ✅ Páginas Já Implementadas
As seguintes páginas já foram atualizadas com a solução CSRF:
- `/views/auth/login.ejs` - Página de login
- `/views/auth/register.ejs` - Página de registro

### Opção 1: Inclusão Manual (Recomendada)

Para implementar nas demais páginas, adicione no `<head>` de cada página que precisa de proteção CSRF:

```ejs
<%- include('components/csrf-setup') %>
```

**Nota:** Ajuste o caminho relativo conforme a estrutura de pastas. Por exemplo:
- Para páginas em `/views/`: `<%- include('components/csrf-setup') %>`
- Para páginas em `/views/admin/`: `<%- include('../components/csrf-setup') %>`
- Para páginas em `/views/auth/`: `<%- include('../components/csrf-setup') %>`

### Opção 2: Inclusão Automática

Se você tem um arquivo de layout principal, adicione a inclusão lá para aplicar a todas as páginas.

### Opção 3: Apenas o Script

Se preferir uma abordagem mais simples, adicione apenas:

```html
<meta name="csrf-token" content="<%= csrfToken %>">
<script>window.csrfToken = '<%= csrfToken %>';</script>
<script src="/js/csrf-universal.js"></script>
```

## Funcionalidades Automáticas

### Formulários HTML
- Todos os formulários POST/PUT/PATCH/DELETE recebem automaticamente um campo `_csrf` oculto
- Formulários GET são ignorados (não precisam de CSRF)
- Formulários criados dinamicamente são detectados automaticamente

### Requisições AJAX
- `fetch()` - Adiciona automaticamente o cabeçalho `X-CSRF-Token`
- `XMLHttpRequest` - Adiciona automaticamente o cabeçalho `X-CSRF-Token`
- Apenas métodos POST/PUT/PATCH/DELETE são afetados

### Funções Auxiliares Disponíveis

```javascript
// Criar formulário com CSRF
const form = createFormWithCSRF('/admin/settings/change/name', 'POST');

// Submeter dados com CSRF
submitWithCSRF('/admin/settings/change/name', 'POST', { name: 'Novo Nome' });

// Fetch com CSRF
fetchWithCSRF('/api/endpoint', {
    method: 'POST',
    body: JSON.stringify(data),
    headers: { 'Content-Type': 'application/json' }
});
```

## Páginas Específicas que Precisam de Correção

### Página de Configurações Admin
Adicione no arquivo de configurações do admin:
```ejs
<%- include('../components/csrf-setup') %>
```

### Outras Páginas com Formulários
Qualquer página que tenha formulários ou faça requisições POST deve incluir o componente.

## Modificações no Backend

O arquivo `index.js` foi modificado para:
- Garantir que o token CSRF esteja sempre disponível em `res.locals.csrfToken`
- Adicionar middleware universal que injeta o token em todas as renderizações

## Verificação de Funcionamento

1. Inclua o componente CSRF na página
2. Abra as ferramentas de desenvolvedor do navegador
3. Verifique se existe:
   - Meta tag: `<meta name="csrf-token" content="...">`
   - Variável global: `window.csrfToken`
   - Script carregado: `/js/csrf-universal.js`
4. Teste um formulário - deve funcionar sem erro de CSRF

## Benefícios

- ✅ **Universal**: Funciona em todas as páginas automaticamente
- ✅ **Automático**: Não requer modificação manual de formulários
- ✅ **Compatível**: Funciona com código existente
- ✅ **Dinâmico**: Detecta formulários criados via JavaScript
- ✅ **Seguro**: Mantém a proteção CSRF ativa
- ✅ **Flexível**: Permite uso manual quando necessário

## Solução de Problemas

### Token não encontrado
- Verifique se `<%- include('components/csrf-setup') %>` está no `<head>`
- Confirme que `csrfToken` está disponível na view

### Formulário ainda dá erro
- Verifique se o script `/js/csrf-universal.js` está carregando
- Confirme que o formulário não tem `method="get"`
- Verifique no console se há erros JavaScript

### Requisições AJAX falham
- Use `fetchWithCSRF()` em vez de `fetch()` para garantia
- Verifique se o cabeçalho `X-CSRF-Token` está sendo enviado

Esta solução resolve universalmente o problema de CSRF em todo o painel, eliminando a necessidade de correções manuais em cada formulário.