-- Concierge: sempre lembrar que quem agenda é a pessoa, e oferecer explicar o
-- caminho. Pedido da Adriana em 06/09/2026: "quando falar sobre agendamento
-- sempre fazer aquele lembrete de quem agenda é a pessoa, ele apenas recomenda
-- e daí pode perguntar se a pessoa sabe como agendar ou se gostaria de ver uma
-- demonstração". Ela mesma sinalizou não saber se isso é base de conhecimento
-- ou prompt.
--
-- Estrutura conferida antes de escrever (a mesma casa que já existe, não uma nova):
--   - `summit_2026.event_rules` é exatamente essa casa: fatos operacionais do
--     evento, com `aplica_em`/`prioridade`, que `public.mind_kit_evento` expõe
--     como `regras_criticas` (só `prioridade <= 2`) dentro do Kit do Concierge.
--     Não é prompt solto — é Intelligence, igual ela desconfiava;
--   - já existe conteúdo vizinho: `reserva-workshops-masterclasses` (prioridade
--     1) já manda o Concierge lembrar de agendar e conferir Minha Agenda, mas
--     sem a frase de posse ("quem agenda é a pessoa") nem a pergunta de
--     acompanhamento. `app-menus-e-confirmacao-reserva` (prioridade 100, por
--     isso NUNCA chega ao Kit hoje) já tem o caminho exato dentro do app:
--     Programação → sessão → Reservar → confirma em Minha Agenda;
--   - o "roteiro" com prints de tela e botão destacado (`ROTEIROS.reserva` em
--     app.js, "Lugar reservado") é uma simulação de tela separada — não é o
--     Concierge (que não referencia `mindagent-chat` em lugar nenhum de
--     app.js). Não existe hoje um tour visual "de dentro do Concierge";
--   - por isso "a demonstração" aqui, no Concierge, só pode ser em texto: pedi
--     confirmação da Adriana sobre isso e a pergunta não foi respondida, então
--     seguindo o modo automático seguimos com a leitura mais direta e reversível
--     — explicar o caminho em palavras, reaproveitando o MESMO fato que já está
--     aprovado em `app-menus-e-confirmacao-reserva`, sem inventar conteúdo novo.
--     Se a intenção era um tour visual dedicado ao Concierge, é ajuste à parte.
--
-- Regra nova (não reescreve as duas existentes, que continuam com seus temas
-- próprios): pura adição, prioridade 1 para chegar ao Kit como as outras
-- regras críticas de agendamento.
--
-- Reversível: `update ... set ativo=false where chave=...`.
-- Idempotente: só insere se a chave ainda não existir.

begin;

insert into summit_2026.event_rules (event_id, chave, titulo, texto, aplica_em, prioridade, ativo)
select
  e.id,
  'concierge-oferece-mostrar-como-agendar',
  'Quem agenda é a pessoa',
  'O Concierge recomenda; quem faz a reserva é sempre a própria pessoa, no app. '
  'Sempre que recomendar um conteúdo que exige agendamento, lembre isso antes de '
  'mais nada. Em seguida, pergunte se a pessoa já sabe como agendar ou se quer '
  'que o Concierge explique o caminho: abrir Programação, entrar na sessão '
  'desejada, tocar em Reservar, e depois conferir em Minha Agenda para '
  'confirmar que a reserva foi feita.',
  array['reserva','recomendacao','concierge','workshop','masterclass'],
  1,
  true
from summit_2026.events e
where e.slug = 'mind-summit-2026'
  and e.ativo
  and not exists (
    select 1 from summit_2026.event_rules r
    where r.chave = 'concierge-oferece-mostrar-como-agendar'
  );

-- Prova: a regra existe, está ativa, prioridade 1, e chega mesmo ao Kit do
-- Concierge (mind_kit_evento, sem precisar de conversa real).
do $$
declare v_kit jsonb; v_achou boolean;
begin
  if not exists (
    select 1 from summit_2026.event_rules
    where chave = 'concierge-oferece-mostrar-como-agendar' and ativo and prioridade <= 2
  ) then
    raise exception 'regra não inserida ou fora do alcance do Kit (prioridade > 2)';
  end if;

  v_kit := public.mind_kit_evento(null, null);
  if v_kit is null then raise exception 'mind_kit_evento não devolveu bloco'; end if;

  select exists(
    select 1 from jsonb_array_elements(v_kit->'regras_criticas') r
    where r->>'chave' = 'concierge-oferece-mostrar-como-agendar'
  ) into v_achou;
  if not v_achou then
    raise exception 'regra não chegou em regras_criticas do Kit';
  end if;
end $$;

commit;
