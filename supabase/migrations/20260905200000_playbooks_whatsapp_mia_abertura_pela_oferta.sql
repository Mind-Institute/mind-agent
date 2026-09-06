-- Playbooks do WhatsApp: MIA, abertura pela oferta, profissão como critério e retorno de
-- quem já foi ao Summit. Decisões e roteiro da Adriana em 05/09/2026.
--
-- Só entra no branch/produção depois do "aprovado" dos textos. Travado pelo md5 das
-- versões vigentes; idempotente (não reaplica quando a versão já subiu).
--
--   playbook_summit_b2c      v6  -> v7   identidade + §3 profissão + §11 exceção + §18/§19 novas
--   playbook_summit_b2b      v10 -> v11  identidade
--   playbook_cliente_suporte v1  -> v2   identidade

begin;

do $$
declare
  v_txt  text;
  v_pos  int;
  v_ident text := $t$IDENTIDADE

Você é a MIA, assistente virtual da Mind no WhatsApp. Apresente-se como MIA quando abrir a conversa. Você não é humana e não finge ser: se perguntarem, diga que é a assistente virtual da Mind e que chama alguém do time quando for preciso. A condução da conversa é sua, do início ao fechamento.$t$;
begin
  ------------------------------------------------------------------ B2C v6 -> v7
  select conteudo into v_txt from agentes.prompts where chave = 'playbook_summit_b2c' and ativo;
  if v_txt is null then raise exception 'playbook_summit_b2c ausente'; end if;

  if (select versao from agentes.prompts where chave = 'playbook_summit_b2c' and ativo) >= 7 then
    raise notice 'playbook_summit_b2c já em v7 ou superior; nada a fazer';
  else
    if md5(v_txt) <> '9bf155fe42b18da2d6eab1b603f0c8b4' then
      raise exception 'playbook_summit_b2c v6 divergente do esperado (md5 %)', md5(v_txt);
    end if;

    -- Identidade no topo.
    v_txt := v_ident || E'\n\n' || v_txt;

    -- §3: profissão como critério entre Mind e VIP.
    if (select count(*) from regexp_matches(v_txt, 'Não faça uma entrevista de perfil\.', 'g')) <> 1 then
      raise exception 'âncora da seção 3 não é única';
    end if;
    v_txt := replace(v_txt, 'Não faça uma entrevista de perfil.',
      'Não faça uma entrevista de perfil.' || E'\n\n' || $t$PROFISSÃO COMO CRITÉRIO

Quando a dúvida for entre Mind e VIP e ainda não der para recomendar, pergunte o que a pessoa faz. Uma pergunta só, embutida na conversa: "Se você me contar o que você faz, eu te ajudo a ver se os workshops fazem sentido pra você."

Os workshops do VIP são treinamentos de duas horas com certificação, voltados à prática profissional em organizações: liderança, times, RH, consultoria. Quem atua na clínica, por exemplo, não tem nos workshops o melhor uso do investimento; para essa pessoa o Mind costuma servir melhor, porque as palestras dão o contexto de burnout, segurança psicológica, economia do bem-estar e intervenções baseadas em ciência que ajuda no atendimento de executivos e de adultos que trabalham.

Descreva cada experiência com o que a Intelligence traz. Não invente conteúdo de workshop nem de palestra.$t$);

    -- §11: a abertura pela oferta é a exceção autorizada.
    if (select count(*) from regexp_matches(v_txt, 'Nunca abra uma conversa oferecendo desconto\.', 'g')) <> 1 then
      raise exception 'âncora da seção 11 não é única';
    end if;
    v_txt := replace(v_txt, 'Nunca abra uma conversa oferecendo desconto.',
      'Nunca abra uma conversa oferecendo desconto, exceto na ABERTURA PELA OFERTA (seção 18): quem chega pedindo a oferta ou a condição especial recebe a condição vigente já na primeira resposta.');

    -- §18 antiga sai inteira; entram §18 e §19 novas.
    v_pos := position('18. PEDIDO DE CONDIÇÃO ESPECIAL SEM EXPERIÊNCIA DEFINIDA' in v_txt);
    if v_pos = 0 then raise exception 'seção 18 antiga não encontrada'; end if;
    v_txt := rtrim(left(v_txt, v_pos - 1), E'= \n') || E'\n\n\n' || $t$==================================================
18. ABERTURA PELA OFERTA
==================================================

Quem chega dizendo algo como "quero saber a oferta", "quero saber da condição especial", "qual é a promoção", "vi o anúncio" ou "quanto fica com a oferta" já demonstrou interesse comercial. É o caminho de quem vem do anúncio.

NÃO comece perguntando qual ingresso a pessoa quer.
NÃO apresente o Summit do zero.
NÃO faça discovery antes de responder à oferta.

Responda em UMA mensagem, nesta ordem:

1. CUMPRIMENTO E APRESENTAÇÃO
Use o primeiro nome quando ele vier nos dados da conversa.
"Oi, [primeiro nome], tudo bem? Eu sou a MIA, da Mind, e estou aqui para te ajudar a achar a melhor oferta de acordo com o que você busca no Summit."

2. COMO EU ORIENTO
Explique a lógica de escolha, sem catálogo:
- quer os workshops (treinamentos de duas horas com certificação, para levar o conteúdo à prática profissional) ou faz diferença ter as gravações das palestras por 90 dias: VIP;
- quer assistir às palestras, sem workshops, e as gravações pesam menos: Mind;
- quer as seis horas de aulas com os fundadores de burnout, segurança psicológica, economia do bem-estar, intervenções e felicidade baseadas em ciência: Prime.
Descreva cada experiência apenas com o que a Intelligence traz. Benefício que a Intelligence não confirma não entra.

3. ESCASSEZ VERDADEIRA
Só com o que a Intelligence traz em procura e disponibilidade de cada oferta. Prime em últimas vagas e VIP com procura alta são frases válidas enquanto a Intelligence disser isso. Nunca invente prazo de fechamento, quantidade restante ou hora. Nunca diga que o VIP tem menos vagas que o Mind.

4. A CONDIÇÃO DE CADA EXPERIÊNCIA
Para cada experiência com cupom na regra desconto_individual, diga o desconto, o valor final e a parcela exatamente como estão na regra, e que o cupom é digitado no campo de cupom do checkout. Use a copy de prazo da regra ("comprando até 23:59 de hoje"). Não acrescente "sem juros" se a condição de pagamento da Intelligence não disser. Prime não tem cupom: no Prime, a urgência é a disponibilidade.

5. CONVITE
Feche com: "Posso te mandar o link do que fizer mais sentido pra você hoje?"
Se a pessoa já disser a experiência, envie o checkout oficial na mesma resposta, lembrando o cupom para digitar.

Depois da abertura:
- se a pessoa hesitar entre Mind e VIP, use a profissão como critério (seção 3);
- se a barreira for preço, siga a seção 11 e a regra desconto_individual: o 300OFF no Mind é resgate, nunca segunda oferta automática. Antes de liberá-lo, diga que vai verificar se consegue aprovar uma condição melhor e volte com a aprovação na resposta seguinte;
- ao enviar o checkout, use checkout_sent = true e desfecho = checkout_enviado.


==================================================
19. QUEM JÁ FOI AO SUMMIT
==================================================

Se a Intelligence mostrar que a pessoa participou de uma edição anterior, reconheça isso logo no início: "Que bom te ver de volta! Vi que você esteve no Summit no ano passado."

Pergunte o que a traz de volta e quais são as expectativas para este ano. Use a resposta para ligar a expectativa à experiência que entrega aquilo e recomende com base nisso.

Nunca afirme participação anterior sem o dado no Kit. Nunca cite categoria, valor ou detalhe da compra anterior sem que a pessoa toque no assunto.$t$;

    update agentes.prompts
       set conteudo = v_txt, versao = 7, atualizado_em = now()
     where chave = 'playbook_summit_b2c' and ativo;
  end if;

  ------------------------------------------------------------------ B2B v10 -> v11
  select conteudo into v_txt from agentes.prompts where chave = 'playbook_summit_b2b' and ativo;
  if v_txt is null then raise exception 'playbook_summit_b2b ausente'; end if;
  if (select versao from agentes.prompts where chave = 'playbook_summit_b2b' and ativo) >= 11 then
    raise notice 'playbook_summit_b2b já em v11 ou superior; nada a fazer';
  else
    if md5(v_txt) <> '3b6fb8d3108604feb15d598263776b26' then
      raise exception 'playbook_summit_b2b v10 divergente do esperado (md5 %)', md5(v_txt);
    end if;
    update agentes.prompts
       set conteudo = v_ident || E'\n\n' || ltrim(v_txt, E'\n'), versao = 11, atualizado_em = now()
     where chave = 'playbook_summit_b2b' and ativo;
  end if;

  ------------------------------------------------------------------ suporte v1 -> v2
  select conteudo into v_txt from agentes.prompts where chave = 'playbook_cliente_suporte' and ativo;
  if v_txt is null then raise exception 'playbook_cliente_suporte ausente'; end if;
  if (select versao from agentes.prompts where chave = 'playbook_cliente_suporte' and ativo) >= 2 then
    raise notice 'playbook_cliente_suporte já em v2 ou superior; nada a fazer';
  else
    if md5(v_txt) <> '3b6d80e08de7d72289bd478ad74ddbee' then
      raise exception 'playbook_cliente_suporte v1 divergente do esperado (md5 %)', md5(v_txt);
    end if;
    update agentes.prompts
       set conteudo = replace(v_ident, ' A condução da conversa é sua, do início ao fechamento.', '') || E'\n\n' || v_txt,
           versao = 2, atualizado_em = now()
     where chave = 'playbook_cliente_suporte' and ativo;
  end if;
end $$;

-- Prova: versões e presença das seções novas.
do $$
begin
  if (select versao from agentes.prompts where chave = 'playbook_summit_b2c' and ativo) < 7 then raise exception 'b2c não subiu'; end if;
  if (select conteudo from agentes.prompts where chave = 'playbook_summit_b2c' and ativo) !~ '18\. ABERTURA PELA OFERTA' then raise exception 'seção 18 nova ausente'; end if;
  if (select conteudo from agentes.prompts where chave = 'playbook_summit_b2c' and ativo) ~ '18\. PEDIDO DE CONDIÇÃO ESPECIAL' then raise exception 'seção 18 antiga ainda presente'; end if;
  if (select conteudo from agentes.prompts where chave = 'playbook_summit_b2c' and ativo) !~ 'Você é a MIA' then raise exception 'identidade ausente no b2c'; end if;
  if (select conteudo from agentes.prompts where chave = 'playbook_summit_b2b' and ativo) !~ 'Você é a MIA' then raise exception 'identidade ausente no b2b'; end if;
  if (select conteudo from agentes.prompts where chave = 'playbook_cliente_suporte' and ativo) !~ 'Você é a MIA' then raise exception 'identidade ausente no suporte'; end if;
end $$;

commit;
