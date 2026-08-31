-- QUANDO VOCÊ NÃO SOUBER: o agente para de devolver silêncio.
--
-- O PROBLEMA OBSERVADO. Perguntado sobre o que não está nos dados, o agente às vezes
-- não responde nada. Ficar calado é o pior desfecho possível: a pessoa conclui que foi
-- ignorada e vai embora, e nenhum log registra uma resposta ruim — registra ausência.
--
-- O QUE JÁ EXISTIA. `playbook_router` (título: "Identidade, dados e limites (vale
-- sempre)") é a camada universal: ela entra em TODA rota do Treble pela camada `agent`
-- de `treble_agent_prompt`. Ela já mandava não inventar, já mandava "confirmar com o
-- time" e já tinha o critério de `needs_human`. Não se cria casa nova para isto.
--
-- OS TRÊS BURACOS que este bloco fecha:
--
--   1. nada proibia o SILÊNCIO — tudo era "não invente" / "transfira", e nenhuma linha
--      dizia que deixar a pessoa sem resposta é inaceitável;
--   2. faltava o PRIMEIRO TEMPO — o texto mandava oferecer a saída ("vou confirmar com
--      o time") sem nunca mandar ADMITIR que não sabe. Admitir e oferecer são dois
--      movimentos, e só o segundo estava escrito;
--   3. não havia CONDICIONAL DE CANAL — o texto assumia que transferir sempre existe.
--      Existe no WhatsApp/Treble (`needs_human=true` é contrato real). Não existe hoje
--      no app/Concierge, que admite e para ali.
--
-- POR QUE CONDUTA E NÃO FRASE PRONTA. A redação é do agente, escolhida para o momento;
-- o que o playbook fixa é o CONTEÚDO (admitir, depois oferecer) e o LIMITE (só prometer
-- a saída que o canal de fato executa). Copy fixa aqui viraria robô repetindo a mesma
-- desculpa, e é justamente o que o tom de voz do Mind não faz.
--
-- ESCOPO. Só `playbook_router`, que é Treble/WhatsApp. O app/Concierge não lê este
-- prompt e continua sem handoff — a capacidade não existe lá, e prometer contato que
-- ninguém dá seria inventar. Fica registrado para a lane do Concierge (#41).

do $guard$
declare
  v_ancora  constant text := 'CHAMAR HUMANO (needs_human=true)';
  v_bloco   constant text :=
'QUANDO VOCÊ NÃO SOUBER — nunca fique calado nem desconverse. Deixar a pessoa sem resposta é pior que qualquer resposta honesta: ela conclui que foi ignorada e vai embora.
Dois tempos, nesta ordem:
1. ADMITA que você não tem essa informação — com naturalidade, sem rodeio e sem se desculpar demais. Não invente meio-caminho nem responda outra coisa no lugar.
2. OFEREÇA A SAÍDA que de fato existe neste canal. A redação é sua, escolha a que couber no momento; o que não muda é o conteúdo:
- se você pode transferir, diga que vai passar a conversa para alguém do time (needs_human=true);
- se este canal não transfere, diga que alguém do time entra em contato assim que possível.
Nunca prometa transferência que não acontece nem retorno que ninguém vai dar: prometer o que o canal não faz é uma forma de inventar.
Antes de encerrar o assunto, responda o que você AINDA consegue responder — quase sempre sobra algo útil, e assim a pessoa fica.
Isso não atropela o resto: continua valendo entregar valor e recolher quem é a pessoa antes de transferir de fato.';
  v_antes   text;
  v_depois  text;
begin
  select conteudo into v_antes from agentes.prompts where chave = 'playbook_router';

  if v_antes is null then
    raise exception 'playbook_router não existe — a camada universal mudou de casa, revise antes de aplicar';
  end if;

  -- Idempotente: rodar de novo não duplica o bloco.
  if position(v_bloco in v_antes) > 0 then
    raise notice 'bloco já presente em playbook_router; nada a fazer';
    return;
  end if;

  -- A âncora tem de existir UMA vez. Se o prompt for reescrito e ela sumir, a migration
  -- falha aqui em vez de anexar o bloco em lugar errado.
  if position(v_ancora in v_antes) = 0 then
    raise exception 'âncora % não encontrada em playbook_router', v_ancora;
  end if;
  if (length(v_antes) - length(replace(v_antes, v_ancora, ''))) / length(v_ancora) <> 1 then
    raise exception 'âncora % aparece mais de uma vez em playbook_router', v_ancora;
  end if;

  -- O bloco entra ANTES de CHAMAR HUMANO: primeiro a conduta, depois o mecanismo.
  v_depois := replace(v_antes, v_ancora, v_bloco || E'\n\n' || v_ancora);

  if length(v_depois) <> length(v_antes) + length(v_bloco) + 2 then
    raise exception 'tamanho inesperado após a inserção: % vs %',
      length(v_depois), length(v_antes) + length(v_bloco) + 2;
  end if;

  update agentes.prompts
     set conteudo      = v_depois,
         versao        = versao + 1,
         atualizado_em = now()
   where chave = 'playbook_router';

  raise notice 'playbook_router: % -> % chars', length(v_antes), length(v_depois);
end
$guard$;

-- Confere o resultado: bloco presente uma vez, âncora preservada uma vez.
do $check$
declare v text;
begin
  select conteudo into v from agentes.prompts where chave = 'playbook_router';
  if position('QUANDO VOCÊ NÃO SOUBER' in v) = 0 then
    raise exception 'bloco não ficou em playbook_router';
  end if;
  if position('CHAMAR HUMANO (needs_human=true)' in v) = 0 then
    raise exception 'a âncora se perdeu em playbook_router';
  end if;
end
$check$;
