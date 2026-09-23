-- =====================================================================================
-- Revisita da inteligência já gravada com a lente JTBD, por regra (sem IA) — 23/09/2026
-- (docs/PERFIL_ICP_JTBD.md §4.4a; pedido da Adriana: "ela chegou com interesse em delegação
-- porque é diretora de RH — isso diz algo sobre o JTBD dela").
-- Cada job "mind" ganha sinais.memoria_regex: expressão aplicada ao texto das memórias de
-- conversa (interesse, objetivo, preferencia_comercial, delegacao, patrocinio, outro) e aos
-- campos de análise de conversa (objective, buyer_objective, use_case, interests). Um casamento
-- vira evidência de 0,60 ("disse em conversa"); com o contexto por família de ICP já existente,
-- "delegação/liderança" + RH vira também "contratar treinamento de liderança".
-- =====================================================================================

update intelligence.jtbd set sinais = sinais || jsonb_build_object('memoria_regex', v.rx), atualizado_em = now()
from (values
  ('boa_empregadora',         'employer branding|marca empregadora|\ygptw\y|great place|melhores empresas para trabalhar|imagem da empresa|reputa[çc][ãa]o como empregador'),
  ('investidora_bem_estar',   'patroc[ií]n|expositor|estande|\ycotas?\y|parceria com o mind|apoiar o summit|investe em bem'),
  ('vender_para_rh',          'vender (para|pra) (o )?(rh|empresas)|prospec[çc]|prospectar|clientes corporativ|decisores? de rh|fechar (contratos|clientes)|minha consultoria|meus clientes|minha empresa de consultoria'),
  ('liderar_melhor',          'liderar melhor|minha lideran[çc]a|meu time|minha equipe|conversas dif[ií]ceis|dar feedback|feedback (para|pro|ao|a) (meu |minha )?(time|equipe)|delega[çc][ãa]o|delegar|seguran[çc]a psicol[óo]gica|ser (um|uma) (bom |boa )?l[ií]der|autorregula[çc]|lideran[çc]a (humanizada|emp[áa]tica|consciente)'),
  ('minha_saude_performance', 'meu burnout|meu esgotamento|meu estresse|minha ansiedade|minha sa[úu]de mental|meu bem-?estar|meu equil[ií]brio|equil[ií]brio (entre )?(vida|trabalho)|minha energia|produtividade pessoal|autocuidado|performance pessoal|minha performance|estou (esgotad|exaust|no limite)|me cuidar|cuidar de mim'),
  ('escolher_programas',      'programas? de bem-?estar|programas? de sa[úu]de mental|pol[ií]tica de bem-?estar|estruturar (o |a )?(bem-?estar|sa[úu]de mental)|gest[ãa]o (estrat[ée]gica )?de bem-?estar|implementar (bem-?estar|sa[úu]de mental)|a[çc][õo]es de bem-?estar|benef[ií]cios de sa[úu]de|sa[úu]de mental (na|da) empresa|bem-?estar (na|da) empresa|para (os |meus )?colaboradores'),
  ('escolher_consultoria',    '(?<!minha )(?<!nossa )(?<!tenho uma )(?<!trabalho com )(?<!trabalho em )(?<!atuo com )(?<!atuo em )consultoria|diagn[óo]stico organizacional|parceiro externo|mind dash|assessoria'),
  ('treinar_liderancas',      'treinamento (de|para) (l[ií]deres|gestores|lideran[çc]as?)|treinar (os |as |meus |nossos )?(gestores|l[ií]deres|lideran[çc]as)|capacitar (os |as |meus |nossos )?(gestores|l[ií]deres|lideran[çc]as)|desenvolver (os |as |meus |nossos )?(gestores|l[ií]deres|lideran[çc]as)|formar l[ií]deres|programa de lideran[çc]a|desenvolvimento de lideran[çc]as?|\ypdl\y|in ?company|turma fechada|workshop para (l[ií]deres|gestores)'),
  ('nr1_mensuracao',          '\ynr-? ?0?1\y|riscos? psicossoc|\ypgr\y|\ygro\y|mensura[çc][ãa]o|diagn[óo]stico de riscos|question[áa]rio de riscos|compliance trabalhista|fiscaliza[çc][ãa]o|fatore?s de risco psicossoc'),
  ('provar_retorno',          '\yroi\y|retorno (do|sobre o?) (investimento|bem-?estar)|business case|indicadores|m[ée]tricas|dados de (pessoas|bem-?estar|sa[úu]de)|convencer (a )?(diretoria|o board|o cfo|a lideran[çc]a)|people analytics|mostrar (resultado|valor)|comprovar'),
  ('engajar_reter',           'engajament|reten[çc][ãa]o|turnover|rotatividade|clima organizacional|pesquisa de clima|clima (da|do) (empresa|time|equipe)|cultura organizacional|prop[óo]sito|pertenciment|significado no trabalho|reconheciment|experi[êe]ncia do colaborador|employee experience'),
  ('autoridade_escala',       'autoridade|certifica[çc][ãa]o|credencial|me diferenciar|me posicionar|escalar (minha|meu|a minha|o meu)|al[ée]m do 1:1|dar palestras|ser palestrante|palestrar|posicionamento profissional|especializa[çc][ãa]o|me tornar refer[êe]ncia|refer[êe]ncia no mercado|atender empresas'),
  ('encontrar_pares',         'networking|conex[õo]es|\ypares\y|trocar experi[êe]ncias?|troca de experi[êe]ncias?|comunidade|\yjourney\y|grupo de (l[ií]deres|executiv|rh)|conhecer (pessoas|outros|outras)')
) v(codigo, rx)
where intelligence.jtbd.codigo = v.codigo;

-- perfil_evidencias ganha a fonte "memoria_texto" (memórias de conversa e campos de análise)
create or replace function intelligence.perfil_evidencias(p_mind uuid, p_familia text default null)
returns table (codigo text, confianca numeric, evidencia jsonb)
language sql stable
set search_path to 'pg_catalog', 'public', 'intelligence', 'engagement', 'summit_2026', 'credenciamento_summit_2026'
as $fn$
  with base as (
    select * from (
      select distinct on (ci.sessao_id, x.c) x.c as codigo, 0.70::numeric as conf, jsonb_build_object('tipo', 'checkin', 'sessao', se.titulo) as ev
        from credenciamento_summit_2026."Check Ins Summit" ci
        join summit_2026.sessions se on se.id = ci.sessao_id
        cross join lateral unnest(se.jtbd) as x(c)
       where ci.mind_id = p_mind
       order by ci.sessao_id, x.c) a
    union all
    select * from (
      select distinct on (r.sessao_id, x.c) x.c, 0.60::numeric, jsonb_build_object('tipo', 'reserva', 'sessao', se.titulo)
        from credenciamento_summit_2026."Reservas_Agenda_APP" r
        join summit_2026.sessions se on se.id = r.sessao_id
        cross join lateral unnest(se.jtbd) as x(c)
       where r.mind_id = p_mind
         and not exists (select 1 from credenciamento_summit_2026."Check Ins Summit" ci where ci.mind_id = p_mind and ci.sessao_id = r.sessao_id)
       order by r.sessao_id, x.c) b
    union all
    select * from (
      select distinct on (j.codigo, si.chave) j.codigo, (j.sinais->'interesses'->>si.chave)::numeric, jsonb_build_object('tipo', 'interesse', 'chave', si.chave)
        from engagement.agent_sessions ag
        join engagement.session_interests si on si.agent_session_id = ag.id
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->'interesses') ? si.chave
       where ag.mind_id = p_mind
         and (j.sinais->'interesses_familias' is null
              or p_familia in (select jsonb_array_elements_text(j.sinais->'interesses_familias')))
       order by j.codigo, si.chave) c
    union all
    select * from (
      select distinct on (j.codigo, pm.valor->>'code') j.codigo, pm.confianca,
             jsonb_build_object('tipo', 'conversa', 'jt', pm.valor->>'code', 'contexto', left(pm.valor->>'context', 120))
        from intelligence.participante_memoria pm
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (pm.valor->>'code') = any(j.jt_raiz)
        cross join lateral (select j.sinais->'jt_filtro'->(pm.valor->>'code') as f) x
       where pm.mind_id = p_mind and pm.tipo = 'jtbd' and pm.status in ('ativa', 'proposta') and pm.origem <> 'regra_perfil'
         and (x.f->>'contexto_regex' is null or coalesce(pm.valor->>'context', '') ~* (x.f->>'contexto_regex'))
         and (x.f->>'contexto_regex_excluir' is null or coalesce(pm.valor->>'context', '') !~* (x.f->>'contexto_regex_excluir'))
         and (x.f->'familias' is null or p_familia in (select jsonb_array_elements_text(x.f->'familias')))
       order by j.codigo, pm.valor->>'code', pm.confianca desc) d
    union all
    -- o que a pessoa disse em conversa (memórias de texto) casando com o regex de cada job
    select * from (
      select distinct on (j.codigo) j.codigo, 0.60::numeric,
             jsonb_build_object('tipo', 'memoria_texto', 'memoria', pm.tipo, 'texto', left(pm.valor->>'text', 100))
        from intelligence.participante_memoria pm
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->>'memoria_regex') is not null
       where pm.mind_id = p_mind and pm.status in ('ativa', 'proposta')
         and pm.tipo in ('interesse', 'objetivo', 'preferencia_comercial', 'delegacao', 'patrocinio', 'outro')
         and coalesce(pm.valor->>'text', '') ~* (j.sinais->>'memoria_regex')
       order by j.codigo, pm.confianca desc, pm.atualizado_em desc) h
    union all
    -- objetivo / caso de uso / interesses da análise de conversa
    select * from (
      select distinct on (j.codigo) j.codigo, 0.60::numeric,
             jsonb_build_object('tipo', 'memoria_texto', 'memoria', 'analise', 'texto', left(t.txt, 100))
        from intelligence.analise_conversa ac
        cross join lateral (select concat_ws(' · ', ac.dados->>'objective', ac.dados->>'buyer_objective', ac.dados->>'use_case',
                                              case when jsonb_typeof(ac.dados->'interests') = 'array' then (select string_agg(x #>> '{}', ' · ') from jsonb_array_elements(ac.dados->'interests') x) else ac.dados->>'interests' end) as txt) t
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->>'memoria_regex') is not null
       where ac.mind_id = p_mind and t.txt ~* (j.sinais->>'memoria_regex')
       order by j.codigo, ac.analisado_em desc nulls last) i
    union all
    select * from (
      select j.codigo, 0.60::numeric, jsonb_build_object('tipo', 'memoria_patrocinio', 'texto', left(pm.valor->>'text', 120))
        from intelligence.participante_memoria pm
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->>'patrocinio')::boolean
       where pm.mind_id = p_mind and pm.tipo = 'patrocinio' and pm.status in ('ativa', 'proposta')
       order by pm.atualizado_em desc limit 1) e
    union all
    select * from (
      select j.codigo, 0.70::numeric, jsonb_build_object('tipo', 'analise_patrocinio', 'empresa', ac.dados->'sponsorship'->>'company')
        from intelligence.analise_conversa ac
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->>'patrocinio')::boolean
       where ac.mind_id = p_mind and nullif(ac.dados->'sponsorship'->>'company', '') is not null
       order by ac.analisado_em desc nulls last limit 1) f
    union all
    select * from (
      select distinct on (j.codigo) j.codigo, 0.70::numeric, jsonb_build_object('tipo', 'analise_produto', 'produto', left(ac.dados->>'preferred_product_or_offer', 60))
        from intelligence.analise_conversa ac
        join intelligence.jtbd j on j.nivel = 'mind' and j.ativo and (j.sinais->'conversa'->>'preferred_product_regex') is not null
       where ac.mind_id = p_mind and coalesce(ac.dados->>'preferred_product_or_offer', '') ~* (j.sinais->'conversa'->>'preferred_product_regex')
       order by j.codigo, ac.analisado_em desc nulls last) g
  ),
  ctx as (
    select distinct on (j.codigo) j.codigo, (j.sinais->'contextual'->>'confianca')::numeric as conf,
           jsonb_build_object('tipo', 'contexto', 'de', b.codigo, 'familia', p_familia) as ev
      from intelligence.jtbd j
      join base b on b.conf >= 0.60 and b.codigo in (select jsonb_array_elements_text(j.sinais->'contextual'->'de'))
     where j.nivel = 'mind' and j.ativo and j.sinais ? 'contextual'
       and p_familia in (select jsonb_array_elements_text(j.sinais->'contextual'->'familias'))
     order by j.codigo, b.conf desc
  )
  select codigo, conf, ev from base
  union all
  select codigo, conf, ev from ctx;
$fn$;
comment on function intelligence.perfil_evidencias(uuid, text) is 'Uma linha por evidência de JTBD da pessoa (check-in, reserva, interesse da jornada, job-raiz de conversa traduzido, texto de memórias/análises de conversa por regex, patrocínio, produto preferido, contexto por família de ICP). Só leitura; quem grava é perfil_projetar.';
