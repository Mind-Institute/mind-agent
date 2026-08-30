-- ============================================================
-- session_speakers — speaker_id passa a ser o caminho canônico
-- ------------------------------------------------------------
-- OBJETIVO
--   Permitir que um vínculo pessoa↔sessão seja criado usando SOMENTE
--   `speaker_id` → ecossistema.palestrantes_especialistas(id), sem inventar
--   UUID legado para satisfazer a PK antiga.
--
-- ESTADO ANTES
--   PRIMARY KEY (sessao_id, palestrante_id)  -- palestrante_id uuid NOT NULL
--   speaker_id bigint NULL, FK para ecossistema.palestrantes_especialistas
--   12 linhas, todas com speaker_id e palestrante_id preenchidos,
--   nenhuma duplicata de (sessao_id, speaker_id).
--
-- POR QUE ISSO É SEGURO — consumidores conferidos no catálogo de produção
--   Seis funções citam `palestrante_id`:
--     api.sessions, api.speakers, api.mindagent_bootstrap,
--     api.treble_event_bundle, public.mind_admin_read_resource,
--     public.mind_admin_mutate_resource
--   TODAS as seis leem `summit.session_speakers` e `comum.speakers`. Nenhum
--   desses objetos existe: o schema `summit` foi renomeado para `summit_2026`,
--   o schema `comum` para `ecossistema`, e `comum.speakers` foi deletada.
--   Verificado: to_regclass('comum.speakers') e to_regclass('summit.session_speakers')
--   são NULL, e os schemas `summit` e `comum` não constam de pg_namespace.
--   Executar qualquer uma delas hoje já falha — comprovado rodando
--   public.mind_admin_dashboard_counts(), que aborta com
--   42P01 relation "summit.sessions" does not exist.
--   Ou seja: o único writer que insere em session_speakers com palestrante_id
--   (mind_admin_mutate_resource) é código morto. Não há writer vivo.
--
--   O único consumidor vivo é public.mindagent_chat_search, que usa
--   `summit_2026.session_speakers` com join por `speaker_id` em
--   `ecossistema.palestrantes_especialistas` e NUNCA menciona palestrante_id.
--
--   A tabela não pertence à publicação `supabase_realtime` (que não é
--   FOR ALL TABLES), então remover a PK não afeta replicação lógica.
--
-- O QUE ESTA MIGRATION NÃO FAZ
--   Não remove fisicamente `palestrante_id`: as funções legadas ainda citam a
--   coluna no texto, e apagá-la é uma frente separada de limpeza do legado.
--   Não cria surrogate id novo. Não popula dado. Não toca nas 12 linhas.
-- ============================================================

-- 1. A PK depende de palestrante_id. É ela que obriga um UUID legado em todo
--    vínculo novo — a trava que esta migration remove.
alter table summit_2026.session_speakers
  drop constraint agenda_sessao_palestrantes_pkey;

-- 2. palestrante_id deixa de ser obrigatório. Continua existindo e continua
--    preenchido nas 12 linhas históricas; vínculo novo simplesmente não o usa.
alter table summit_2026.session_speakers
  alter column palestrante_id drop not null;

-- 3. Unicidade canônica: a mesma pessoa não entra duas vezes na mesma sessão.
--    NULLS NOT DISTINCT (PG15+) para que a ausência de speaker_id também não
--    possa se repetir na mesma sessão — sem isso, linhas sem identidade
--    canônica se multiplicariam silenciosamente.
alter table summit_2026.session_speakers
  add constraint session_speakers_sessao_speaker_key
  unique nulls not distinct (sessao_id, speaker_id);

comment on column summit_2026.session_speakers.palestrante_id is
  'LEGADO. Identidade antiga de palestrante, herdada de comum.speakers (tabela deletada). Não é mais obrigatória, não gera IDs novos e não deve ser usada em lógica nova. A identidade canônica da pessoa é speaker_id → ecossistema.palestrantes_especialistas.id.';

comment on column summit_2026.session_speakers.speaker_id is
  'Identidade canônica da pessoa: ecossistema.palestrantes_especialistas.id. Caminho único para novos vínculos pessoa↔sessão.';

comment on constraint session_speakers_sessao_speaker_key on summit_2026.session_speakers is
  'Impede a mesma pessoa duas vezes na mesma sessão. NULLS NOT DISTINCT: no máximo uma linha sem identidade canônica por sessão.';
