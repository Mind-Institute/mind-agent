-- OS MENUS DO APP E O LEMBRETE DE AGENDAR. Verdade canônica fechada DEPOIS do deploy da
-- v1.9.0 e já registrada na Intelligence — `summit_2026.knowledge_documents`, documento
-- "Menus do app, Programação, Minha Agenda e reservas".
--
-- O fato mora lá e continua lá. O que falta é CONDUTA, e conduta mora no playbook:
--
--   PLAYBOOK DECIDE COMO PENSAR. INTELLIGENCE INFORMA O QUE É VERDADE AGORA.
--
-- Por isso isto não entra no `base` (que é transversal a todas as rotas e canais, e o
-- WhatsApp não tem app nem Minha Agenda) nem vira um segundo catálogo de fatos aqui.
-- Entram duas coisas que são comportamento do Concierge:
--
--   1) o VOCABULÁRIO — o menu da programação chama-se `Programação`; chamá-lo de "Agenda"
--      manda a pessoa para o lugar errado, porque `Minha Agenda` é outro menu, com outro
--      conteúdo (só o que ela efetivamente reservou);
--   2) o FECHAMENTO OBRIGATÓRIO — recomendar conteúdo que exige reserva sem lembrar de
--      agendar produz o pior resultado possível: a pessoa sai da conversa achando que tem
--      lugar garantido e descobre na porta que não tem.
--
-- A seção 2 já era a casa disto ("AGENDA E JORNADA PESSOAL") e já dizia o mais difícil —
-- não fingir que lê a agenda da pessoa. As linhas novas se somam a ela; nenhuma linha
-- existente é removida ou reescrita.
--
-- Emendas ancoradas em duas âncoras conferidas como únicas no conteúdo vivo, e o bloco
-- inteiro é idempotente: se as linhas novas já estiverem lá, não faz nada.

do $emenda$
declare
  v_conteudo text;
  v_ancora_menus  constant text := '2. AGENDA E JORNADA PESSOAL' || chr(10) || '- Você NÃO tem uma fonte sistêmica';
  v_ancora_fim    constant text := '- Não pergunte de novo o que a conversa já deixou claro.';
  v_linha_menus   constant text :=
    '2. AGENDA E JORNADA PESSOAL' || chr(10) ||
    '- Os menus do app são: Concierge (esta conversa), Programação (a programação completa do evento), Minha Agenda (somente o que a pessoa efetivamente reservou/agendou) e Ingresso (o QR Code). O menu da programação chama-se Programação — nunca o chame de "Agenda", porque "Minha Agenda" é outro menu, com outro conteúdo.' || chr(10) ||
    '- Você NÃO tem uma fonte sistêmica';
  v_linhas_reserva constant text :=
    '- Não pergunte de novo o que a conversa já deixou claro.' || chr(10) ||
    '- SEMPRE que recomendar um conteúdo que exige agendamento — Arena LinkedIn, Arena Sextante, workshop ou Masterclass —, feche lembrando a pessoa de agendar no app e de conferir depois em Minha Agenda se a reserva apareceu. Isso não é opcional e não depende de ela perguntar.' || chr(10) ||
    '- A regra para saber se está garantido é simples: se não está em Minha Agenda, não está agendado. Use exatamente isso quando a pessoa estiver em dúvida se conseguiu reservar.' || chr(10) ||
    '- Arena Mind é a exceção: não exige reserva para acesso. Nunca diga que é preciso reservar a Arena Mind.';
begin
  select conteudo into v_conteudo from agentes.prompts where chave = 'playbook_concierge_summit';
  if v_conteudo is null then
    raise exception 'playbook_concierge_summit nao existe';
  end if;

  -- Já aplicado? Sai sem tocar em nada.
  if position('nunca o chame de "Agenda"' in v_conteudo) > 0
     and position('se não está em Minha Agenda, não está agendado' in v_conteudo) > 0 then
    raise notice 'emenda de menus/reserva ja aplicada; nada a fazer';
    return;
  end if;

  if position(v_ancora_menus in v_conteudo) = 0 then
    raise exception 'ancora dos menus nao encontrada: a secao 2 mudou de forma';
  end if;
  if position(v_ancora_fim in v_conteudo) = 0 then
    raise exception 'ancora do fim da secao 2 nao encontrada: a secao 2 mudou de forma';
  end if;

  v_conteudo := replace(v_conteudo, v_ancora_menus,  v_linha_menus);
  v_conteudo := replace(v_conteudo, v_ancora_fim,    v_linhas_reserva);

  update agentes.prompts set conteudo = v_conteudo where chave = 'playbook_concierge_summit';
end $emenda$;

do $g$
declare c text;
begin
  select conteudo into c from agentes.prompts where chave = 'playbook_concierge_summit';

  -- O que entrou.
  if position('Programação (a programação completa do evento)' in c) = 0 then
    raise exception 'o menu Programacao nao entrou no playbook'; end if;
  if position('nunca o chame de "Agenda"' in c) = 0 then
    raise exception 'a proibicao de chamar Programacao de Agenda nao entrou'; end if;
  if position('feche lembrando a pessoa de agendar no app' in c) = 0 then
    raise exception 'o lembrete obrigatorio de agendamento nao entrou'; end if;
  if position('se não está em Minha Agenda, não está agendado' in c) = 0 then
    raise exception 'a regra de conferencia em Minha Agenda nao entrou'; end if;
  if position('Nunca diga que é preciso reservar a Arena Mind' in c) = 0 then
    raise exception 'a excecao da Arena Mind nao entrou'; end if;

  -- O que NÃO podia sair: a conduta que já existia na seção 2.
  if position('Você NÃO tem uma fonte sistêmica da Minha Agenda' in c) = 0 then
    raise exception 'a regra de nao fingir leitura da agenda se perdeu'; end if;
  if position('Não pergunte de novo o que a conversa já deixou claro.' in c) = 0 then
    raise exception 'a ultima linha original da secao 2 se perdeu'; end if;
  if position('3. COMO VOCÊ USA A INTELLIGENCE' in c) = 0 then
    raise exception 'a secao 3 se perdeu'; end if;
end $g$;
