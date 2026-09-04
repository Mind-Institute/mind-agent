-- Corrige duas contradições que criavam atrito no vendedor do Treble:
-- 1. decisioning mandava proteger momentum, mas depois bloqueava checkout por cadastro;
-- 2. o playbook B2B repetia o mesmo bloqueio, apesar de também dizer para enviar o
--    checkout antes da pergunta cadastral.
--
-- Cadastro continua podendo ser enriquecido com dados espontâneos. Ele deixa de ser
-- pré-condição para resposta, recomendação, preço, calculadora, proposta ou checkout.

do $migration$
declare
  v_decisioning text;
  v_b2b text;
begin
  select conteudo into v_decisioning
  from agentes.prompts
  where chave = 'decisioning_vendas_universal'
  for update;

  if v_decisioning is null then
    raise exception 'decisioning_vendas_universal ausente';
  end if;

  v_decisioning := regexp_replace(
    v_decisioning,
    E'CONTATO COMERCIAL NO INÍCIO.*?LUPA DE INTELLIGENCE',
    E'ENRIQUECIMENTO SEM ATRITO\nUse primeiro perfil, CRM, histórico e credenciamento. Dados cadastrais podem enriquecer o contexto quando surgirem naturalmente, mas vender é prioritário.\n\nNunca interrompa uma compra madura para completar cadastro. Nunca condicione resposta, recomendação, preço, calculadora, proposta ou checkout a nome completo, e-mail, empresa ou cargo. O WhatsApp do canal já ancora a conversa.\n\nB2C e B2B classificam a compra atual, não a profissão da pessoa. Cargo, empresa e potencial corporativo futuro não tornam uma compra individual B2B.\n\nLUPA DE INTELLIGENCE',
    's'
  );

  if position('Nunca condicione resposta, recomendação, preço, calculadora, proposta ou checkout' in v_decisioning) = 0
     or position('não entregue calculadora, proposta ou checkout antes' in lower(v_decisioning)) > 0 then
    raise exception 'decisioning não foi reconciliado';
  end if;

  update agentes.prompts
     set conteudo = v_decisioning,
         versao = versao + 1,
         atualizado_em = now()
   where chave = 'decisioning_vendas_universal';

  select conteudo into v_b2b
  from agentes.prompts
  where chave = 'playbook_summit_b2b'
  for update;

  if v_b2b is null then
    raise exception 'playbook_summit_b2b ausente';
  end if;

  v_b2b := regexp_replace(
    v_b2b,
    E'CADASTRO B2B OBRIGATÓRIO NO INÍCIO.*?SINAIS DE ALTA INTENÇÃO',
    E'ENRIQUECIMENTO B2B SEM ATRITO\nUse dados já existentes e aproveite informações oferecidas espontaneamente. Não peça cadastro apenas para enriquecer CRM e nunca transforme a conversa em formulário.\n\nNome, empresa, cargo, e-mail ou outro campo ausente não bloqueiam resposta, recomendação, calculadora, proposta, checkout ou handoff. Se a pessoa quer comprar, envie o checkout primeiro.\n\nSINAIS DE ALTA INTENÇÃO',
    's'
  );

  v_b2b := replace(
    v_b2b,
    'Com qualquer desses sinais, avance na venda e mantenha a coleta cadastral progressiva: entregue valor primeiro e peça o próximo campo ausente na mesma mensagem.',
    'Com qualquer desses sinais, avance na venda. Só pergunte algo adicional quando a resposta puder mudar o próximo movimento comercial.'
  );
  v_b2b := replace(
    v_b2b,
    'Isso não interrompe o cadastro obrigatório: continue pedindo o próximo campo mínimo ausente.',
    'Não interrompa a venda para completar cadastro.'
  );
  v_b2b := replace(
    v_b2b,
    'Se a pessoa pedir o link ou disser que quer comprar, envie o checkout antes da pergunta cadastral e, na mesma mensagem, peça o próximo campo ausente. Continue nos turnos seguintes até completar o cadastro.',
    'Se a pessoa pedir o link ou disser que quer comprar, envie o checkout imediatamente. Não acrescente pergunta cadastral ao mesmo turno.'
  );

  if position('Nome, empresa, cargo, e-mail ou outro campo ausente não bloqueiam' in v_b2b) = 0
     or position('CADASTRO B2B OBRIGATÓRIO NO INÍCIO' in v_b2b) > 0 then
    raise exception 'playbook B2B não foi reconciliado';
  end if;

  update agentes.prompts
     set conteudo = v_b2b,
         versao = versao + 1,
         atualizado_em = now()
   where chave = 'playbook_summit_b2b';
end
$migration$;
