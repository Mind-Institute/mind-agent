-- O tom de voz e os playbooks são o cérebro compartilhado de TODO agente do
-- Mind — o Concierge e o atendimento vão usar os mesmos. Não são do bot do
-- WhatsApp. Estavam em treble.prompts porque foi ali que nasceram; a regra é a
-- mesma da identidade: o agente não é dono do dado.
--
-- treble fica só com o runtime do bot: config, conversations, messages,
-- agent_events. O cérebro vai para o schema novo `agentes`.
--
-- Reversível: é troca de catálogo (ALTER ... SET SCHEMA), não reescreve dado.
-- Para desfazer: alter table agentes.prompts set schema treble; restaurar o
-- corpo da função lendo treble.prompts; drop schema agentes.

create schema if not exists agentes;
comment on schema agentes is
  'Cérebro compartilhado dos agentes do Mind: como falam (tom de voz) e como agem (playbooks, base, objeções). Usado por qualquer agente; nenhum é dono. treble/concierge guardam só o runtime da própria ferramenta.';

-- Instantâneo: preserva PK, RLS, políticas, grants e a FK para o catálogo.
alter table treble.prompts set schema agentes;

comment on table agentes.prompts is
  'Blocos do prompt, um por linha (chave): base + tom_de_voz + playbook_<audience> + objecoes. Compostos por turno em public.treble_agent_prompt. Trocar comportamento é UPDATE, não deploy.';

-- A única função que lê os prompts em runtime. Mesmo nome e assinatura: a Edge
-- Function continua chamando treble_agent_prompt sem mudar nada — só o corpo
-- passa a ler de agentes.prompts. CREATE OR REPLACE preserva os grants.
create or replace function public.treble_agent_prompt(p_audience text default 'desconhecido')
  returns text
  language sql
  security definer
  set search_path to 'public', 'agentes'
as $function$
  select string_agg(conteudo, E'\n\n' order by ordem)
  from (
    select conteudo, 1 as ordem from agentes.prompts where chave = 'base' and ativo
    union all
    select conteudo, 2 from agentes.prompts where chave = 'tom_de_voz' and ativo
    union all
    select conteudo, 3 from agentes.prompts
     where chave = 'playbook_' || coalesce(nullif(p_audience,''), 'desconhecido') and ativo
    union all
    select conteudo, 4 from agentes.prompts
     where chave = 'objecoes' and ativo
       and coalesce(p_audience,'desconhecido') in ('b2c','desconhecido','b2b')
  ) partes;
$function$;
