-- Customer Intelligence: a IA continua sendo a autoridade semantica.
-- O banco continua fail-closed para proveniencia, sensibilidade e persistencia.
-- Este prompt aplica o contrato ICP/JTBD e separa pessoa de Product Intelligence,
-- Commercial e Decisioning.

do $migration$
declare
  v_conteudo text;
  v_bloco_antigo text := $old$
EXTRAIA TUDO QUE FOR ÚTIL — SEM TETO ARTIFICIAL
Não limite a dois, cinco ou qualquer número fixo. Extraia todos os fatos úteis realmente sustentados pela conversa, deduplicando conceitos equivalentes.

Priorize:
- identidade quando explicitamente fornecida;
- cargo/função e empresa;
- ICP quando a conversa realmente trouxer evidência profissional suficiente;
- jobs-to-be-done realmente expressos;
- objetivos e resultados desejados;
- interesses de conteúdo;
- problemas/desafios profissionais que quer avançar;
- preferências de formato ou abordagem;
- escolhas, recusas e preferências que ela comunicou;
- conteúdos/palestrantes/experiências que explicitamente quer ver;
- conteúdo que disse ter assistido, perdido ou não conseguido ver;
- restrições práticas relevantes;
- necessidades operacionais não sensíveis;
- stakeholder, delegação ou contexto profissional útil.
$old$;
  v_bloco_v4 text := $v4$
FRONTEIRA DA MEMÓRIA — A PESSOA, NÃO O ATENDIMENTO
- `customer_memory` descreve o que a PESSOA revelou sobre si, seu contexto profissional, seus objetivos, suas preferências, suas restrições ou suas escolhas.
- Fato do evento, programação, horário, sala, regra, produto ou qualquer informação trazida pelo AGENTE/Intelligence nunca vira memória da pessoa, mesmo quando a resposta está correta e aparece na conversa.
- Uma pergunta pontual prova apenas que a pessoa fez aquela pergunta. Não a transforme, sozinha, em interesse, preferência, objetivo, JTBD ou contexto durável.
- Dúvida logística como "onde fica a praça de alimentação?", "qual é o horário?" ou "quem é o chef?" não gera memória. Uma preferência ou restrição pessoal explicitamente relatada, como "preciso de tradução simultânea", pode gerar memória operacional quando for útil depois.
- Nunca emita um item cujo valor apenas repita ou parafraseie a resposta do AGENTE. A mensagem do lead indicada como evidência precisa sustentar diretamente um fato SOBRE A PESSOA, não apenas o assunto da conversa.

$v4$;
  v_bloco_novo text := $new$
SELEÇÃO SEMÂNTICA — MEMÓRIA É CURADORIA, NÃO TRANSCRIÇÃO
Você é a autoridade semântica que decide o que merece virar Customer Intelligence. Não extraia tudo que foi mencionado. Extraia somente fatos que passam por TODOS os testes abaixo. Se qualquer teste falhar, não emita o item.

1. TESTE DA PESSOA
O fato descreve a própria pessoa, seu contexto profissional, um progresso que ela busca, uma preferência ou restrição dela, ou os atores da decisão dela?
- Informação sobre evento, agenda, produto, preço, conteúdo, palestrante ou regra pertence a Product Intelligence/Commercial, não à memória da pessoa.
- Resposta, explicação, interpretação ou recomendação do Agent não é fato da pessoa.

2. TESTE DA EVIDÊNCIA
A mensagem de `papel=lead` indicada contém palavras que sustentam diretamente o fato emitido?
- Copie em `evidence_quote` o menor trecho literal suficiente dessa mensagem.
- Se o trecho não existe literalmente na mensagem indicada, não emita o item.
- Contexto estruturado, CRM ou nome do perfil podem ajudar a interpretar, mas não podem ser atribuídos a uma mensagem que não os declarou.
- Nunca escolha um UUID apenas porque pertence ao lead; ele precisa sustentar semanticamente o item.

3. TESTE DA UTILIDADE FUTURA NO MIND
Um Agent Mind em outra interação poderia usar este fato para pelo menos uma finalidade concreta?
- reconhecer contexto profissional/ICP sem perguntar de novo;
- compreender um JTBD, objetivo ou resultado desejado real;
- personalizar tema, profundidade, formato ou abordagem;
- respeitar uma restrição reutilizável;
- compreender stakeholder, delegação ou contexto de decisão.
Curiosidade pontual, navegação, suporte momentâneo e o assunto de uma consulta não passam neste teste.

4. TESTE DE DURABILIDADE E ESCOPO
O fato continua útil além da resposta imediata?
- `stable`: contexto ou preferência que tende a atravessar oportunidades.
- `opportunity`: fato útil durante a jornada/oportunidade atual.
- `temporary`: necessidade do instante. Não emita em `customer_memory`.
Não transforme um problema operacional resolvível agora em histórico permanente.

O QUE NORMALMENTE DEVE SER APRENDIDO
- identidade, cargo atual e empresa quando a própria pessoa os declara;
- ICP sustentado por autoidentificação ou cargo atual inequívoco, nunca por dor, tema ou produto;
- JTBD sustentado pelo problema, progresso ou resultado que a pessoa quer alcançar;
- objetivo formulado como resultado da pessoa, independente do produto usado para chegar a ele;
- interesse profissional ou de conteúdo explicitamente afirmado, ou escolha concreta que revele preferência real;
- preferência explícita de formato, profundidade, abordagem ou comunicação;
- restrição reutilizável que altere atendimento, recomendação ou execução;
- stakeholder, delegação ou patrocínio explicitamente descritos.

O QUE NÃO DEVE SER APRENDIDO
- pergunta que apenas pede lista, descrição, localização, horário, preço, disponibilidade, acesso, reserva ou instrução de uso;
- entidade mencionada somente para pedir informação: palestrante, sessão, produto, tema ou local;
- fato fornecido pelo Agent ou por Product Intelligence;
- recomendação do Agent sem adoção explícita da pessoa;
- compra, ingresso, etapa do funil, suporte ou operação que já existem em CRM/Commercial/sistemas atuais;
- problema momentâneo como ingresso não visível, senha, acesso ou dúvida de navegação;
- preferência inventada a partir da forma da pergunta, como "prefere conteúdo prático" porque pediu uma recomendação aplicável;
- objetivo centrado no produto, como "quer conteúdo do Summit", quando a conversa só sustenta uma consulta; quando houver resultado real, registre o resultado da pessoa, não a ferramenta/produto;
- múltiplos JTBDs especulativos para explicar uma única fala. Emita somente jobs diretamente sustentados.

FRONTEIRAS POR EXEMPLO
- "Qual é a programação do dia 17?" → nenhuma memória.
- "Me fale sobre Amy Edmondson" → nenhuma memória.
- "Quero muito ver Amy Edmondson" → `interest`, scope `opportunity`.
- "Tenho interesse profissional contínuo em segurança psicológica" → `interest`, scope `stable`; não basta para JT06.
- "Meu time evita trazer problemas e quero mudar isso" → JT06 e, se útil sem duplicação, o objetivo correspondente.
- "Sou HRBP e preciso desenvolver os gestores que apoio" → `role`, ICP inequívoco e JT04.
- "Quando e em que sala é o workshop Falhar melhor?" → nenhuma memória.
- "Reserve Liderança Engajadora para mim" → escolha concreta/interesse de oportunidade; não invente JTBD.
- "Meu ingresso não aparece no app" → nenhuma Customer Intelligence durável; é suporte operacional.
- "Preciso de tradução simultânea durante o evento" → restrição/logística de oportunidade, somente na forma operacional não sensível.
- "Preciso convencer o board com indicadores para aprovar o plano" → JT08, objetivo e stakeholder `board`.

QUALIDADE DA REPRESENTAÇÃO
- Prefira o significado reutilizável à paráfrase do pedido. "Quero reduzir a exaustão da equipe" é objetivo; "quer conteúdos do Summit sobre exaustão" é uma formulação dependente do produto.
- Não duplique o mesmo significado em `goal`, `interest`, `constraint` e `other`. Preserve conceitos diferentes; deduplique paráfrases.
- `interest` é atração explicitamente demonstrada por tema/conteúdo. O simples ato de consultar algo não prova interesse durável.
- `constraint` limita de verdade uma decisão ou execução. Não é uma qualidade desejável inventada pelo analisador.
- `other` não é válvula de escape. Use apenas para fato da pessoa, útil e durável que realmente não caiba nas categorias específicas.
- A saída vazia é um resultado correto e esperado quando a conversa foi apenas informacional, operacional ou de suporte.

$new$;
begin
  select conteudo into v_conteudo
  from agentes.prompts
  where chave = 'analise_concierge' and ativo
  for update;

  if v_conteudo is null then
    raise exception 'analise_concierge ausente ou inativo';
  end if;

  -- Aplicavel tanto sobre a versao 3 do Git quanto sobre a contencao v4.
  v_conteudo := replace(v_conteudo, v_bloco_v4, '');
  if position('SELEÇÃO SEMÂNTICA — MEMÓRIA É CURADORIA, NÃO TRANSCRIÇÃO' in v_conteudo) = 0 then
    if position(v_bloco_antigo in v_conteudo) = 0 then
      raise exception 'analise_concierge mudou de forma; bloco de selecao nao encontrado';
    end if;
    v_conteudo := replace(v_conteudo, v_bloco_antigo, v_bloco_novo);
  end if;

  -- Fica no JSON bruto da analise para auditoria, sem criar uma nova casa.
  if position('"evidence_quote":' in v_conteudo) = 0 then
    v_conteudo := replace(
      v_conteudo,
      E'      "evidence_message_id": "UUID exato de uma mensagem do lead",\n',
      E'      "evidence_message_id": "UUID exato de uma mensagem do lead",\n'
        || E'      "evidence_quote": "menor trecho literal dessa mensagem que sustenta o item",\n'
    );
  end if;

  update agentes.prompts
  set conteudo = v_conteudo,
      versao = greatest(versao, 5),
      atualizado_em = now()
  where chave = 'analise_concierge' and ativo;
end
$migration$;

do $contract$
declare
  v_conteudo text;
  v_versao integer;
begin
  select conteudo, versao into v_conteudo, v_versao
  from agentes.prompts
  where chave = 'analise_concierge' and ativo;

  if v_versao < 5 then raise exception 'prompt nao avancou para v5'; end if;
  if position('SELEÇÃO SEMÂNTICA — MEMÓRIA É CURADORIA, NÃO TRANSCRIÇÃO' in v_conteudo) = 0 then raise exception 'protocolo semantico ausente'; end if;
  if position('TESTE DA UTILIDADE FUTURA NO MIND' in v_conteudo) = 0 then raise exception 'teste de utilidade ausente'; end if;
  if position('A saída vazia é um resultado correto e esperado' in v_conteudo) = 0 then raise exception 'contrato de saida vazia ausente'; end if;
  if position('"evidence_quote": "menor trecho literal dessa mensagem que sustenta o item"' in v_conteudo) = 0 then raise exception 'evidence_quote ausente'; end if;
  if position('EXTRAIA TUDO QUE FOR ÚTIL — SEM TETO ARTIFICIAL' in v_conteudo) > 0 then raise exception 'instrucao agressiva antiga permaneceu'; end if;
  if position('FRONTEIRA DA MEMÓRIA — A PESSOA, NÃO O ATENDIMENTO' in v_conteudo) > 0 then raise exception 'contencao v4 permaneceu duplicada'; end if;
end
$contract$;
