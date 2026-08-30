-- ============================================================
-- Passo 15 — coletor de memória por pessoa: public.mind_memoria_fatos
-- ------------------------------------------------------------
-- POR QUE ESTA FUNÇÃO EXISTE
--
--   A memória do participante já é ESCRITA e nunca é LIDA no turno.
--   `analise_gravar` chama `analise_projetar_memoria`, que projeta
--   `dados.customer_memory` em `intelligence.participante_memoria`. O caminho
--   de escrita está vivo. O que faltava era o lado da leitura: nenhum
--   componente do runtime abre essa tabela, então nada que a pessoa disse
--   volta no turno seguinte.
--
--   Esta é a menor mudança que fecha esse circuito: um coletor a mais, na
--   mesma forma dos quatro que já existem (`mind_pessoa_fatos`,
--   `mind_crm_fatos`, `mind_crm_comercial`, `mind_engagement_fatos`).
--   Nenhuma tabela nova, nenhum writer novo, nenhuma arquitetura paralela.
--
-- O QUE ESTA MIGRATION DELIBERADAMENTE NÃO FAZ
--
--   Não altera `public.mind_agent_context`. O comentário daquela função diz,
--   desde o Passo 8, que "Memory entra no Passo 15", e o CONTRATO 3 de
--   `tests/mind_agent_context_contract.sql` trava o conjunto EXATO de chaves
--   do topo. Acrescentar uma chave ali é mudar o contrato do AGENT_CONTEXT
--   e o caminho síncrono compartilhado — decisão e momento que não são
--   desta migration. O coletor entra pronto e é ligado por quem integrar o
--   runtime, com uma linha.
--
-- ------------------------------------------------------------
-- SEMÂNTICA CONGELADA DA LEITURA
--
--   `ativa`  → a análise classificou como escopo estável E confiança alta
--              (`analise_projetar_memoria`), ou o próprio usuário confirmou
--              (`mindagent_chat_save_interests`). É o que se pode tratar
--              como sabido sobre a pessoa.
--
--   `proposta` → tudo o mais que a análise extraiu. É inferência ainda não
--              promovida.
--
--   As duas NUNCA se misturam no payload. `memorias` carrega as ativas;
--   `propostas` carrega as propostas. Fundir as listas transformaria
--   inferência fraca em fato — exatamente o que o Passo 15 proíbe. Quem
--   consome decide o que fazer com cada uma; o coletor não decide por ele.
--
--   `substituida` é histórico e nunca sai. Memória expirada (`valido_ate`
--   no passado) nunca sai. As duas viram contagem em `meta`, para que a
--   ausência seja legível e não silenciosa.
--
--   DOIS WRITERS, DUAS FORMAS DE `valor`, NENHUMA TERCEIRA INVENTADA:
--   `analise_projetar_memoria` grava `{text, scope}`; a superfície de chat
--   grava `{label, confirmed}`. O coletor devolve `valor` cru e deriva
--   `texto` por coalesce(text, label). Não normaliza, não reescreve, não
--   completa o que o writer não gravou — `escopo` fica nulo quando o writer
--   não informa escopo.
--
--   Coletor factual: não usa LLM, não escreve, não pontua, não recomenda,
--   não lê CRM, Product Intelligence, Kit nem continuidade/Silence.
-- ============================================================

create or replace function public.mind_memoria_fatos(p_pessoa_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pessoas, intelligence
as $fn$
with
alvo as (
  select p.id from pessoas.pessoas p where p.id = p_pessoa_id
),

-- Tudo o que a pessoa tem na casa da memória. O recorte de "viva" acontece
-- depois, para que o que foi descartado ainda possa ser contado em meta.
bruto as (
  select pm.status, pm.tipo, pm.chave, pm.valor, pm.confianca, pm.importancia,
         pm.origem, pm.analise_conversa_id, pm.evidencia_message_id,
         pm.valido_ate, pm.criado_em, pm.atualizado_em,
         (pm.valido_ate is not null and pm.valido_ate <= now()) as expirada
    from intelligence.participante_memoria pm
   where pm.participante_id = p_pessoa_id
),

viva as (
  select * from bruto b
   where b.status in ('ativa', 'proposta')
     and not b.expirada
),

item as (
  select v.status,
         jsonb_build_object(
           'tipo',                 v.tipo,
           'chave',                v.chave,
           -- coalesce entre as duas formas realmente gravadas hoje.
           'texto',                coalesce(v.valor->>'text', v.valor->>'label'),
           'escopo',               v.valor->>'scope',
           'valor',                v.valor,
           'confianca',            v.confianca,
           'importancia',          v.importancia,
           'origem',               v.origem,
           'analise_conversa_id',  v.analise_conversa_id,
           'evidencia_message_id', v.evidencia_message_id,
           'valido_ate',           v.valido_ate,
           'registrada_em',        v.criado_em,
           'atualizada_em',        v.atualizado_em) as j,
         v.tipo, v.chave
    from viva v
),

memorias as (
  select coalesce(jsonb_agg(i.j order by i.tipo, i.chave), '[]'::jsonb) as j
    from item i where i.status = 'ativa'
),
propostas as (
  select coalesce(jsonb_agg(i.j order by i.tipo, i.chave), '[]'::jsonb) as j
    from item i where i.status = 'proposta'
),

meta as (
  select jsonb_build_object(
    'ativas',                 (select count(*) from viva v where v.status = 'ativa'),
    'propostas',              (select count(*) from viva v where v.status = 'proposta'),
    -- o que existe mas não sai, dito em voz alta.
    'expiradas_ignoradas',    (select count(*) from bruto b where b.expirada),
    'substituidas_ignoradas', (select count(*) from bruto b where b.status = 'substituida'),
    'origens',                (select coalesce(jsonb_agg(distinct v.origem), '[]'::jsonb) from viva v),
    'ultima_atualizacao',     (select max(v.atualizado_em) from viva v)) as j
)

select case
  when p_pessoa_id is null then
    jsonb_build_object('ok', false, 'motivo', 'sem_pessoa')
  when not exists (select 1 from alvo) then
    jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada', 'pessoa_id', p_pessoa_id)
  else
    jsonb_build_object(
      'ok',        true,
      'pessoa_id', p_pessoa_id,
      'memorias',  (select j from memorias),
      'propostas', (select j from propostas),
      'meta',      (select j from meta))
end
$fn$;

revoke all on function public.mind_memoria_fatos(uuid) from public, anon, authenticated;
grant execute on function public.mind_memoria_fatos(uuid) to service_role;

comment on function public.mind_memoria_fatos(uuid) is
  'Passo 15 — coletor de memoria da pessoa a partir de intelligence.participante_memoria. Devolve memorias (status=ativa) e propostas (status=proposta) em listas SEPARADAS: proposta e inferencia nao promovida e nunca vira fato por fusao. substituida e memoria expirada nunca saem; viram contagem em meta. valor e devolvido cru e texto = coalesce(text,label), as duas formas realmente gravadas pelos dois writers vivos. Nao usa LLM, nao escreve, nao pontua, nao recomenda, nao le CRM, Product Intelligence, Kit nem continuidade. Nao e chamado por mind_agent_context: o wiring do runtime e do passo de integracao.';
