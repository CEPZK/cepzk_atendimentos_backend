# CEPZK — Atendimentos (Backend)

Backend do sistema de controle dos atendimentos de tratamentos da Casa Espírita
CEPZK.

## Visão geral

Após a entrevista no Atendimento Fraterno, o entrevistador cadastra o assistido
no sistema junto com os tratamentos pelos quais ele irá passar. Em cada
atendimento, quando o assistido recebe alta, um voluntário marca o tratamento
como completo. No tratamento do **Acolher com Amor (ACA)**, os voluntários
mantêm a agenda de sessões de cada assistido, com procedimentos e relatórios.

**Stack atual:**

- [Supabase](https://supabase.com) — banco de dados (Postgres), autenticação
  (Auth) e API (PostgREST);
- Migrations versionadas no repositório em `supabase/migrations/`.

> Convenção do projeto: aplicação em Português (BR); código em inglês,
> exceto o schema do banco e a documentação.

## Estrutura do repositório

```
├── supabase/
│   ├── config.toml          # Configuração do Supabase CLI (dev local)
│   ├── seed.sql             # Seed local (dados extras, opcional)
│   └── migrations/
│       ├── 20260831000001_create_schema.sql        # Esquema do banco
│       ├── 20260831000002_seed_reference_data.sql  # Catálogos iniciais
│       ├── 20260831000003_row_level_security.sql   # RLS
│       ├── 20260831000004_auth_hooks.sql           # Trigger do sign-up
│       ├── 20260831000005_seed_setor_mediunico.sql # Setor Mediúnico (ajuste)
│       └── 20260831000006_fix_setor_departamento_mapping.sql  # Mapeamento setor→departamento
├── docs/
│   ├── banco-de-dados.md    # Documentação do banco (PT-BR)
│   └── autenticacao.md      # Documentação da autenticação (PT-BR)
├── .env.example
└── README.md
```

## Começando

### 1. Crie um projeto no Supabase

Acesse [supabase.com](https://supabase.com) e crie um projeto (o plano free é
suficiente). Anote a **URL** e a **anon key** em
*Project Settings → API*.

### 2. Aplique as migrations

**Opção A — Supabase CLI (recomendada):**

```bash
# Pré-requisitos: Node.js e Docker
npm install -g supabase
supabase link --project-ref SEU_PROJECT_REF
supabase db push
```

**Opção B — SQL Editor (manual):**

No dashboard, abra *SQL Editor* e execute os arquivos de
`supabase/migrations/` **em ordem** (001 → 004).

### 3. Configure o ambiente

```bash
cp .env.example .env
# preencha SUPABASE_URL e SUPABASE_ANON_KEY
```

### 4. (Opcional) Desenvolvimento local com Docker

```bash
supabase start        # sobe Postgres + Auth + API localmente
supabase status       # URL, keys e senha local
```

O ambiente local aplica as migrations e o `seed.sql` automaticamente.

## Autenticação

Sign-up com e-mail e senha via Supabase Auth. Ao se cadastrar, o voluntário é
criado automaticamente em `cepzk_voluntario` (mesmo `id` do `auth.users`)
através de um trigger — veja [docs/autenticacao.md](docs/autenticacao.md).

## Banco de dados

15 tabelas divididas em dois domínios:

- **`cepzk_*`** — estrutura geral (departamentos, setores, horários,
  voluntários, assistidos, tratamentos);
- **`aca_*`** — extensões específicas do Acolher com Amor (distonias,
  queixas, procedimentos, agenda de sessões, relatórios).

Documentação completa em [docs/banco-de-dados.md](docs/banco-de-dados.md).

## Documentação

- [Banco de dados](docs/banco-de-dados.md)
- [Autenticação](docs/autenticacao.md)

## Próximos passos

- [ ] Frontend da aplicação
- [ ] Cadastro do assistido após a entrevista (Atendimento Fraterno)
- [ ] Marcação de alta / conclusão de tratamento
- [ ] Agenda de sessões do ACA (features a especificar)
