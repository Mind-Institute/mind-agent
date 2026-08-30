-- ============================================================
-- session_speakers — speaker_id vira a identidade canônica, e a única
-- ------------------------------------------------------------
-- DECISÃO CANÔNICA
--   Todo vínculo válido pessoa↔sessão TEM speaker_id. Se a pessoa não existe
--   em ecossistema.palestrantes_especialistas, não se cria vínculo incompleto.
--   Por isso speaker_id passa a NOT NULL e a PK passa a ser (sessao_id,
--   speaker_id) — não uma UNIQUE que ainda admitisse linha sem identidade.
--
--   `palestrante_id` é legado. Deixa de ser obrigatório, não gera IDs novos e
--   não entra em lógica nova. Continua fisicamente na tabela: as funções
--   legadas ainda citam a coluna no texto, e apagá-la é frente separada.
--
-- ESTADO ANTES (produção, conferido)
--   PRIMARY KEY (sessao_id, palestrante_id)   -- palestrante_id uuid NOT NULL
--   speaker_id bigint NULL, FK → ecossistema.palestrantes_especialistas(id)
--   12 linhas · speaker_id nulo: 0 · palestrante_id nulo: 0
--   duplicatas de (sessao_id, speaker_id): 0
--   Ou seja: NOT NULL e a nova PK entram sem violação e sem tocar em dado.
--
-- POR QUE ISSO É SEGURO — consumidores conferidos no catálogo
--   Seis funções citam `palestrante_id`: api.sessions, api.speakers,
--   api.mindagent_bootstrap, api.treble_event_bundle,
--   public.mind_admin_read_resource e public.mind_admin_mutate_resource.
--   TODAS leem `summit.session_speakers` e `comum.speakers`. Nenhum desses
--   objetos existe: `summit` virou `summit_2026`, `comum` virou `ecossistema`
--   e `comum.speakers` foi deletada. Verificado: os schemas `summit` e `comum`
--   não constam de pg_namespace, e to_regclass de ambas as relações é NULL.
--   Não é dedução — executar public.mind_admin_dashboard_counts() hoje aborta
--   com 42P01 relation "summit.sessions" does not exist. O único writer que
--   insere com palestrante_id (mind_admin_mutate_resource) é código morto.
--
--   O único consumidor vivo, public.mindagent_chat_search, usa
--   summit_2026.session_speakers com join por speaker_id em
--   ecossistema.palestrantes_especialistas e nunca menciona palestrante_id.
--
--   A tabela não pertence à publicação `supabase_realtime` (que não é FOR ALL
--   TABLES) e nenhuma FK externa aponta para ela: trocar a PK não afeta
--   replicação lógica nem outra tabela.
--
-- EFEITO COLATERAL QUE VALE REGISTRAR
--   A FK existente é ON DELETE SET NULL. Com speaker_id NOT NULL, apagar uma
--   pessoa do Ecossistema que tenha vínculo passa a FALHAR (violação de NOT
--   NULL) em vez de silenciosamente orfanar o vínculo. O dado fica protegido,
--   mas o erro é indireto. Se preferir um erro explícito, a forma canônica é
--   trocar a ação da FK para ON DELETE RESTRICT — mudança de uma linha,
--   deixada de fora aqui porque a instrução foi preservar a FK existente.
--
-- NÃO FAZ
--   Não remove palestrante_id. Não cria surrogate id novo. Não altera dado.
--   Não toca nas 12 linhas.
-- ============================================================

-- 1. A PK antiga depende de palestrante_id — é ela que obriga um UUID legado
--    em todo vínculo novo.
alter table summit_2026.session_speakers
  drop constraint agenda_sessao_palestrantes_pkey;

-- 2. Legado deixa de ser obrigatório.
alter table summit_2026.session_speakers
  alter column palestrante_id drop not null;

-- 3. Identidade canônica passa a ser obrigatória: sem pessoa no Ecossistema,
--    não há vínculo.
alter table summit_2026.session_speakers
  alter column speaker_id set not null;

-- 4. PK canônica. Também é o que impede a mesma pessoa duas vezes na mesma
--    sessão — sem constraint auxiliar.
alter table summit_2026.session_speakers
  add constraint session_speakers_pkey
  primary key (sessao_id, speaker_id);

comment on column summit_2026.session_speakers.palestrante_id is
  'LEGADO. Identidade antiga de palestrante, herdada de comum.speakers (tabela deletada). Não é obrigatória, não gera IDs novos e não deve ser usada em lógica nova. A identidade canônica da pessoa é speaker_id.';

comment on column summit_2026.session_speakers.speaker_id is
  'Identidade canônica da pessoa: ecossistema.palestrantes_especialistas.id. Obrigatória e parte da PRIMARY KEY — todo vínculo pessoa↔sessão tem identidade canônica.';

comment on constraint session_speakers_pkey on summit_2026.session_speakers is
  'PK canônica (sessao_id, speaker_id): identifica o vínculo pela sessão e pela pessoa do Ecossistema, e impede a mesma pessoa duas vezes na mesma sessão.';
