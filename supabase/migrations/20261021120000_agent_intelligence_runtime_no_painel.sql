-- PAINEL: AGENT INTELLIGENCE MOSTRA O QUE CADA AGENTE LÊ DE VERDADE (SÓ LEITURA).
--
-- Pedido da Adriana (21/10/2026): popular a página Agent Intelligence com os agentes que existem,
-- os conhecimentos que acessam e onde estão acessíveis ou plugáveis. Função aprovada por ela (D7)
-- no mesmo dia: uma leitura nova, fechada, sem tabela nova e sem escrita.
--
-- Por que existe: a matriz `agentes.knowledge_access` (a que a página já mostrava) não chega a nenhum
-- agente — só o admin e `mind_knowledge_buscar_global` a leem, e nenhum agente chama essa busca.
-- O que o agente lê de verdade no turno vem de duas casas que o painel não alcançava (o schema
-- `agentes` não é exposto à API):
--   · agentes.canal_competencia — em que canal a rota está ligada;
--   · agentes.kit_blocos        — os blocos do Kit: fatos estruturados, decisioning e ferramentas.
-- A página passa a separar "lê hoje" (estas duas) de "plugável" (a matriz, decisão da Adriana).
--
-- Uma porta, no molde de mind_admin_read_agent_intelligence_access (só o service_role executa; a
-- mindagent-knowledge chama):
--   · mind_admin_read_agent_runtime(p_id) — uma linha por rota que aparece em canal_competencia ou
--     kit_blocos, com o playbook (`playbook_<rota>` em agentes.prompts), os canais com o veredito do
--     próprio Capability Gate (`mind_rota_capacidade`, o mesmo que o runtime usa) e os blocos do Kit.
-- Nenhuma lista de agentes escrita aqui: a rota existe se o banco diz que existe.
--
-- GATE PENDENTE (segurança — Adriana): NÃO MERGEAR ASSIM. Testada em produção dentro de transação com
-- rollback, como service_role: "permission denied for schema agentes". O service_role não tem USAGE em
-- `agentes` (nem em `ecossistema`/`catalogo`), e é por isso que a página Agent Intelligence já devolve 503
-- hoje (log de 21/10): as portas que ela usa são SECURITY INVOKER. As saídas possíveis — SECURITY DEFINER
-- nas portas do painel (molde de mind_admin_read_ofertas/mind_admin_read_knowledge_sources) ou USAGE+SELECT
-- ao service_role — mudam permissão e esperam a decisão dela.

create or replace function public.mind_admin_read_agent_runtime(p_id text default null)
returns setof jsonb
language sql
stable
set search_path to ''
as $fn$
  with rotas as (
    select cc.rota from agentes.canal_competencia cc
    union
    select kb.rota from agentes.kit_blocos kb
  )
  select jsonb_build_object(
    'id', r.rota,
    'agentKey', r.rota,
    'playbook', (
      select jsonb_build_object(
        'chave', p.chave,
        'titulo', p.titulo,
        'versao', p.versao,
        'ativo', p.ativo,
        'produtoCodigo', p.produto_codigo,
        'atualizadoEm', p.atualizado_em
      )
      from agentes.prompts p
      where p.chave = 'playbook_' || r.rota
    ),
    'canais', coalesce((
      select jsonb_agg(jsonb_build_object(
        'canal', c.canal,
        'ativo', c.ativo,
        'observacao', c.observacao,
        'podeExecutar', coalesce((cap.v ->> 'pode_executar')::boolean, false),
        'motivo', cap.v ->> 'reason',
        'atualizadoEm', c.atualizado_em
      ) order by c.canal)
      from agentes.canal_competencia c
      cross join lateral (select public.mind_rota_capacidade(c.rota, c.canal) as v) cap
      where c.rota = r.rota
    ), '[]'::jsonb),
    'kit', coalesce((
      select jsonb_agg(jsonb_build_object(
        'bloco', k.bloco,
        'provider', k.provider,
        'secao', k.secao,
        'obrigatorio', k.obrigatorio,
        'ativo', k.ativo
      ) order by k.secao, k.bloco)
      from agentes.kit_blocos k
      where k.rota = r.rota
    ), '[]'::jsonb),
    'updatedAt', coalesce(greatest(
      (select max(c.atualizado_em) from agentes.canal_competencia c where c.rota = r.rota),
      (select p.atualizado_em from agentes.prompts p where p.chave = 'playbook_' || r.rota)
    ), now())
  )
  from rotas r
  where p_id is null or r.rota = p_id
  order by r.rota;
$fn$;

comment on function public.mind_admin_read_agent_runtime(text) is
  'Painel Agent Intelligence: por rota, o playbook, os canais com o veredito do Capability Gate e os blocos do Kit. Só leitura; só service_role.';

revoke all on function public.mind_admin_read_agent_runtime(text) from public, anon, authenticated;
grant execute on function public.mind_admin_read_agent_runtime(text) to service_role;
