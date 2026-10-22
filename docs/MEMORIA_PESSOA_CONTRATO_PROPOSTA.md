# Memória da pessoa — o que existe hoje e proposta de contrato de sensibilidade

> Documento de orientação para a Adriana (pedido de 22/10/2026: "antes eu preciso ver exatamente o que
> ela guarda… uma regra para classificar o que é confidencial, o que pode ir a um agente específico e o
> que pode ser dividido entre agentes"). **Nada aqui está implementado**: hoje nenhum agente recebe a
> memória da pessoa. Entregar é gate dela (produto + sensibilidade); a mudança de função é D7.

## 1. Onde mora e o que guarda

Casa: `intelligence.participante_memoria` (uma linha por fato sobre uma pessoa, com `mind_id`).
Campos que importam: `tipo`, `chave`, `valor` (JSON com `text`, `scope`, `sensitivity`, `evidence_kind`,
`code`, `context`), `origem`, `status` (`ativa` / `proposta` / `substituida`), `confianca`.

Quem grava:

- `regra_perfil`: regra determinística a partir do cadastro/HubSpot (ICP, JTBD, cargo, empresa). Não
  vem de conversa.
- `analise_vendas_summit` e `analise_concierge`: a análise pós-conversa (`analisar-conversa`), via
  `analise_projetar_memoria`. É aqui que entra o que a pessoa disse ao agente.
- `confirmado_pelo_usuario`: a própria pessoa confirmou (poucos casos, só `interesse`).

Inventário das memórias **ativas** em 22/10/2026 (15.732 linhas):

| tipo | linhas | pessoas | origem principal | exemplo real (anonimizado) |
|---|---:|---:|---|---|
| jtbd | 3.829 | 1.598 | regra_perfil | "Aprender a liderar melhor (eu, como líder)" |
| icp | 2.240 | 2.240 | regra_perfil | "Gestor(a) / Middle Management (não RH)" |
| interesse | 2.126 | 776 | análises | "Workshop Falhar melhor"; "Futuro do trabalho" |
| empresa | 1.959 | 1.959 | regra_perfil | nome da empresa |
| cargo | 1.949 | 1.949 | regra_perfil | "Proprietária - Psicóloga Clínica" |
| preferencia | 1.271 | 686 | análises | "não quer receber mais contatos"; "descadastrar de comunicações" |
| objetivo | 680 | 412 | análises | "Encontrar inspiração para um desafio atual" |
| preferencia_comercial | 582 | 504 | análises | "VIP"; "não vai ao evento neste ano" |
| identidade | 564 | 564 | análises | nome como a pessoa se apresentou |
| outro | 181 | 155 | análises | "insatisfação com a organização do evento anterior" |
| logistica | 158 | 135 | análises | "Vai aos 2 dias do evento" |
| restricao | 96 | 89 | análises | "considera o valor do ingresso como barreira" |
| stakeholder | 76 | 58 | análises | "autorização da empresa" |
| delegacao | 21 | 20 | análises | "atua em nome do marido para resolver o acesso" |

Escopo (`scope`): 12.472 `stable` (perfil durável), 3.258 `opportunity` (vale para esta oportunidade),
0 `temporary` (o projetor descarta as temporárias do concierge).

**Sensibilidade hoje: não existe classificação.** `sensitivity` vale `none` em 5.572 linhas e está vazia
nas outras 10.160 (as de `regra_perfil` e parte das análises antigas). Nenhuma linha está marcada como
sensível, porque o projetor do concierge **descarta** na entrada tudo que não for `none`
(`analise_projetar_memoria`: `continue when v_sens is distinct from 'none'`). Ou seja: o que a análise
julgou sensível nunca foi gravado, e o que foi gravado nunca foi classificado além de "não sensível".
O prompt da análise decide sozinho o que é `none`; não há regra escrita que o painel mostre.

Quem lê hoje: `mind_customer_intelligence` (ICP, JTBD, cargo, empresa para o contexto do agente, com a
trava de não-lead) e `mindagent_chat_get_context` (continuidade). O bloco "memória da pessoa" (interesses,
objetivos, preferências, restrições) **não chega ao agente** em nenhuma rota; fica no painel (Inteligência).

## 2. O problema a resolver

Três perguntas distintas, que hoje se misturam:

1. **O que não pode nem ser gravado?** (dado clínico, diagnóstico, sofrimento psíquico, dado financeiro
   pessoal, dado de terceiros nomeados, orientação sexual/religião/saúde). Hoje depende do prompt da
   análise dizer `sensitivity ≠ none`, e aí o fato some sem rastro.
2. **O que pode ser gravado, mas só um humano vê?** (reclamação sobre a empresa, contexto delicado de
   trabalho, "não quer ser contatada por X"). Útil para a Adriana e para a equipe, nunca para um agente
   falar de volta à pessoa.
3. **O que o agente pode usar, e qual agente?** O que a pessoa disse à Vendedora do Summit (orçamento,
   decisor, prazo) é da negociação do Summit; o nome, o cargo, o interesse em liderança servem a todos.

## 3. Proposta: três classes de visibilidade, decididas por regra e não por prompt

Classe gravada em cada memória (nova chave dentro de `valor`, sem tabela nova; D2 não é tocada):

| classe | quem vê | exemplos (por `tipo` e conteúdo) |
|---|---|---|
| **A · compartilhada** | qualquer agente do Mind (MIA, Concierge, Institute, Dash, Vendedora) e o painel | identidade (nome), cargo, empresa, ICP, JTBD, interesse por tema, objetivo profissional, **preferência de contato** ("não me ligue", "só e-mail", opt-out), logística do evento |
| **B · do produto** | só os agentes do produto que gravou (ex.: Summit) e o painel | preferencia_comercial, restricao (preço, orçamento), stakeholder, delegacao, "outro" ligado à negociação |
| **C · só humanos** | painel (administrador), nunca o agente | reclamação/insatisfação, contexto delicado de trabalho, qualquer fato com `sensitivity ≠ none` que valha a pena guardar para a equipe |
| **(não grava)** | ninguém | saúde/diagnóstico/sofrimento, finanças pessoais, dado de terceiro nomeado, categorias especiais da LGPD. Vale registrar só o **sinal** ("acionou protocolo de crise em 22/10"), nunca o conteúdo |

Regras de desempate:

- A classe vem primeiro da **regra por tipo** (tabela acima) e só depois do juízo da análise
  (`sensitivity`): a análise pode **subir** a classe (A → C), nunca descer.
- `preferencia` de contato é **sempre A**: o pior erro possível é um agente contatar quem pediu para
  não ser contatada porque a memória ficou "só do Summit".
- Memória `opportunity` de outro produto não é entregue ao agente (vale para B); `stable` de classe A vale
  para todos.
- Playground e conversas de teste nunca gravam (já é assim).

## 4. O que muda, em ordem (cada passo é um gate seu)

1. **Ver antes de decidir** (sem mudança de contrato): no painel, em Inteligência → Memória da pessoa,
   mostrar por tipo quantas linhas há e **exemplos reais mascarados** ao clicar na fonte (é o item que
   você pediu em 22/10: "clicar no source e ver exemplos"). Com isso você ajusta a tabela da seção 3
   com casos reais.
2. **Classificar o que já existe** (migration, sem função nova): preencher `valor.visibilidade` nas
   15.732 linhas pela regra por tipo (A/B/C). Nada muda para o agente ainda.
3. **Gravar classificado daqui para a frente** (D7: alterar `analise_projetar_memoria`): aplicar a regra
   por tipo + `sensitivity`; o que hoje é descartado em silêncio passa a virar classe C ou "não grava",
   com contagem visível no painel (quantas foram recusadas e por quê, sem o conteúdo).
4. **Entregar ao agente** (D7 + contrato de prompt): um bloco "o que já sabemos desta pessoa" no
   `AGENT_CONTEXT`, montado por função única (`mind_memoria_para_agente(rota, mind_id)`) que aplica a
   classe, o produto da rota e o escopo. O agente recebe texto curto por tipo, nunca o JSON cru, e o
   playbook ganha a instrução de **usar sem repetir de volta** ("você me disse que…" só quando a
   pessoa trouxe o assunto). Começar por um agente (sugestão: Concierge ou MIA), com o Playground para
   conferir.
5. **Direito da pessoa**: uma porta para apagar a memória de uma pessoa (hoje é SQL manual).

## 5. O que eu recomendo que você decida agora

- A tabela da seção 3 está certa para o Mind? Em especial: `preferencia_comercial` e `restricao` são
  só do produto (B) ou podem ir a todos (A)?
- Reclamações e insatisfação (`outro`) ficam em C (só humanos) ou não se gravam?
- Sinal de crise: guardar o **sinal** (data e rota) para a equipe, ou nada?
- Primeiro agente a receber memória: Concierge (continuidade de atendimento) ou MIA (personalizar as
  indicações de conteúdo)?

Até você decidir, nada é entregue a agente nenhum; o passo 1 pode sair sem gate porque só mostra ao
administrador o que já está gravado.
