-- ============================================================
-- Avaliação do dia — um link de leitura, sem login
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- O QUE ISTO É
-- Uma porta de leitura das respostas protegida por TOKEN na URL, e não
-- por sessão. Pedida em 16/09 para a equipe ver os resultados no celular
-- sem passar pelo login do painel.
--
-- O QUE ISTO EXPÕE, E POR QUE ISSO PRECISA ESTAR ESCRITO AQUI
-- Tudo: e-mail, profissão e os textos que os participantes escreveram.
-- Quem tiver o link lê. Encaminhar o link é dar acesso, e não há como
-- saber para quem. É uma decisão de produto tomada com o risco na mesa,
-- não um descuido — e é por isso que vem com as quatro travas abaixo.
--
--   1. TOKEN de 32 hex, sorteado. Não se adivinha e não se enumera.
--   2. PRAZO. Vencido, a porta fecha sozinha. Sem ninguém lembrar.
--   3. CONTADOR de acessos e último acesso. Se vazar, dá para ver.
--   4. REVOGAÇÃO num update. O link morre na hora.
--
-- REVOGAR AGORA:
--   update concierge.config set valor = jsonb_set(valor,'{revogado}','true')
--    where chave = 'avaliacao_do_dia_link';
--
-- TROCAR O TOKEN (invalida o antigo e cria outro):
--   update concierge.config
--      set valor = valor || jsonb_build_object(
--            'token', encode(gen_random_bytes(16),'hex'),
--            'revogado', false, 'acessos', 0)
--    where chave = 'avaliacao_do_dia_link';
--
-- ESTENDER O PRAZO:
--   update concierge.config
--      set valor = jsonb_set(valor,'{expira_em}', to_jsonb((now() + interval '7 days')::text))
--    where chave = 'avaliacao_do_dia_link';
--
-- NADA DE EXISTENTE É TOCADO: uma linha nova em `concierge.config` e uma
-- função nova com nome próprio.

insert into concierge.config (chave, valor, descricao)
values (
  'avaliacao_do_dia_link',
  jsonb_build_object(
    'token', encode(gen_random_bytes(16), 'hex'),
    'expira_em', (now() + interval '7 days')::text,
    'revogado', false,
    'acessos', 0,
    'ultimo_acesso', null
  ),
  'Link de leitura das respostas da Avaliação do dia, sem login. EXPÕE e-mail, profissão e textos abertos para quem tiver a URL. Revogar: set revogado=true.'
)
on conflict (chave) do nothing;

-- ------------------------------------------------------------
-- A porta
-- ------------------------------------------------------------
-- `volatile`, e não `stable`, de propósito: ela conta o acesso. Sem o
-- contador não há como perceber que o link virou público.

create or replace function public.mind_avaliacao_do_dia_por_token(
  p_token text,
  p_event_slug text default 'mind-summit-2026'
)
 returns jsonb
 language plpgsql
 volatile security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_cfg jsonb;
  v_evento summit_2026.events%rowtype;
  v_resultado jsonb;
begin
  select c.valor into v_cfg from concierge.config c where c.chave = 'avaliacao_do_dia_link';

  -- Uma recusa só para todos os casos: token errado, revogado e vencido
  -- respondem igual. Distinguir diria a quem está sondando qual das três
  -- portas existe.
  if v_cfg is null
     or coalesce((v_cfg->>'revogado')::boolean, false)
     or coalesce(v_cfg->>'token', '') = ''
     or p_token is null
     or length(p_token) <> 32
     or v_cfg->>'token' <> lower(p_token)
     or (v_cfg->>'expira_em')::timestamptz <= now() then
    return null;
  end if;

  update concierge.config
     set valor = valor
       || jsonb_build_object('acessos', coalesce((valor->>'acessos')::int, 0) + 1)
       || jsonb_build_object('ultimo_acesso', now()::text)
   where chave = 'avaliacao_do_dia_link';

  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then return null; end if;

  select jsonb_build_object(
    'evento', v_evento.nome,
    'geradoEm', to_char(now() at time zone v_evento.fuso, 'DD/MM/YYYY HH24:MI'),
    'expiraEm', to_char(((v_cfg->>'expira_em')::timestamptz) at time zone v_evento.fuso, 'DD/MM/YYYY HH24:MI'),
    'dias', coalesce((
      select jsonb_agg(d order by d.dia)
      from (
        select a.dia,
               count(*) as respondentes,
               round(avg(a.nota_relevancia), 2) as relevancia,
               round(avg(a.nota_programacao), 2) as programacao,
               jsonb_build_object(
                 'mind',  count(*) filter (where a.experiencia = 'mind'),
                 'vip',   count(*) filter (where a.experiencia = 'vip'),
                 'prime', count(*) filter (where a.experiencia = 'prime')) as por_experiencia
        from engagement.avaliacao_do_dia a
        where a.event_id = v_evento.id
        group by a.dia
      ) d
    ), '[]'::jsonb),
    'porAtividade', coalesce((
      select jsonb_agg(jsonb_build_object(
               'titulo', x.titulo, 'dia', x.dia, 'inicio', x.inicio,
               'espaco', x.espaco, 'avaliacoes', x.avaliacoes, 'media', x.media)
             order by x.avaliacoes desc, x.media desc nulls last, x.titulo)
      from (
        select s.titulo, s.dia,
               to_char(s.inicio at time zone v_evento.fuso, 'HH24:MI') as inicio,
               l.nome as espaco,
               count(t.nota) as avaliacoes,
               round(avg(t.nota), 2) as media
        from summit_2026.sessions s
        left join summit_2026.locations l on l.id = s.espaco_id
        left join engagement.avaliacao_do_dia_atividade t on t.sessao_id = s.id
        where s.event_id = v_evento.id
          and s.tipo is distinct from 'credenciamento'
          and s.tipo is distinct from 'intervalo'
          and s.tipo is distinct from 'almoco'
        group by s.id, s.titulo, s.dia, s.inicio, l.nome
      ) x
    ), '[]'::jsonb),
    -- AQUI MORA O DADO PESSOAL: e-mail, profissão e o que a pessoa
    -- escreveu. É o que o link foi pedido para mostrar.
    'respostas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia', r.dia,
               'quando', to_char(r.enviado_em at time zone v_evento.fuso, 'DD/MM HH24:MI'),
               'email', p.email,
               'nome', btrim(coalesce(p.primeiro_nome,'') || ' ' || coalesce(p.sobrenome,'')),
               'experiencia', r.experiencia,
               'profissao', r.profissao,
               'expectativas', r.expectativas,
               'relevancia', r.nota_relevancia,
               'programacao', r.nota_programacao,
               'maisGostou', r.mais_gostou,
               'melhorar', r.melhorar,
               'comentario', r.comentario,
               'atividades', (select count(*) from engagement.avaliacao_do_dia_atividade t
                              where t.avaliacao_id = r.id))
             order by r.enviado_em desc)
      from engagement.avaliacao_do_dia r
      join pessoas.pessoas p on p.id = r.participante_id
      where r.event_id = v_evento.id
    ), '[]'::jsonb)
  ) into v_resultado;

  return v_resultado;
end;
$function$;

comment on function public.mind_avaliacao_do_dia_por_token(text, text) is
  'Respostas da Avaliação do dia para o link sem login. EXPÕE dado pessoal a quem tiver o token. Conta cada acesso. Token errado, revogado ou vencido devolvem NULL, sem distinção.';

revoke execute on function public.mind_avaliacao_do_dia_por_token(text, text) from public;
grant execute on function public.mind_avaliacao_do_dia_por_token(text, text) to service_role;
