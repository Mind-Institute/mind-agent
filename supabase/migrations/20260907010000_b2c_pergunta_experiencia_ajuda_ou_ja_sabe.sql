-- Playbook B2C: a escolha entre Mind e VIP passa a começar por uma pergunta explícita
-- ("já sabe ou quer ajuda?") em vez de despejar a lógica de decisão em quem ainda não
-- disse o que busca. Decisão e roteiro da Adriana em 07/09/2026, depois de medir em
-- produção que o vendedor raramente perguntava antes de recomendar.
--
-- Dois lugares mudam, pelo mesmo motivo:
--   seção 3  (QUANDO A ESCOLHA AINDA ESTÁ ABERTA) — fluxo orgânico, fora da oferta;
--   seção 18 (ABERTURA PELA OFERTA)               — quem chega pedindo a condição.
--
-- A pergunta, quando cabe, é sempre a mesma dupla:
--   1. importância dos workshops (aprendizagem prática em temas específicos, com
--      certificação, para o dia a dia do trabalho);
--   2. importância das gravações das Arenas (Mind, LinkedIn, Sextante).
-- Nenhuma das duas relevante ou só secundária -> Mind. Qualquer uma importa de
-- verdade -> VIP. A profissão continua como pista para avaliar a relevância real dos
-- workshops (conteúdo já aprovado; clínica não tira o melhor proveito do formato),
-- não mais como a pergunta em si.
--
-- Toda comparação Mind x VIP passa a lembrar que a diferença de parcela (12x) é de
-- poucos reais por mês — reduz o peso do preço como objeção entre as duas.
--
-- Não existe hoje, na base de conhecimento, um documento de ICP dizendo qual perfil
-- profissional se beneficia mais de quais workshops especificamente. O prompt não
-- inventa essa camada: instrui a buscar os temas reais (a ferramenta de busca já
-- existe no Kit B2C) em vez de generalizar. Fica registrado para quando esse
-- conteúdo existir e puder virar knowledge_documents.
--
-- Travado pelo md5 da versão vigente; idempotente (não reaplica quando a versão já
-- subiu). Só toca `playbook_summit_b2c`.

begin;

do $$
declare
  v_txt text;
begin
  select conteudo into v_txt from agentes.prompts where chave = 'playbook_summit_b2c' and ativo;
  if v_txt is null then raise exception 'playbook_summit_b2c ausente'; end if;

  if (select versao from agentes.prompts where chave = 'playbook_summit_b2c' and ativo) >= 9 then
    raise notice 'playbook_summit_b2c já em v9 ou superior; nada a fazer';
  else
    if md5(v_txt) <> 'c154daa9098645fc120dbbf33a3d0670' then
      raise exception 'playbook_summit_b2c v8 divergente do esperado (md5 %)', md5(v_txt);
    end if;

    ---------------------------------------------------------------- seção 3
    if (select count(*) from regexp_matches(
      v_txt,
      'PROFISSÃO COMO CRITÉRIO' || E'\n\n' ||
      'Quando a dúvida for entre Mind e VIP e ainda não der para recomendar, pergunte o que a pessoa faz\. Uma pergunta só, embutida na conversa: "Se você me contar o que você faz, eu te ajudo a ver se os workshops fazem sentido pra você\."' || E'\n\n' ||
      'Os workshops do VIP são treinamentos de duas horas com certificação, voltados à prática profissional em organizações: liderança, times, RH, consultoria\. Quem atua na clínica, por exemplo, não tem nos workshops o melhor uso do investimento; para essa pessoa o Mind costuma servir melhor, porque as palestras dão o contexto de burnout, segurança psicológica, economia do bem-estar e intervenções baseadas em ciência que ajuda no atendimento de executivos e de adultos que trabalham\.' || E'\n\n' ||
      'Descreva cada experiência com o que a Intelligence traz\. Não invente conteúdo de workshop nem de palestra\.'
    )) <> 1 then
      raise exception 'âncora da seção 3 (profissão como critério) não é única';
    end if;

    v_txt := replace(v_txt,
      $t$PROFISSÃO COMO CRITÉRIO

Quando a dúvida for entre Mind e VIP e ainda não der para recomendar, pergunte o que a pessoa faz. Uma pergunta só, embutida na conversa: "Se você me contar o que você faz, eu te ajudo a ver se os workshops fazem sentido pra você."

Os workshops do VIP são treinamentos de duas horas com certificação, voltados à prática profissional em organizações: liderança, times, RH, consultoria. Quem atua na clínica, por exemplo, não tem nos workshops o melhor uso do investimento; para essa pessoa o Mind costuma servir melhor, porque as palestras dão o contexto de burnout, segurança psicológica, economia do bem-estar e intervenções baseadas em ciência que ajuda no atendimento de executivos e de adultos que trabalham.

Descreva cada experiência com o que a Intelligence traz. Não invente conteúdo de workshop nem de palestra.$t$,
      $t$MIND OU VIP: DUAS PERGUNTAS DECIDEM

Quando a dúvida for entre Mind e VIP, pergunte primeiro se ela já sabe o que quer ou prefere ajuda para escolher. Se ela quiser ajuda, faça duas perguntas curtas, uma de cada vez, embutidas na conversa — nunca como formulário:
1. Quanto pesa pra ela ter os workshops — aprendizagem prática em temas específicos, com certificação, pra levar pro dia a dia do trabalho?
2. Quanto pesa ter as gravações das Arenas (Mind, LinkedIn e Sextante) depois do evento?

O que a pessoa conta sobre o que faz ajuda a avaliar a relevância real dos workshops: eles são treinamentos de duas horas com certificação, voltados à prática profissional em organizações (liderança, times, RH, consultoria). Quem atua na clínica, por exemplo, raramente tem ali o melhor uso do investimento — para essa pessoa o Mind costuma servir melhor, porque as palestras já dão o contexto de burnout, segurança psicológica, economia do bem-estar e intervenções baseadas em ciência.

RECOMENDAÇÃO, com o que ela respondeu:
- as duas coisas irrelevantes ou secundárias pra ela: Mind;
- qualquer uma das duas importa de verdade: VIP.

Ao comparar Mind e VIP, sempre situe a diferença pelo que ela pesa no mês: a parcela (12x) de um é poucos reais maior que a do outro. Use os valores de parcela que a Intelligence trouxer — nunca um número aproximado ou lembrado.

Descreva cada experiência com o que a Intelligence traz. Não invente conteúdo de workshop nem de palestra.$t$
    );

    ---------------------------------------------------------------- seção 18, preâmbulo
    if (select count(*) from regexp_matches(
      v_txt, 'NÃO comece perguntando qual ingresso a pessoa quer\.'
    )) <> 1 then
      raise exception 'âncora do preâmbulo da seção 18 não é única';
    end if;

    v_txt := replace(v_txt,
      $t$NÃO comece perguntando qual ingresso a pessoa quer.
NÃO apresente o Summit do zero.
NÃO faça discovery antes de responder à oferta.$t$,
      $t$NÃO apresente o Summit do zero.
NÃO despeje a lógica de Mind x VIP em quem ainda não disse se já sabe o que quer — pergunte primeiro.
NÃO faça discovery espontâneo com quem já souber a experiência: só pergunte para quem pedir ajuda para escolher.$t$
    );

    if (select count(*) from regexp_matches(
      v_txt, 'Responda em UMA mensagem, nesta ordem:'
    )) <> 1 then
      raise exception 'âncora "responda em uma mensagem" não é única';
    end if;
    v_txt := replace(v_txt,
      'Responda em UMA mensagem, nesta ordem:',
      'Siga esta ordem — numa só mensagem quando a pessoa já souber o que quer, ou começando pelo passo 2 quando ela pedir ajuda para escolher:'
    );

    ---------------------------------------------------------------- seção 18, passo 2
    if (select count(*) from regexp_matches(
      v_txt,
      '2\. COMO EU ORIENTO' || E'\n' ||
      'Explique a lógica de escolha, sem catálogo:' || E'\n' ||
      '- quer os workshops \(treinamentos de duas horas com certificação, para levar o conteúdo à prática profissional\) ou faz diferença ter as gravações das palestras por 90 dias: VIP;' || E'\n' ||
      '- quer assistir às palestras, sem workshops, e as gravações pesam menos: Mind;' || E'\n' ||
      '- quer as seis horas de aulas com os fundadores de burnout, segurança psicológica, economia do bem-estar, intervenções e felicidade baseadas em ciência: Prime\.' || E'\n' ||
      'Descreva cada experiência apenas com o que a Intelligence traz\. Benefício que a Intelligence não confirma não entra\.'
    )) <> 1 then
      raise exception 'âncora do passo 2 da seção 18 não é única';
    end if;

    v_txt := replace(v_txt,
      $t$2. COMO EU ORIENTO
Explique a lógica de escolha, sem catálogo:
- quer os workshops (treinamentos de duas horas com certificação, para levar o conteúdo à prática profissional) ou faz diferença ter as gravações das palestras por 90 dias: VIP;
- quer assistir às palestras, sem workshops, e as gravações pesam menos: Mind;
- quer as seis horas de aulas com os fundadores de burnout, segurança psicológica, economia do bem-estar, intervenções e felicidade baseadas em ciência: Prime.
Descreva cada experiência apenas com o que a Intelligence traz. Benefício que a Intelligence não confirma não entra.$t$,
      $t$2. VOCÊ JÁ SABE OU QUER AJUDA PARA ESCOLHER?
Se a pessoa já disse a experiência (Mind, VIP, Prime) ou descreveu com clareza o que busca, pule para o passo 4 com a condição dela.

Se não, pergunte com uma frase curta e natural: "Você já sabe qual experiência quer, ou prefere que eu te ajude a escolher?"

Quem pedir ajuda, faça DUAS perguntas curtas, uma de cada vez, nunca como formulário:
1. Quanto pesa pra ela ter os workshops — aprendizagem prática em temas específicos, com certificação, pra levar pro dia a dia do trabalho?
2. Quanto pesa ter as gravações das Arenas (Mind, LinkedIn e Sextante) depois do evento?

Use o que ela contar sobre o que faz e o problema que quer resolver para avaliar a relevância real dos workshops disponíveis — busque os temas atuais quando isso ajudar a responder com precisão, em vez de generalizar. Nunca invente tema de workshop nem de palestra.

RECOMENDAÇÃO, com o que ela respondeu:
- as duas coisas irrelevantes ou secundárias pra ela: Mind;
- qualquer uma das duas importa de verdade: VIP;
- quer as seis horas de aulas com os fundadores de burnout, segurança psicológica, economia do bem-estar, intervenções e felicidade baseadas em ciência: Prime.

Ao comparar Mind e VIP, sempre situe a diferença pelo que ela pesa no mês: a parcela (12x) de um é poucos reais maior que a do outro. Use os valores de parcela que a Intelligence trouxer — nunca um número aproximado ou lembrado.

Descreva cada experiência apenas com o que a Intelligence traz. Benefício que a Intelligence não confirma não entra.$t$
    );

    update agentes.prompts
       set conteudo = v_txt, versao = 9, atualizado_em = now()
     where chave = 'playbook_summit_b2c' and ativo;
  end if;
end $$;

-- Prova: versão subiu e as duas seções novas existem, as antigas não sobraram.
do $$
declare
  v_txt text;
begin
  select conteudo into v_txt from agentes.prompts where chave = 'playbook_summit_b2c' and ativo;
  if (select versao from agentes.prompts where chave = 'playbook_summit_b2c' and ativo) < 9 then
    raise exception 'b2c não subiu para v9';
  end if;
  if v_txt !~ 'MIND OU VIP: DUAS PERGUNTAS DECIDEM' then
    raise exception 'seção 3 nova ausente';
  end if;
  if v_txt ~ 'PROFISSÃO COMO CRITÉRIO' then
    raise exception 'seção 3 antiga ainda presente';
  end if;
  if v_txt !~ '2\. VOCÊ JÁ SABE OU QUER AJUDA PARA ESCOLHER\?' then
    raise exception 'passo 2 novo da seção 18 ausente';
  end if;
  if v_txt ~ '2\. COMO EU ORIENTO' then
    raise exception 'passo 2 antigo da seção 18 ainda presente';
  end if;
  if v_txt !~ 'a parcela \(12x\) de um é poucos reais maior que a do outro' then
    raise exception 'lembrete de parcela ausente';
  end if;
  if (select length(v_txt) from agentes.prompts where chave='playbook_summit_b2c' and ativo) >= 22000 then
    raise exception 'prompt B2C cresceu demais: % caracteres', length(v_txt);
  end if;
end $$;

commit;
