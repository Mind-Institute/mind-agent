-- O AVISO PASSA A TER CATEGORIA.
--
-- POR QUE AGORA. O handoff de design de 02/09 desenhou a home e a tela de
-- Avisos importantes pintando cada aviso pela categoria: a caixa do ícone
-- ganha a cor, e a tela de avisos ganha chips que filtram por ela. Sem o
-- dado, a cor teria de ser adivinhada a partir do ícone — e ícone não é
-- categoria: `sino` serve para lembrete antes de ir e para alteração no
-- meio do evento.
--
-- AS QUATRO SÃO AS DO DESENHO, e nenhuma é inventada aqui:
--
--   antes_de_ir  verde   preparação: o que resolver antes de sair de casa
--   no_evento    roxo    o que acontece durante, incluindo mudança de sala
--   reservas     laranja vaga limitada — é a categoria que pede ação
--   ingressos    verde   credencial e entrada; sem ponto no chip, por ser
--                        a categoria de serviço
--
-- As três cores já eram tokens da marca (`--verde`, `--roxo`, `--coral`).
-- O design não trouxe paleta nova.
--
-- ADITIVA. Coluna nova numa tabela que já é do Home V3, com `default` —
-- nenhuma linha existente fica inválida, nenhuma função quebra por não
-- conhecê-la, e o app publicado hoje continua ignorando o campo até subir
-- a versão nova. Desfazer é `drop column`.
--
-- O DEFAULT É `antes_de_ir` porque é o estado em que o evento está: um
-- aviso escrito hoje é de preparação. Quem cria pelo painel escolhe numa
-- lista, então o default só decide o palpite inicial do formulário.

alter table concierge.avisos
  add column if not exists categoria text not null default 'antes_de_ir';

-- Lista fechada dos dois lados: o app tem uma cor por categoria e nada
-- para desenhar fora dela.
do $c$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'concierge.avisos'::regclass and conname = 'avisos_categoria_check'
  ) then
    alter table concierge.avisos
      add constraint avisos_categoria_check
      check (categoria in ('antes_de_ir', 'no_evento', 'reservas', 'ingressos'));
  end if;
end $c$;

-- BACKFILL DOS AVISOS VIVOS.
--
-- Por `chave`, não por título: título é texto editável pelo painel e pode
-- ter mudado. `chave` é a identidade estável de quem nasceu no código do
-- app. O `where categoria = 'antes_de_ir'` faz o backfill valer só sobre
-- o que ainda está no default — reexecutar não desfaz classificação que
-- alguém tenha corrigido depois pelo painel.
--
--   traducao  fone     retirar o aparelho exige documento → antes de ir
--   ingresso  ingresso a credencial                       → ingressos
--   sala      lugar    mudança de sala no dia             → no evento
--   abertura  sino     abertura e credenciamento no dia   → no evento
update concierge.avisos set categoria = 'ingressos'
 where chave = 'ingresso' and categoria = 'antes_de_ir';
update concierge.avisos set categoria = 'no_evento'
 where chave in ('sala', 'abertura') and categoria = 'antes_de_ir';
-- `traducao` fica em `antes_de_ir`, que já é o default.

-- ============================================================
-- A PORTA PÚBLICA passa a devolver o campo.
-- ============================================================
-- ESTE CORPO SAIU DO `prosrc` VIVO, NÃO DE `docs/sql/home-v3/06-funcao-publica.sql`.
-- O arquivo em `docs/` está DESATUALIZADO: a função em produção ganhou
-- depois `'geradoEm'`, o filtro de troca arquivada e o `replace(…, 'T', ' ')`
-- que faz o horário da troca ser lido — tudo isso sustenta a programação
-- das telas por data. Reescrever a partir do arquivo teria apagado as três
-- coisas em silêncio, e a home voltaria a não virar sozinha no dia 16.
--
-- A ÚNICA diferença para o que está no ar é a linha `'categoria'`. A ponte
-- em `public` não é tocada: a assinatura não mudou.
create or replace function api.mindagent_home_publico(p_event_slug text default 'mind-summit-2026')
returns jsonb
language sql
stable security definer
set search_path to 'public', 'api', 'concierge', 'summit_2026'
as $function$
with ev as (
  select e.* from summit_2026.events e where e.slug = p_event_slug and e.ativo limit 1
),
cfg as (
  select coalesce(c.valor, '{}'::jsonb) as v from concierge.config c where c.chave = 'home'
)
select jsonb_build_object(
  'geradoEm', now(),

  -- AVISOS EM CIRCULAÇÃO, mais recente em cima.
  --   no-ar     → na rua agora, independente do relógio (disparo imediato)
  --   agendado  → entra sozinho quando `disparo_em` chega
  --   rascunho, encerrado → não saem
  -- A regra é aplicada na leitura: não depende de pg_cron nem de rotina
  -- que possa não rodar às 9h do dia 16.
  'avisos', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', coalesce(a.chave, a.id::text),
      'icone', a.icone,
      'categoria', a.categoria,
      'em', to_char(a.disparo_em at time zone coalesce((select fuso from ev), 'America/Sao_Paulo'),
                    'YYYY-MM-DD"T"HH24:MI'),
      'situacao', a.situacao,
      'titulo', a.titulo,
      'resumo', a.subtitulo,
      'mensagem', a.descricao,
      'verNoApp', a.ver_no_app,
      'botaoVerNoApp', a.botao_ver_no_app
    ) order by a.disparo_em desc nulls last)
    from concierge.avisos a
    where (a.situacao = 'no-ar' or (a.situacao = 'agendado' and a.disparo_em <= now()))
      and (a.event_id is null or a.event_id = (select id from ev))
  ), '[]'::jsonb),

  -- QUAL DAS QUATRO COMPOSIÇÕES está no ar. Em `programado`, vale a
  -- última troca cujo horário já passou — mesma ideia dos avisos.
  'home', coalesce((
    select jsonb_build_object(
      'momento', case
        when v->>'modo' = 'programado' then coalesce((
          select troca->>'momento'
          from jsonb_array_elements(coalesce(v->'trocas', '[]'::jsonb)) troca
          where coalesce((troca->>'arquivada')::boolean, false) is false
            and (replace(troca->>'quando', 'T', ' '))::timestamp
                at time zone coalesce((select fuso from ev), 'America/Sao_Paulo') <= now()
          order by troca->>'quando' desc
          limit 1
        ), v->>'momento', 'antes')
        else coalesce(v->>'momento', 'antes')
      end,
      'modo', coalesce(v->>'modo', 'manual')
    )
    from cfg
  ), jsonb_build_object('momento', 'antes', 'modo', 'manual'))
);
$function$;

do $g$
declare d text; n int; momento text;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'api' and p.proname = 'mindagent_home_publico';

  if position('''categoria'', a.categoria' in d) = 0 then
    raise exception 'a porta publica nao devolve a categoria'; end if;

  -- O QUE NÃO PODIA SAIR JUNTO. As três linhas que o arquivo em `docs/`
  -- não tem e que a programação das telas por data depende.
  if position('''geradoEm''' in d) = 0 then
    raise exception 'geradoEm se perdeu'; end if;
  if position('troca->>''arquivada''' in d) = 0 then
    raise exception 'o filtro de troca arquivada se perdeu'; end if;
  if position('replace(troca->>''quando''' in d) = 0 then
    raise exception 'a leitura do horario da troca se perdeu'; end if;
  if position('a.situacao = ''agendado'' and a.disparo_em <= now()' in d) = 0 then
    raise exception 'a regra de aviso agendado se perdeu'; end if;

  select count(*) into n from concierge.avisos where categoria = 'no_evento';
  if n <> 2 then
    raise exception 'o backfill de no_evento classificou % aviso(s), esperava 2', n; end if;

  -- A porta continua respondendo, e continua dizendo qual tela está no ar.
  select api.mindagent_home_publico() -> 'home' ->> 'momento' into momento;
  if momento is null then
    raise exception 'a porta publica parou de dizer o momento'; end if;
end $g$;
