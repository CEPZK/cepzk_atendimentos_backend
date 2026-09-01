# Autenticação

O sistema usa o **Supabase Auth** para gerenciar os usuários (voluntários do
centro).

## Como funciona

- **Métodos habilitados:** e-mail + senha e magic link (confirmação por
  e-mail desabilitada por padrão — o login é imediato; ajuste em
  *Authentication → Providers* no dashboard conforme preferir).
- **Sign-up aberto:** habilitado por padrão (`enable_signup = true` no
  `supabase/config.toml`). Se quiser apenas cadastro manual pela
  administração, desative o sign-up no dashboard e crie os usuários em
  *Authentication → Users*.
- **JWT:** expiração padrão de 1 hora. O `id` do usuário no JWT é o mesmo
  `uuid` usado em `cepzk_voluntario.id`.

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
é criado **automaticamente no sign-up** por um trigger (`after insert on
auth.users` → `public.handle_new_user()`):

```sql
create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();
```

O nome do voluntário vem, nesta ordem:

1. `raw_user_meta_data.nome` — campo `nome` enviado no sign-up;
2. `raw_user_meta_data.name`;
3. parte do e-mail antes do `@`.

### Exemplo de sign-up (frontend)

```js
const { data, error } = await supabase.auth.signUp({
  email: 'maria@exemplo.com',
  password: 'senha-forte',
  options: { data: { nome: 'Maria da Silva' } },
});
```

Após o sign-up, já existe a linha correspondente em `cepzk_voluntario`.

> O nome pode ser corrigido depois com um simples `update` em
> `cepzk_voluntario` (todo voluntário logado tem acesso — veja RLS abaixo).

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
  (consultando `cepzk_voluntario_setor`);
- catálogos (`cepzk_departamento`, `cepzk_setor`, `cepzk_horario`,
  `aca_distonia`, `aca_queixa`, `aca_procedimento`) em **somente leitura**;
- assistidos só podem ser **alterados** por quem atua no Atendimento
  Fraterno.

Ao refinar, remova/substitua a política `autenticados_acesso_completo` das
tabelas correspondentes.

## Boas práticas

- **Nunca** exponha a `service_role key` no frontend — use apenas no
  backend/processos administrativos;
- O frontend deve usar a **anon key** + JWT do usuário logado
  (`supabase.auth.getSession()`);
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
