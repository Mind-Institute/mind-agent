-- ============================================================
-- Avaliação do dia — o relatório passa a mostrar o e-mail
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- `create or replace` numa função criada hoje por este mesmo trabalho.
-- Nenhuma tabela, coluna ou permissão muda; só o que a função devolve.
--
-- POR QUE ISTO NÃO CONTRARIA A REGRA DO PAINEL
-- `admin/src/components/admin/dado-pessoal.tsx` mascara e-mail em toda
-- tela, e o comentário dele diz o porquê: "ver o dado inteiro é decisão
-- de backend, com registro em auditoria". Esta é a decisão de backend —
-- tomada para UM relatório, o da Avaliação do dia, que já exige sessão
-- de administrador e papel válido em `mind_admin_users`.
--
-- E o motivo é operacional: o relatório existe para agir sobre o que a
-- pessoa escreveu. "Muita fila para tudo" sem saber quem escreveu não
-- dá para responder. Um e-mail mascarado aqui atenderia a forma da
-- regra e não a razão dela.
--
-- O QUE CONTINUA VALENDO
-- - A rota é `/admin/respostas`: sem sessão de administrador, 401/403.
-- - O log não recebe resposta aberta, e-mail nem nome — nem no erro.
-- - Nada disso vale para o app do participante, que não tem esta rota.

create or replace function public.mind_avaliacao_do_dia_respostas(
  p_event_slug text default 'mind-summit-2026',
  p_dia date default null,
  p_experiencia text default null,
  p_sessao_id uuid default null,
  p_pagina int default 1,
  p_por_pagina int default 50
)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_evento summit_2026.events%rowtype;
  v_exp text := nullif(lower(btrim(coalesce(p_experiencia, ''))), '');
  v_pagina int := greatest(1, coalesce(p_pagina, 1));
  v_por int := least(500, greatest(1, coalesce(p_por_pagina, 50)));
  v_total bigint;
  v_itens jsonb;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;
  if v_exp is not null and v_exp not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;

  -- Filtrar por atividade estreita as RESPOSTAS a quem avaliou aquela
  -- atividade. `exists` e não join: join traria a resposta uma vez por
  -- nota, e a mesma pessoa apareceria repetida na lista e na contagem.
  select count(*) into v_total
  from engagement.avaliacao_do_dia a
  where a.event_id = v_evento.id
    and (p_dia is null or a.dia = p_dia)
    and (v_exp is null or a.experiencia = v_exp)
    and (p_sessao_id is null or exists (
      select 1 from engagement.avaliacao_do_dia_atividade at
      where at.avaliacao_id = a.id and at.sessao_id = p_sessao_id));

  select coalesce(jsonb_agg(x order by ordem), '[]'::jsonb) into v_itens
  from (
    select jsonb_build_object(
      'id', a.id,
      'dia', a.dia,
      'enviadoEm', a.enviado_em,
      -- O e-mail e o nome vêm da pessoa canônica, por `participante_id`.
      -- `left join`: resposta de quem ainda não tem e-mail no cadastro
      -- continua aparecendo, com o campo nulo — sumir com a linha seria
      -- pior que mostrá-la sem contato.
      'email', p.email,
      'nome', nullif(btrim(coalesce(p.primeiro_nome, '') || ' ' || coalesce(p.sobrenome, '')), ''),
      'experiencia', a.experiencia,
      'profissao', a.profissao,
      'expectativas', a.expectativas,
      'notaRelevancia', a.nota_relevancia,
      'notaProgramacao', a.nota_programacao,
      'maisGostou', a.mais_gostou,
      'melhorar', a.melhorar,
      'comentario', a.comentario,
      'atividadesAvaliadas', (
        select count(*) from engagement.avaliacao_do_dia_atividade at
        where at.avaliacao_id = a.id)
    ) as x,
    row_number() over (order by a.enviado_em desc, a.id) as ordem
    from engagement.avaliacao_do_dia a
    left join pessoas.pessoas p on p.id = a.participante_id
    where a.event_id = v_evento.id
      and (p_dia is null or a.dia = p_dia)
      and (v_exp is null or a.experiencia = v_exp)
      and (p_sessao_id is null or exists (
        select 1 from engagement.avaliacao_do_dia_atividade at
        where at.avaliacao_id = a.id and at.sessao_id = p_sessao_id))
    order by a.enviado_em desc, a.id
    offset (v_pagina - 1) * v_por
    limit v_por
  ) pagina;

  return jsonb_build_object('total', v_total, 'pagina', v_pagina,
                            'porPagina', v_por, 'itens', v_itens);
end;
$function$;

comment on function public.mind_avaliacao_do_dia_respostas(text, date, text, uuid, int, int) is
  'Respostas da Avaliação do dia, paginadas, com as perguntas abertas, o nome e o e-mail de quem respondeu. Restrita ao painel administrativo — a rota exige sessão de administrador.';
