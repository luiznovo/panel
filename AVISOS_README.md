# Sistema de Avisos - DracoPanel

## Visão Geral

O sistema de avisos permite que administradores criem e gerenciem avisos que são exibidos para todos os usuários na página `/instances`. Os avisos podem ter diferentes cores/modelos e podem ser ativados ou desativados conforme necessário.

## Funcionalidades Implementadas

### 1. Painel Administrativo
- **Localização**: `/admin/avisos`
- **Acesso**: Apenas administradores
- **Funcionalidades**:
  - Listar todos os avisos criados
  - Criar novos avisos
  - Editar avisos existentes
  - Excluir avisos
  - Ativar/desativar avisos

### 2. Exibição de Avisos
- **Localização**: Página `/instances` (topo da página)
- **Visibilidade**: Todos os usuários autenticados
- **Características**:
  - Apenas avisos ativos são exibidos
  - Design responsivo para dispositivos móveis
  - Diferentes cores baseadas no modelo escolhido

### 3. Modelos de Avisos

#### Verde (Sucesso)
- **Uso**: Informações positivas, atualizações bem-sucedidas
- **Ícone**: Checkmark
- **Cores**: Fundo verde claro, borda verde, texto verde escuro

#### Amarelo (Aviso)
- **Uso**: Avisos importantes, manutenções programadas
- **Ícone**: Triângulo de aviso
- **Cores**: Fundo amarelo claro, borda amarela, texto amarelo escuro

#### Vermelho (Erro)
- **Uso**: Problemas críticos, interrupções de serviço
- **Ícone**: X em círculo
- **Cores**: Fundo vermelho claro, borda vermelha, texto vermelho escuro

#### Cinza (Informação)
- **Uso**: Informações gerais, notificações neutras
- **Ícone**: Ícone de informação
- **Cores**: Fundo cinza claro, borda cinza, texto cinza escuro

## Estrutura de Dados

Cada aviso é armazenado no banco de dados com a seguinte estrutura:

```json
{
  "id": "timestamp_string",
  "titulo": "Título do aviso",
  "descricao": "Descrição detalhada do aviso",
  "modelo": "green|yellow|red|gray",
  "ativo": true|false,
  "criadoEm": "2025-01-XX...",
  "atualizadoEm": "2025-01-XX..." // opcional
}
```

## Arquivos Modificados/Criados

### Novos Arquivos
1. **`/routes/instances.js`** - Rota para página de instâncias com avisos
2. **`/views/admin/avisos.ejs`** - Interface administrativa para gerenciar avisos

### Arquivos Modificados
1. **`/routes/admin.js`** - Adicionadas rotas para CRUD de avisos
2. **`/views/components/admin_template.ejs`** - Adicionado link "Avisos" na sidebar
3. **`/views/instances.ejs`** - Adicionada seção para exibir avisos ativos

## Rotas da API

### Administrativas
- `GET /admin/avisos` - Lista todos os avisos
- `POST /admin/avisos/create` - Cria um novo aviso
- `POST /admin/avisos/update/:id` - Atualiza um aviso existente
- `POST /admin/avisos/delete/:id` - Exclui um aviso

### Públicas
- `GET /instances` - Página de instâncias com avisos ativos

## Segurança

- Todas as rotas administrativas requerem autenticação de administrador
- Ações sensíveis são registradas no log de auditoria
- Validação de entrada para todos os campos obrigatórios
- Proteção CSRF habilitada

## Uso

### Para Administradores
1. Acesse `/admin/avisos` através da sidebar administrativa
2. Clique em "Criar Aviso" para adicionar um novo aviso
3. Preencha título, descrição, escolha o modelo e defina se está ativo
4. Use "Editar" para modificar avisos existentes
5. Use "Excluir" para remover avisos (com confirmação)

### Para Usuários
- Os avisos ativos aparecerão automaticamente no topo da página `/instances`
- Cada aviso mostra título, descrição e ícone apropriado baseado no modelo
- Design responsivo garante boa visualização em dispositivos móveis

## Considerações Técnicas

- Os avisos são armazenados como JSON no banco de dados
- Sistema utiliza Alpine.js para interatividade dos modais
- CSS responsivo com Tailwind CSS
- Ícones SVG para melhor performance e escalabilidade
- Validação tanto no frontend quanto no backend

## Manutenção

- Avisos inativos não são exibidos mas permanecem no banco de dados
- Recomenda-se revisar periodicamente avisos antigos
- Logs de auditoria registram todas as ações administrativas
- Backup regular do banco de dados recomendado