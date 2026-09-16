-- Camarote não conseguia recomendação de programação nenhuma: a MIA identificava
-- o ingresso certo e ainda assim recusava tudo ("não tenho a regra oficial de
-- acesso dessa categoria"). Adriana viu isso ao vivo em 06/09/2026 e pediu para
-- entender a estrutura antes de mexer — é o que este comentário registra.
--
-- Estrutura conferida (nada disparou sozinho por engano):
--   - `public.mind_kit_programacao_filtrada` é quem monta `programacao.sessions`
--     para o Kit do Concierge (bloco obrigatório, `agentes.kit_blocos`);
--   - ela pega `mind_credenciamento_fatos(pessoa).categorias` (já correto e já
--     devolve "Camarote" — corrigido em 20260902220000) e filtra de novo por um
--     allowlist FECHADO: `array['mind','vip','prime']`. "camarote" nunca passa,
--     `v_categorias` fica vazio, e a função devolve
--     `motivo_sem_sessoes = 'categoria_sem_regra_de_acesso'` — o dado exato que
--     vira a frase de recusa no playbook (§"CONTEXTO TEMPORAL, INGRESSO E
--     DESCOBERTA", 20260903120000): "Se programacao.ingresso.motivo_sem_sessoes
--     estiver preenchido, explique que não consegue confirmar uma opção
--     compatível". O playbook está certo; o dado que ele recebe é que está errado;
--   - é a MESMA classe de bug já vista duas vezes neste repositório (pílula de
--     ingresso no app, e `api.mindagent_participante_ingresso`), sempre por uma
--     lista fechada de categorias esquecida depois que o Camarote passou a
--     existir. As duas vezes anteriores, o reparo foi abrir a lista, não somar
--     mais um literal nela — mesmo reparo aqui;
--   - `summit_2026.sessions.ingressos` também não tem NENHUMA linha com
--     "camarote" hoje: mesmo com a função corrigida, não haveria o que casar.
--     Não existe cron nem sync automático sobre essa coluna (conferido em
--     `cron.job`), então a correção manual não corre o risco do Prime esgotado
--     de hoje cedo (nada vai sobrescrever silenciosamente);
--   - decisão já dada pela Adriana hoje para esta mesma categoria: "acessos da
--     experiência Camarote = idêntico do Prime". `prime` está em TODAS as 77
--     sessões (as três combinações vigentes de `ingressos` incluem prime), então
--     "idêntico ao Prime" em sessão quer dizer: Camarote entra em todas onde
--     Prime está.
--
-- Duas mudanças, nenhuma nova tabela:
--   1. a função para de reaplicar o allowlist fechado — só normaliza para
--      minúsculas o que `mind_credenciamento_fatos` já validou (ativo, não
--      revogado, sem a sentinela "SEM MAPA"). Mind/VIP/Prime continuam
--      exatamente como estavam; só deixa de barrar categoria nova por engano;
--   2. `ingressos` ganha "camarote" em toda sessão que já tinha "prime".
--
-- Reversível: `update summit_2026.sessions set ingressos = array_remove(ingressos,'camarote')`
-- e recriar a função com o allowlist antigo.
-- Idempotente: o UPDATE só toca quem ainda não tem "camarote"; a função é
-- create or replace puro.

begin;

-- 1. A função para de derrubar categoria que não está em um literal fixo -----------------
create or replace function public.mind_kit_programacao_filtrada(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_base jsonb;
  v_pessoa uuid;
  v_cred jsonb;
  v_categorias text[] := '{}'::text[];
  v_sessoes jsonb := '[]'::jsonb;
begin
  v_base := public.mind_kit_programacao(p_conversa_id,p_necessidade);
  if v_base is null then return null; end if;

  select c.participante_id into v_pessoa
  from engagement.conversas c where c.id=p_conversa_id;

  if v_pessoa is null then
    return v_base || jsonb_build_object('ingresso',jsonb_build_object(
      'identificado',false,'recomendacoes_filtradas',false));
  end if;

  v_cred := public.mind_credenciamento_fatos(v_pessoa);
  -- mind_credenciamento_fatos já é a casa que decide categoria válida (ativo,
  -- não revogado, sem a sentinela "SEM MAPA"). Só normaliza para minúsculas
  -- aqui; não reaplica um segundo allowlist que fica esquecido no próximo
  -- tipo de ingresso novo.
  select coalesce(array_agg(lower(x)), '{}'::text[])
    into v_categorias
  from jsonb_array_elements_text(coalesce(v_cred->'categorias','[]'::jsonb)) x;

  if coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false)
     and cardinality(v_categorias)>0 then
    select coalesce(jsonb_agg(item order by ord),'[]'::jsonb)
      into v_sessoes
    from jsonb_array_elements(coalesce(v_base->'sessions','[]'::jsonb))
           with ordinality j(item,ord)
    join summit_2026.sessions s on s.id=(j.item->>'id')::uuid
    where coalesce(s.ingressos,'{}'::text[]) && v_categorias;
  end if;

  v_base := jsonb_set(v_base,'{sessions}',v_sessoes,true);
  v_base := jsonb_set(v_base,'{sessions_total}',to_jsonb(jsonb_array_length(v_sessoes)),true);
  return v_base || jsonb_build_object('ingresso',jsonb_build_object(
    'identificado',true,
    'tem_ingresso_ativo',coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false),
    'categorias',coalesce(v_cred->'categorias','[]'::jsonb),
    'categorias_aplicadas',to_jsonb(v_categorias),
    'recomendacoes_filtradas',true,
    'motivo_sem_sessoes',case
      when not coalesce((v_cred->>'tem_ingresso_ativo')::boolean,false) then 'sem_ingresso_ativo'
      when cardinality(v_categorias)=0 then 'categoria_sem_regra_de_acesso'
      when jsonb_array_length(v_sessoes)=0 then 'nenhuma_sessao_compativel_na_busca'
      else null end));
end
$function$;

revoke all on function public.mind_kit_programacao_filtrada(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function public.mind_kit_programacao_filtrada(uuid,jsonb)
  to service_role;

-- 2. Camarote entra em toda sessão onde o Prime já está -----------------------------------
update summit_2026.sessions
   set ingressos = array_append(ingressos, 'camarote'),
       atualizado_em = now()
 where 'prime' = any(ingressos)
   and not ('camarote' = any(ingressos));

-- 3. Provas: allowlist fechado sumiu; camarote replicou o prime; pessoa Camarote
--    REAL de hoje já teria sessão compatível. Nenhuma conversa fictícia criada.
do $$
declare
  v_pessoa uuid;
  v_cred jsonb;
  v_categorias text[];
  v_matches integer;
  v_func_src text;
begin
  select pg_get_functiondef(p.oid) into v_func_src
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='mind_kit_programacao_filtrada';
  if v_func_src ilike '%array[''mind'',''vip'',''prime'']%' then
    raise exception 'allowlist fechado ainda presente em mind_kit_programacao_filtrada';
  end if;

  if (select count(*) from summit_2026.sessions where 'prime' = any(ingressos))
       <> (select count(*) from summit_2026.sessions where 'camarote' = any(ingressos)) then
    raise exception 'camarote não replicou o acesso do prime em todas as sessões';
  end if;

  select v.pessoa_id into v_pessoa
  from credenciamento_summit_2026.v_participantes v
  where lower(coalesce(v.status,'')) = 'ativo'
    and v.revogado_em is null
    and v.pessoa_id is not null
    and coalesce(nullif(btrim(v.ticket_name),''), nullif(btrim(v.ticket_type),'')) ilike 'camarote'
  limit 1;
  if v_pessoa is null then
    raise exception 'nenhuma pessoa Camarote ativa encontrada para a prova';
  end if;

  v_cred := public.mind_credenciamento_fatos(v_pessoa);
  select array_agg(lower(x)) into v_categorias
  from jsonb_array_elements_text(coalesce(v_cred->'categorias','[]'::jsonb)) x;

  if not ('camarote' = any(v_categorias)) then
    raise exception 'categoria camarote não chegou normalizada a partir do credenciamento real';
  end if;

  select count(*) into v_matches
  from summit_2026.sessions s
  where coalesce(s.ingressos,'{}'::text[]) && v_categorias;

  if v_matches = 0 then
    raise exception 'pessoa Camarote real continua sem nenhuma sessão compatível';
  end if;
end $$;

commit;
