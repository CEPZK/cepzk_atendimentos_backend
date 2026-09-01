# Autenticação

O sistema usa o **Supabase Auth** para gerenciar os usuários (voluntários do
centro).

## Como funciona

O acesso é **sem senha** e **somente por convite (invite-only)**:

1. **Convite:** o admin convida o voluntário pelo e-mail (no Supabase
   Dashboard ou, no futuro, pela própria aplicação). O voluntário recebe
   um e-mail com o link de convite;
2. **Primeiro acesso:** o voluntário clica no link, confirma a conta e
   entra na plataforma. O registro em `cepzk_voluntario` é criado
   automaticamente no momento do convite (já com o nome informado por
   quem convidou);
3. **Logins seguintes:** o voluntário clica em "Entrar", informa o e-mail
   e um novo **magic link** é enviado; ao clicar, volta a estar logado.

- **Cadastro próprio é desabilitado:** `enable_signup = false` — um e-mail
  que não recebeu convite não consegue criar conta nem receber link;
- **Senha:** não existe em nenhum momento (login por e-mail/senha não
  funciona); a interface **não deve oferecer campo de senha**;
- **JWT:** expiração padrão de 1 hora. O `id` do usuário no JWT é o mesmo
  `uuid` usado em `cepzk_voluntario.id`.

### Papéis (roles)

Voluntários têm um papel em `cepzk_voluntario.papel`
(`enum papel_voluntario`):

| Papel         | Permissões (por ora)                              |
| ------------- | ------------------------------------------------- |
| `admin`       | Envio de convites e alteração de papéis           |
| `coordenador` | Igual a colaborador (diferenciação prevista)      |
| `colaborador` | Uso normal da plataforma — default de todo convite |

- **Somente `admin` pode enviar convites e alterar papéis.** A proteção
  existe em duas camadas: a Edge Function de convites verifica o papel do
  chamador (JWT) antes de enviar, e o trigger
  `on_voluntario_papel_protected` reverte qualquer mudança de `papel`
  feita por quem não é admin (o `service_role` e a administração local
  são liberados);
- O admin define o papel de cada voluntário em `cepzk_voluntario.papel`.

### Enviando convites (admin)

> Restrito a voluntários com `papel = 'admin'`.

**Pelo Dashboard (sem código):** *Authentication → Users → Invite user* →
informe o e-mail (e o nome, nos metadados) → o e-mail de convite é
enviado. (O acesso ao dashboard já é administrativo.)

**Pela aplicação (previsto):** tela de administração que chama uma Edge
Function com a **service role key** (a API de admin nunca roda no
frontend). A Edge Function deve **verificar que o usuário autenticado
(JWT) tem `papel = 'admin'`** antes de enviar o convite:

```js
// dentro de uma Edge Function (service role)
// 1. lê o JWT do request, busca cepzk_voluntario.papel do usuário
// 2. se papel !== 'admin' -> 403
// 3. senão:
const { data, error } = await supabaseAdmin.auth.admin.inviteUserByEmail({
  email: 'maria@exemplo.com',
  data: { nome: 'Maria da Silva' }, // vira raw_user_meta_data
  redirectTo: 'https://SEU-APP/auth/callback', // página de callback
});
```

> **Primeiro admin:** como ainda não há ninguém logado, o primeiro admin
> não pode ser convidado pelo sistema. Crie-o manualmente em
> *Authentication → Users → Add user* (marcando *Auto confirm user*) e ele
> loga com magic link como qualquer outro voluntário.
>
> Obs.: o link de convite não usa PKCE — a página de callback da
> aplicação precisará tratar o redirecionamento do convite além do fluxo
> de magic link.

### Fluxo de login (frontend)

```js
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// voluntário informa apenas o e-mail; se ele foi convidado, um novo
// magic link é enviado para o e-mail
const { data, error } = await supabase.auth.signInWithOtp({
  email: 'maria@exemplo.com',
  options: {
    // deve estar na allowlist de redirect URLs do projeto
    emailRedirectTo: 'https://SEU-APP/auth/callback',
    shouldCreateUser: false, // reforço: nunca criar usuário sem convite
  },
});
// fluxo: e-mail chega → voluntário clica no link → cai na URL de callback
// com o código → supabase.auth.exchangeCodeForSession() cria a sessão
```

> O método se chama `signInWithOtp`, mas envia um **magic link** por
> padrão (o código numérico OTP é uma variação feita via template de
> e-mail — o padrão do sistema é o link).

### Configuração no projeto (dashboard)

- **Authentication → Providers → Email**: **desative** *"Allow new users
  to sign up"* (essencial para o invite-only — bloqueia cadastro próprio);
- **Authentication → URL Configuration**: defina a *Site URL* e adicione
  as URLs de callback da aplicação (ex.: `https://seu-app.com/auth/callback`)
  — são as **únicas** URLs para onde os links podem redirecionar;
- **(recomendado em produção) Authentication → SMTP Settings**: configure
  um provedor de e-mail próprio (ex.: Resend, SendGrid) para entrega
  confiável;
- Cada convite e cada login enviam e-mail e estão sujeitos ao rate limit
  do projeto (ajustável em *Authentication → Auth Settings*).

## Como a aplicação acessa o banco

A aplicação (rodando no navegador ou em um servidor no seu computador)
**não conecta diretamente no Postgres**. Ela fala com a **API do Supabase
(PostgREST)** via HTTPS, usando:

- `SUPABASE_URL` — a URL do projeto;
- `SUPABASE_ANON_KEY` — a chave pública (pode ficar no frontend);
- **o JWT do usuário logado** — é ele que define o papel usado no banco:
  `authenticated` quando logado, `anon` quando não.

Exemplo com `supabase-js`:

```js
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// depois que o voluntário faz login:
const { data, error } = await supabase.from('cepzk_assistido').select('*');
```

São as políticas de RLS (seção abaixo) que decidem o que cada request pode
fazer: sem login, nenhum acesso às tabelas; com login de voluntário, acesso
conforme as políticas.

> Conexão TCP direta com o Postgres a partir do computador não é o modelo
> de uso do Supabase. Para administração local, use o *SQL Editor* do
> dashboard ou o CLI `supabase` (que se conecta pela rede privada do
> projeto).

## Perfil do voluntário

`cepzk_voluntario` é um espelho 1:1 de `auth.users`. O registro do voluntário
é **criado automaticamente no momento do convite** (o `inviteUserByEmail` já
cria a linha em `auth.users`) e **sincronizado** quando os metadados ou o
e-mail do usuário mudam:

- `on_auth_user_created` (`after insert`) → cria o voluntário
  (com `email` e `nome`);
- `on_auth_user_updated` (`after update`) → atualiza `nome` e `email`;
- `on_voluntario_papel_protected` → protege a coluna `papel` (veja
  [Papéis](#papeis-roles)).

Campos:

- `nome` — vem, nesta ordem: `raw_user_meta_data.nome` (campo `nome`
  enviado no convite), `raw_user_meta_data.name`, ou a parte do e-mail
  antes do `@`;
- `sobrenome` — opcional, preenchido pelo próprio voluntário;
- `email` — espelha `auth.users.email` (o admin o usa para reenviar
  convites);
- `telefone` — preenchido pelo próprio voluntário na plataforma;
- `papel` — `admin` / `coordenador` / `colaborador` (default
  `colaborador`);
- `data_criacao` — quando o registro foi criado (`default now()`).

### Atualizando nome ou e-mail

Quando o voluntário quiser mudar o nome ou o e-mail, o frontend atualiza
os dados do Auth e os triggers cuidam do resto:

```js
await supabase.auth.updateUser({ data: { nome: 'Maria S. da Silva' } });
// cepzk_voluntario.nome é atualizado automaticamente
```

> O `telefone` e o `papel` não vêm do Auth: `telefone` é editado
> diretamente em `cepzk_voluntario`, e `papel` só pode ser alterado por
> admin (protegido por trigger).

## Row Level Security (RLS)

O RLS está **habilitado em todas as tabelas** da aplicação.

### Política da versão 1 (atual)

| Papel         | Acesso                                                        |
| ------------- | ------------------------------------------------------------- |
| `authenticated` | SELECT, INSERT, UPDATE e DELETE em **todas** as tabelas      |
| `anon`        | Nenhum acesso a nenhuma tabela                                |
| `service_role`| Ignora o RLS (uso exclusivo de processos fora do navegador)   |

A política `autenticados_acesso_completo` (criada na migration 003) é
aplicável a qualquer voluntário logado — apropriado para um sistema interno
onde todos os voluntários da casa são confiáveis.

### Refinamentos planejados

À medida que as features forem implementadas, as políticas serão
específicas por feature, por exemplo:

- voluntário só **altera** sessões e relatórios dos setores em que atua
  (consultando `cepzk_escala`);
- catálogos (`cepzk_departamento`, `cepzk_setor`, `cepzk_horario`,
  `aca_distonia`, `aca_queixa`, `aca_procedimento`) em **somente leitura**;
- assistidos só podem ser **alterados** por quem atua no Atendimento
  Fraterno.

Ao refinar, remova/substitua a política `autenticados_acesso_completo` das
tabelas correspondentes.

## Boas práticas

- **Nunca** exponha a `service_role key` no frontend — ela é usada apenas
  em Edge Functions (ex.: envio de convites) e processos administrativos;
- O frontend deve usar a **anon key** + JWT do usuário logado
  (`supabase.auth.getSession()`);
- O formulário de login deve ter **apenas o campo de e-mail** — nenhum
  campo de senha;
- Em caso de desligamento de um voluntário: desabilite/exclua o usuário em
  *Authentication → Users*. A exclusão do `auth.users` remove o login; o
  registro em `cepzk_voluntario` (e o histórico em assistidos/relatórios)
  permanece — a remoção manual do `cepzk_voluntario` falhará enquanto houver
  referências em `entrevistador_id`, `ponte_id` ou `dirigente_id`.

## Variáveis de ambiente

| Variável                  | Obrigatória | Uso                                    |
| ------------------------- | ----------- | -------------------------------------- |
| `SUPABASE_URL`            | Sim         | URL do projeto (`https://xxxx.supabase.co`) |
| `SUPABASE_ANON_KEY`       | Sim         | Cliente (navegador/frontend)           |
| `SUPABASE_SERVICE_ROLE_KEY` | Não       | Somente processos fora do navegador    |

Veja `.env.example`.
