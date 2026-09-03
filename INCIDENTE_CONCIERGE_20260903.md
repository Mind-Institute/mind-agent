# Incidente do Concierge — 03/09/2026

## Resultado executivo

O incidente não teve uma causa única. Duas falhas independentes apareceram juntas:

1. **A Home quebrava antes da conversa.** Um aviso ativo e imediato chegou com
   `disparo_em = null`. O frontend chamava `.split('T')` sem validar o valor e
   interrompia a montagem da Home.
2. **O Concierge desistia cedo demais.** O Kit, o Gate e as ferramentas estavam
   disponíveis, mas `tool_choice: auto` permitia ao modelo responder que não tinha
   informação sem chamar `buscar_intelligence`. Em produção ele expôs inclusive
   `JSON` e `sessions: []`, detalhes que nunca deveriam chegar ao participante.

O Router não quebrou, o transporte entre frontend e Edge não quebrou e o Kit não
estava vazio. O defeito principal do agente era de **política de recuperação no
runtime**, não de disponibilidade dos componentes.

Correção integrada na [PR #91](https://github.com/Mind-Institute/mind-agent/pull/91),
commit `3ad409969135effc70ead9374fcebd764869f9fc`.

## Mudanças do dia que formaram o contexto

| PR | Mudança relevante | Relação com o incidente |
| --- | --- | --- |
| #84 | Core agêntico compartilhado, Kit amplo, ferramentas de Intelligence e indexador | Criou a arquitetura atual; não interrompeu o transporte |
| #85 | Jornada contextual e uso do ingresso/interesses | Aumentou contexto, sem quebrar Gate ou sessão |
| #86 | Inbox de retomada, ainda desligado | Sem participação no caminho síncrono do chat |
| #87 | Registro de checkout e abandono | Sem participação no erro da Home ou na geração da resposta |
| #88 | Bootstrap reparado para os schemas vivos | Corrigiu uma dívida anterior; não é a causa deste incidente |
| #91 | Recuperação obrigatória, tolerância a aviso imediato e contenção móvel | Hotfix do incidente |

A PR #82 permaneceu fora do `main`, mas duas migrations dela haviam sido aplicadas
manualmente. Uma delas cadastrou o aviso `livros_autografos`, ativo, sem
`disparo_em`. O dado é válido para uma publicação imediata; o consumidor é que não
tolerava a ausência de horário.

## Caminho real do App

```text
frontend
  -> autenticação e sessão
  -> identidade/contexto canônicos
  -> origem autoritativa mind_summit_app -> concierge_summit
  -> Capability Gate
  -> Agent Kit da rota
  -> modelo com ferramentas de leitura
  -> persistência da resposta e telemetria
```

Para `mind_summit_app`, a origem já define `concierge_summit`; portanto o Router é
legitimamente pulado. O Gate continua obrigatório. Outras origens continuam usando o
Router dentro das competências permitidas para o canal.

Identidade não foi alterada neste incidente. `pessoas.pessoas.id` continua sendo o
`person_id` canônico, e identificadores externos continuam em
`engagement.identidades`.

## Hipóteses testadas

| Hipótese | Resultado | Evidência |
| --- | --- | --- |
| Frontend deixou de falar com `mindagent-chat` | Refutada | Duas perguntas reais chegaram à Edge e voltaram para a interface |
| CORS ou JWT bloqueou o chat | Refutada | `mindagent-chat` respondeu no navegador autenticado e permaneceu com `verify_jwt=true` |
| Router passou a escolher rota errada | Refutada para o App | A rota persistida foi `concierge_summit`; a origem do App é autoritativa por desenho |
| Gate estava fechado | Refutada | `mind_rota_capacidade('concierge_summit','mindagent-web')` passou |
| Kit não estava sendo montado | Refutada | Kit vivo trouxe playbook, decisioning, structured data e duas ferramentas |
| Contexto excessivo interrompeu a chamada | Refutada como causa imediata | O contexto é grande, cerca de 63 mil caracteres medidos, mas chamadas factuais responderam normalmente |
| Modelo desistia sem usar ferramenta | Confirmada | Resposta de produção teve `rodadas_tool=0`, `ferramentas=[]` e expôs `sessions: []` |
| Retrieval não tinha dados pesquisáveis | Parcialmente refutada | Busca lexical devolveu regras, avisos, locais, sessões e knowledge; a consulta original não tinha correspondência exata |
| Recuperação semântica estava completa | Refutada | 30 chunks existentes, zero embeddings gerados |
| Aviso novo derrubava a Home | Confirmada | Único aviso ativo com `em=null`; stack funcional terminava em `quandoLegivel(em).split('T')` |
| Bug móvel era o `visualViewport` | Refutada como causa principal | O tratamento de `visualViewport` já existia; o input ainda tinha 15px e acionava zoom automático no iOS |

## Causas-raiz

### 1. Contrato incompleto no consumidor de avisos

`no-ar` significa publicação imediata e pode não possuir horário agendado. A Home
tratava `em` como string obrigatória para todas as situações. Isso transformou um
valor válido em exceção de renderização.

Correção: valor ausente ou malformado é exibido como `Agora`; avisos agendados ainda
exigem uma string temporal válida. Nenhum timestamp artificial foi gravado no banco.

### 2. Autonomia sem regra de recuperação

O Core corretamente evitava pré-buscar tudo, para reduzir latência e custo. Porém,
`tool_choice: auto` também permitia a pior decisão possível: interpretar um recorte
vazio do Kit como prova de inexistência e desistir sem investigar.

Correção: quando a primeira resposta contém sinais claros de abstinência e há
ferramentas disponíveis, o runtime dá uma segunda volta e força apenas
`buscar_intelligence`. Depois disso, o modelo responde com o resultado encontrado ou
admite a ausência em linguagem natural. Respostas já sustentadas pelo Kit continuam
sem busca extra.

### 3. Corpus vetorial preparado, mas não indexado

O código de busca híbrida e o indexador existem, mas o indexador ainda não foi
invocado com credencial administrativa. Estado medido:

| origem | chunks | com embedding | pendentes |
| --- | ---: | ---: | ---: |
| `summit_2026` | 28 | 0 | 28 |
| `institute` | 1 | 0 | 1 |
| `dash` | 1 | 0 | 1 |
| `eventos` | 0 | 0 | 0 |

Assim, a lupa funciona hoje, mas a recuperação do corpus documental é lexical. A
busca por estruturas do evento, regras, avisos, sessões e palestrantes continua ativa.

### 4. Estouro móvel

O campo tinha `font-size: 15px`. No iOS, focar um input abaixo de 16px pode ampliar a
página. Mensagens longas também não tinham contenção horizontal suficiente.

Correção: input em 16px, `min-width: 0` nos contêineres flexíveis,
`overflow-x: hidden` na conversa e quebra de palavras/URLs longas nas bolhas.

## Alterações executadas

- `home/estado.js`: tolerância a aviso `no-ar` sem horário e ordenação segura;
- `styles.css`: prevenção de zoom do iOS e overflow horizontal;
- `_shared/agent-intelligence.ts`: detecção restrita de abstinência prematura;
- `mindagent-chat/index.ts`: segunda volta com busca forçada, orçamento existente de
  no máximo duas rodadas e telemetria `recuperacao_forcada`;
- migration `concierge_busca_antes_de_abster`: playbook v6, busca antes da
  abstinência e proibição explícita de expor detalhes internos;
- contratos de regressão para Home, mobile, prompt e comportamento completo da Edge.

Não foram alterados: identidade, RLS, autenticação, Router, Gate, preço, regra
comercial, CRM, HubSpot, Treble, outbound ou fonte de verdade.

## Provas após a correção

- 156/156 testes Edge/contrato;
- build completo Cloudflare e painel Admin;
- typecheck do Admin;
- Home de produção carregou os 18 avisos sem exceção;
- pergunta direta respondeu credenciamento às 7h30 no Pavilhão 3 com
  `rodadas_tool=0` e `recuperacao_forcada=false`;
- pergunta sem resposta inicial acionou `buscar_intelligence`, persistiu
  `rodadas_tool=1` e `recuperacao_forcada=true`, devolveu candidatos e não expôs
  JSON, campos, prompt ou ferramentas;
- `mindagent-chat` em produção: versão 37, `ACTIVE`, `verify_jwt=true`;
- playbook ativo: versão 6, bloco de recuperação presente;
- migration registrada como `concierge_busca_antes_de_abster`.

## Legado: o que pode e o que não pode ser apagado

O bootstrap foi reparado na PR #88 e hoje é consumidor vivo. Ele não deve ser
apagado. A produção ainda possui sete funções que referenciam `comum.speakers`, tabela
removida:

- `api.changed_since`;
- `api.sessions`;
- `api.speakers`;
- `api.treble_event_bundle`;
- `public.mind_admin_dashboard_counts`;
- `public.mind_admin_mutate_resource`;
- `public.mind_admin_read_resource`.

Isso é dívida real, mas não foi a causa deste incidente. A remoção deve ocorrer apenas
após classificar cada função como consumida, substituída ou morta e comprovar os
callers. Apagar em massa durante o hotfix poderia quebrar o Admin, integrações ou
consumidores externos não versionados.

## Pendência operacional

Invocar `mindagent-index-knowledge` em ambiente confiável com credencial
`service_role`/admin até zerar os chunks pendentes, sem desativar JWT e sem colocar a
chave em SQL, logs ou arquivos. Depois, repetir uma bateria de perguntas sem
correspondência lexical e verificar recuperação semântica, latência e grounding.
