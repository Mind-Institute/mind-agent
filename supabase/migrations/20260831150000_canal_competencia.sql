-- CANAL DEFINE AS COMPETÊNCIAS POSSÍVEIS. Política de produto, em tabela.
--
-- O PROBLEMA. `mind_rota_capacidade` avalia três dimensões para dizer se uma rota
-- executa. Duas já eram lidas do sistema — playbook de `agentes.prompts`, Kit de
-- `public.mind_kit_meta`. A terceira, o canal, era um `CASE` escrito dentro do corpo
-- da função: para ligar uma competência num canal, editava-se código.
--
-- E o Router decidia cego ao canal. Ele recebia só `conversa_id`, escolhia entre as
-- seis rotas globais, e só depois o Gate descobria que a escolhida não era servida
-- ali. Dois turnos reais morreram assim em 24h — "Quando será o evento?" e "quais
-- palestrantes estarao no summit?" foram para `concierge_summit` no WhatsApp e
-- viraram transferência. Ninguém errou dentro da própria regra; a regra é que não
-- existia como dado.
--
-- A CASA. `agentes.canal_competencia` passa a ser a fonte canônica da fronteira de
-- roteamento por canal. Uma linha por par (canal, rota), com a matriz INTEIRA — as
-- permitidas e as proibidas. Registrar as duas metades tira a ambiguidade entre
-- "ainda não configurado" e "proibido de propósito", e faz o dado espelhar a decisão
-- de produto, que também foi escrita como pode/não pode.
--
-- O QUE ESTA MIGRATION NÃO FAZ. Não substitui o Gate: a tabela responde só "esta
-- rota é legalmente possível neste canal?". Playbook, Kit e as demais condições
-- continuam sendo do Gate, com a mesma precedência
-- (missing_playbook > missing_kit > canal_incompativel).
--
-- Também não mexe na taxonomia de rotas: `rota_valida` segue fechada na função, como
-- sempre esteve. Esta mudança é sobre CANAL, não sobre inventar rota nova.
--
-- EFEITO ESPERADO NO GATE: NENHUM. A matriz semeada é a que o `CASE` já aplicava,
-- com uma exceção deliberada — `cliente_suporte` passa a ser permitido também em
-- `mindagent-web`. E mesmo essa não muda a saída: aquela célula já falhava por
-- `missing_kit`, que tem precedência sobre canal. O Gate continua denunciando a
-- falta de Kit em vez de escondê-la atrás da política de canal.

-- ------------------------------------------------------------------ 1. A CASA
create table if not exists agentes.canal_competencia (
  canal         text        not null,
  rota          text        not null,
  ativo         boolean     not null default true,
  observacao    text,
  atualizado_em timestamptz not null default now(),
  primary key (canal, rota)
);

comment on table agentes.canal_competencia is
  'Fronteira de roteamento por canal: quais competências o Router pode escolher em cada canal. Fonte canônica, lida pelo Router (antes de decidir) e pelo Capability Gate (depois). Não decide QUAL rota — só quais são legalmente possíveis.';

alter table agentes.canal_competencia enable row level security;

-- ------------------------------------------------------------- 2. A POLÍTICA
-- Decisão de produto, fechada. A matriz inteira, explícita nos dois sentidos.
insert into agentes.canal_competencia (canal, rota, ativo, observacao) values
  ('whatsapp',      'summit_b2c',       true,  'Treble é canal de venda: pessoa decidindo por si.'),
  ('whatsapp',      'summit_b2b',       true,  'Treble é canal de venda: empresa, grupo, negociação.'),
  ('whatsapp',      'cliente_suporte',  true,  'Treble atende quem já comprou.'),
  ('whatsapp',      'concierge_summit', false, 'Concierge é experiência de participação, servida no app.'),
  ('whatsapp',      'institute',        false, 'Fora do escopo do canal.'),
  ('whatsapp',      'dash',             false, 'Fora do escopo do canal.'),
  ('mindagent-web', 'concierge_summit', true,  'O app é o concierge do Summit por construção.'),
  ('mindagent-web', 'cliente_suporte',  true,  'O app pode rotear suporte; executar depende de Kit/playbook, e isso é do Gate.'),
  ('mindagent-web', 'summit_b2c',       false, 'O app não vende.'),
  ('mindagent-web', 'summit_b2b',       false, 'O app não vende.'),
  ('mindagent-web', 'institute',        false, 'Fora do escopo do canal.'),
  ('mindagent-web', 'dash',             false, 'Fora do escopo do canal.')
on conflict (canal, rota) do update
   set ativo         = excluded.ativo,
       observacao    = excluded.observacao,
       atualizado_em = now()
 where agentes.canal_competencia.ativo      is distinct from excluded.ativo
    or agentes.canal_competencia.observacao is distinct from excluded.observacao;

-- --------------------------------------------------------- 3. A LEITORA ÚNICA
-- Contrato no padrão do Core: jsonb com `ok`, e `motivo` quando não dá. Canal que
-- não existe na tabela é `canal_invalido` — a mesma palavra que o Gate já usava.
create or replace function public.mind_canal_rotas(p_canal text)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'agentes'
as $function$
  with entrada as (
    select nullif(btrim(p_canal), '') as canal
  ),
  canal_valido as (
    select e.canal
      from entrada e
     where exists (select 1 from agentes.canal_competencia cc where cc.canal = e.canal)
  )
  select case
    when (select count(*) from canal_valido) = 0
      then jsonb_build_object('ok', false, 'motivo', 'canal_invalido')
    else jsonb_build_object(
      'ok',    true,
      'canal', (select canal from canal_valido),
      'rotas', coalesce((
        select jsonb_agg(cc.rota order by cc.rota)
          from agentes.canal_competencia cc
         where cc.canal = (select canal from canal_valido)
           and cc.ativo
      ), '[]'::jsonb))
  end;
$function$;

comment on function public.mind_canal_rotas(text) is
  'Rotas ATIVAS permitidas num canal. Fonte canônica da fronteira de roteamento: o Router filtra por ela antes de decidir, o Gate valida por ela depois.';

revoke all on function public.mind_canal_rotas(text) from public, anon, authenticated;
grant execute on function public.mind_canal_rotas(text) to service_role;

-- ------------------------------------ 4. O GATE PARA DE DUPLICAR A POLÍTICA
-- Idêntico ao anterior, exceto pelos dois CTEs de canal: `canal_valido` deixa de ter
-- a lista fixa de canais e `canal_executa` deixa de ter o CASE. Os dois passam a ler
-- `agentes.canal_competencia`. Precedência, chaves de retorno e todo o resto: iguais.
create or replace function public.mind_rota_capacidade(p_rota text, p_canal text)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'agentes'
as $function$
with entrada as (
  select nullif(btrim(p_rota), '')  as rota,
         nullif(btrim(p_canal), '') as canal
),
-- Taxonomia canonica do Router. Fechada. `ja_comprou` e `desconhecido` nao sao rotas.
rota_valida as (
  select e.rota
    from entrada e
   where e.rota in ('summit_b2c','summit_b2b','institute','dash',
                    'cliente_suporte','concierge_summit')
),
-- Canais canonicos vivos — agora lidos da politica, nao de uma lista fixa aqui.
canal_valido as (
  select e.canal
    from entrada e
   where exists (select 1 from agentes.canal_competencia cc where cc.canal = e.canal)
),
-- PLAYBOOK — lido do sistema, nunca fixo aqui. Disponivel so quando a linha
-- existe, esta ativa e tem conteudo: um playbook vazio nao ensina nada.
playbook as (
  select exists (
    select 1 from agentes.prompts pr, entrada e
     where pr.chave = 'playbook_' || e.rota
       and pr.ativo
       and btrim(coalesce(pr.conteudo, '')) <> ''
  ) as tem
),
-- KIT — a verdade de completude do Kit tem um dono so: public.mind_kit_meta.
-- O Gate le, nao re-deriva.
kit as (
  select coalesce(
           (public.mind_kit_meta((select rota from rota_valida))
              ->> 'kit_disponivel')::boolean,
           false) as tem
),
-- CANAL — "este runtime executa esta rota autonomamente?". Mesma pergunta de antes;
-- a resposta agora vem de agentes.canal_competencia, a mesma fonte que o Router
-- consulta ANTES de decidir. Uma politica, dois pontos de leitura, zero duplicacao.
canal_executa as (
  select exists (
    select 1
      from agentes.canal_competencia cc
     where cc.canal = (select canal from canal_valido)
       and cc.rota  = (select rota  from rota_valida)
       and cc.ativo
  ) as tem
),
-- PRECEDENCIA FECHADA: missing_playbook > missing_kit > canal_incompativel.
-- Um unico reason, nunca uma lista. A ordem nao e arbitraria — ela vai do que
-- falta mais fundo para o que falta mais na ponta, e o primeiro e o unico que
-- uma pessoa destrava escrevendo um texto.
avaliado as (
  select case
           when not (select tem from playbook)      then 'missing_playbook'
           when not (select tem from kit)           then 'missing_kit'
           when not (select tem from canal_executa) then 'canal_incompativel'
         end as reason
)
select case
  when (select count(*) from rota_valida)  = 0 then jsonb_build_object('ok', false, 'motivo', 'rota_invalida')
  when (select count(*) from canal_valido) = 0 then jsonb_build_object('ok', false, 'motivo', 'canal_invalido')
  else jsonb_build_object(
    'ok',    true,
    'rota',  (select rota  from rota_valida),
    'canal', (select canal from canal_valido),
    'pode_executar', (select reason from avaliado) is null,
    -- needs_human e NECESSIDADE, nao mecanismo: "isto nao pode ser concluido
    -- sozinho e precisa de gente". Nao afirma que existe humano alcancavel
    -- neste canal — inclusive em mindagent-web, onde nao ha.
    'needs_human',   (select reason from avaliado) is not null,
    'reason',        (select reason from avaliado))
end;
$function$;

revoke all on function public.mind_rota_capacidade(text, text) from public, anon, authenticated;
grant execute on function public.mind_rota_capacidade(text, text) to service_role;

-- --------------------------------------------------------------- 5. GUARDAS
do $check$
declare v jsonb; n int;
begin
  select count(*) into n from agentes.canal_competencia;
  if n <> 12 then raise exception 'esperadas 12 linhas de politica, encontradas %', n; end if;

  select count(*) into n from agentes.canal_competencia where ativo;
  if n <> 5 then raise exception 'esperadas 5 combinacoes ativas, encontradas %', n; end if;

  v := public.mind_canal_rotas('whatsapp');
  if v <> jsonb_build_object('ok', true, 'canal', 'whatsapp',
        'rotas', '["cliente_suporte","summit_b2b","summit_b2c"]'::jsonb) then
    raise exception 'politica do whatsapp inesperada: %', v;
  end if;

  v := public.mind_canal_rotas('mindagent-web');
  if v <> jsonb_build_object('ok', true, 'canal', 'mindagent-web',
        'rotas', '["cliente_suporte","concierge_summit"]'::jsonb) then
    raise exception 'politica do mindagent-web inesperada: %', v;
  end if;

  if public.mind_canal_rotas('telegram') ->> 'motivo' is distinct from 'canal_invalido' then
    raise exception 'canal inexistente deveria devolver canal_invalido';
  end if;

  -- O Gate nao pode ter mudado nas combinacoes que a politica preserva.
  if (public.mind_rota_capacidade('concierge_summit','whatsapp') ->> 'reason')
     is distinct from 'canal_incompativel' then
    raise exception 'concierge no whatsapp deveria seguir canal_incompativel';
  end if;
  if (public.mind_rota_capacidade('summit_b2c','whatsapp') ->> 'pode_executar') <> 'true' then
    raise exception 'summit_b2c no whatsapp deveria continuar executavel';
  end if;
  -- cliente_suporte virou permitido no app, mas o Gate continua denunciando o Kit.
  if (public.mind_rota_capacidade('cliente_suporte','mindagent-web') ->> 'reason')
     is distinct from 'missing_kit' then
    raise exception 'suporte no app deveria seguir missing_kit, nao mascarado pela politica';
  end if;
end
$check$;

notify pgrst, 'reload schema';
