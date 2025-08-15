# Correção do Erro CSRF nas Configurações do Painel

## Problema
O erro "ForbiddenError: invalid csrf token" ainda ocorre ao alterar o nome do painel nas configurações administrativas.

## Solução Universal Aplicada
✅ Template principal (`views/components/template.ejs`) já inclui o componente CSRF
✅ Script universal (`public/js/csrf-universal.js`) já criado
✅ Middleware backend (`index.js`) já configurado

## Próximos Passos para Corrigir

### 1. Localizar a Página de Configurações
Procure por arquivos que podem conter o formulário de alterar nome:
- `views/admin/settings.ejs`
- `views/settings.ejs`
- `views/admin/panel-settings.ejs`
- `views/config.ejs`

### 2. Verificar se o Formulário Tem Token CSRF
No arquivo da página de configurações, verifique se o formulário contém:

```html
<form method="POST" action="/admin/settings/change/name">
  <!-- DEVE TER ESTA LINHA: -->
  <input type="hidden" name="_csrf" value="<%= csrfToken %>">
  
  <input type="text" name="panelName" placeholder="Nome do Painel">
  <button type="submit">Salvar</button>
</form>
```

### 3. Se o Token Estiver Ausente
Adicione o campo CSRF no formulário:

```html
<% if (typeof csrfToken !== 'undefined') { %>
<input type="hidden" name="_csrf" value="<%= csrfToken %>">
<% } %>
```

### 4. Para Requisições AJAX
Se a página usar AJAX para salvar, verifique se inclui o cabeçalho:

```javascript
fetch('/admin/settings/change/name', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
  },
  body: JSON.stringify({ panelName: 'Novo Nome' })
});
```

### 5. Verificar Rota Backend
Certifique-se de que a rota `/admin/settings/change/name` não está excluída do CSRF no `index.js`.

## Como Aplicar a Correção

1. **Encontre o arquivo** da página de configurações
2. **Verifique se inclui** `<%- include('../components/csrf-setup') %>` no `<head>`
3. **Adicione o token CSRF** no formulário se estiver ausente
4. **Teste a funcionalidade** após as correções

## Arquivos Já Corrigidos
- ✅ `views/auth/login.ejs`
- ✅ `views/auth/register.ejs`
- ✅ `views/instance/files.ejs`
- ✅ `views/components/template.ejs` (universal)

## Resultado Esperado
Após aplicar a correção, o erro de CSRF deve ser eliminado ao salvar as configurações do painel.