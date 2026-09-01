-- ============================================================
-- 02 · api.mindagent_bootstrap ganha `avisos` e `home`
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
-- Depende de: 01-concierge-avisos.sql e 04-visualizacao-home.sql
--
-- A Edge Function `mindagent-bootstrap` é só um proxy: ela chama esta
-- função e devolve o jsonb inteiro. Por isso o app passa a receber
-- avisos e o momento da home SEM deploy de função nenhuma — é este
-- arquivo e mais nada.
--
-- É UM ARQUIVO SÓ para as duas coisas de propósito: dois arquivos
-- fazendo `create or replace` da mesma função significa que o segundo
-- apaga o primeiro. Aqui existe uma definição, e ela é a verdade.
--
-- O corpo abaixo é a v17 em produção, palavra por palavra, com duas
-- chaves novas no fim do jsonb_build_object. Nada mais mudou.
--
-- ATENÇÃO — ESTA FUNÇÃO ESTÁ QUEBRADA EM PRODUÇÃO HOJE, E ESTE ARQUIVO
-- REPRODUZ A QUEBRA DE PROPÓSITO. Ela lê de `summit.*` e `comum.speakers`,
-- schemas que deixaram de existir em 24/08. O endpoint responde 503 desde
-- então, e o app vive do arquivo local. Aplicar este arquivo NÃO conserta
-- isso: acrescenta as duas chaves e mantém o resto como está, para o
-- reparo ser uma decisão separada e visível. Ver 00-LEIA-ANTES.md.
--
-- REGRA DE CIRCULAÇÃO DOS AVISOS
--   no-ar     → está na rua agora, independente do relógio (é o disparo
--               imediato, e é o que o painel liga na mão)
--   agendado  → entra sozinho quando `disparo_em` chega; quem lê aplica
--               a regra, então não depende de pg_cron nem de rotina
--   rascunho  → não sai
--   encerrado → saiu de circulação
--
-- O MOMENTO DA HOME segue a mesma ideia: em `modo = 'programado'`, vale
-- a última troca cujo horário já passou. Sem job, sem cron.
--
-- O app aplica exatamente a mesma regra em `home/estado.js`, para a
-- lista embutida (origem local) se comportar igual à do banco.

create or replace function api.mindagent_bootstrap(p_event_slug text default 'mind-summit-2026'::text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'pg_catalog', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
as $function$
with ev as (
  select e.* from summit.events e where e.slug=p_event_slug and e.ativo limit 1
),
-- Configuração da home: uma linha em `concierge.config`, chave `home`.
cfg as (
  select coalesce(c.valor, '{}'::jsonb) as v
  from concierge.config c where c.chave = 'home'
)
select jsonb_build_object(
  '_meta',jsonb_build_object(
    'schema_version','1.0',
    'event_slug',p_event_slug,
    'generated_at',now()
  ),
  '_nota','Dados oficiais do Supabase. Informações ausentes não devem ser inventadas.',
  'evento',(select jsonb_build_object(
    'nome',e.nome,
    'dias',e.dias,
    'local',e.local,
    'regra_reserva',(select r.texto from summit.event_rules r where r.ativo and r.chave='reserva_expira' and (r.event_id is null or r.event_id=e.id) order by r.event_id nulls last limit 1),
    'regra_vagas',(select r.texto from summit.event_rules r where r.ativo and r.chave='vagas_limitadas' and (r.event_id is null or r.event_id=e.id) order by r.event_id nulls last limit 1)
  ) from ev e),
  'temas',coalesce((
    select jsonb_agg(jsonb_build_object('codigo',t.codigo,'rotulo',t.rotulo) order by t.rotulo)
    from comum.taxonomy t where t.tipo='tema' and t.ativo
  ),'[]'::jsonb),
  'sessoes',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',coalesce(s.yazo_id,s.id::text),
      'dia',s.dia,
      'inicio',to_char(s.inicio at time zone e.fuso,'HH24:MI'),
      'fim',to_char(s.fim at time zone e.fuso,'HH24:MI'),
      'titulo',s.titulo,
      'descricao',coalesce(s.descricao,''),
      'quem',coalesce((
        select string_agg(sp.nome,'; ' order by sp.nome)
        from summit.session_speakers ss join comum.speakers sp on sp.id=ss.palestrante_id
        where ss.sessao_id=s.id
      ),'Em breve'),
      'espaco',l.nome,
      'formato',coalesce(s.tipo,s.formato,'sessao'),
      'etiqueta',coalesce(tt.rotulo,initcap(coalesce(s.tipo,s.formato,'Sessão'))),
      'trilhas',coalesce(s.trilhas,'{}'::text[]),
      'vaga_limitada',coalesce(s.precisa_reserva,false),
      'online',lower(coalesce(s.formato,'')) in ('remoto','online','virtual'),
      'temas',coalesce(s.topicos_aprendizado,'[]'::jsonb)
    ) order by s.inicio,s.titulo)
    from summit.sessions s
    join ev e on e.id=s.event_id
    left join summit.locations l on l.id=s.espaco_id
    left join comum.taxonomy tt on tt.tipo='tipo_sessao' and tt.codigo=s.tipo and tt.ativo
  ),'[]'::jsonb),
  'pessoas',coalesce((
    select jsonb_agg(jsonb_build_object(
      'nome',sp.nome,
      'credencial',concat_ws(' · ',nullif(sp.cargo,''),nullif(sp.organizacao,'')),
      'resumo',coalesce(sp.bio,''),
      'foto',sp.asset_path,
      'destaque',sp.destaque,
      'na_grade',exists(
        select 1 from summit.session_speakers ss
        join summit.sessions sx on sx.id=ss.sessao_id
        join ev e on e.id=sx.event_id
        where ss.palestrante_id=sp.id
      ),
      'temas',sp.temas
    ) order by sp.destaque desc,sp.nome)
    from comum.speakers sp
    where exists(
      select 1 from summit.session_speakers ss
      join summit.sessions sx on sx.id=ss.sessao_id
      join ev e on e.id=sx.event_id
      where ss.palestrante_id=sp.id
    )
  ),'[]'::jsonb),
  -- NOVO: os avisos em circulação, mais recente em cima. A chave existir
  -- já diz ao app que o banco responde por avisos — lista vazia é uma
  -- resposta legítima, e o app respeita.
  'avisos',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',coalesce(a.chave,a.id::text),
      'icone',a.icone,
      'em',to_char(a.disparo_em at time zone coalesce((select fuso from ev),'America/Sao_Paulo'),'YYYY-MM-DD"T"HH24:MI'),
      'situacao',a.situacao,
      'titulo',a.titulo,
      'resumo',a.subtitulo,
      'mensagem',a.descricao,
      'verNoApp',a.ver_no_app,
      'botaoVerNoApp',a.botao_ver_no_app
    ) order by a.disparo_em desc nulls last)
    from concierge.avisos a
    where (a.situacao='no-ar' or (a.situacao='agendado' and a.disparo_em<=now()))
      and (a.event_id is null or a.event_id=(select id from ev))
  ),'[]'::jsonb),
  -- NOVO: qual das quatro composições da home está no ar.
  --
  -- Em `manual`, vale o que o painel deixou marcado. Em `programado`,
  -- vale a última troca cujo horário já passou — a regra é aplicada na
  -- leitura, então às 7h do dia 16 a home vira sozinha sem job nenhum.
  'home',(
    select jsonb_build_object(
      'momento', case
        when v->>'modo' = 'programado' then coalesce((
          select troca->>'momento'
          from jsonb_array_elements(coalesce(v->'trocas','[]'::jsonb)) troca
          where coalesce((troca->>'arquivada')::boolean, false) is false
            and (replace(troca->>'quando','T',' '))::timestamp
                at time zone coalesce((select fuso from ev),'America/Sao_Paulo') <= now()
          order by troca->>'quando' desc
          limit 1
        ), v->>'momento', 'antes')
        else coalesce(v->>'momento','antes')
      end,
      'modo', coalesce(v->>'modo','manual')
    )
    from cfg
  )
);
$function$;
