# CRM — quem é a pessoa, e quem pode saber o quê

O `mind` guarda o evento e o conteúdo. O **`crm`** guarda as pessoas: quem
elas são, o que compraram, por onde chegaram. São regimes de dado
diferentes — um é editorial e igual para todos, o outro é individual e
tem dono — e por isso vivem em esquemas separados, com regras próprias.

Este documento fixa **quem enxerga o quê**. Quem for ligar um agente novo
ao CRM precisa passar por aqui antes.

## A regra que governa tudo

> Um bot voltado ao cliente não tem como alcançar dado interno.
> Não porque foi instruído a não usar — porque a função que ele chama
> não lê aquelas tabelas.

A separação é estrutural. Um jeito esperto de perguntar não contorna
uma barreira que existe no banco, e nenhum ajuste de prompt reabre o que
o SQL fechou.

## As duas portas

Todo acesso a dado individual passa por uma destas funções. Elas são
`security definer`, registram quem consultou o quê em `crm.acessos`, e
são o **único** caminho: as tabelas têm RLS ligado e nenhum papel do
PostgREST enxerga nada diretamente.

| Função | Quem chama | O que devolve |
|---|---|---|
| `crm.buscar_pessoa(email, whatsapp, agente)` | concierge, WhatsApp, pós-venda | só o conversável |
| `crm.contexto_comercial(email, whatsapp, agente)` | agentes comerciais | o conversável **+** os sinais internos |

**O conversável** — o que o bot pode dizer à própria pessoa: primeiro
nome, sobrenome, e-mail, WhatsApp, empresa, cargo, estágio no funil e os
produtos que ela adquiriu.

**O interno** — o que orienta tom e argumento, e nunca é recitado: origem
de chegada e do último contato, UTMs, dono no CRM, status do lead,
negócios associados, último contato, perfil e NPS. A resposta de
`contexto_comercial` carrega um campo `uso_interno` dizendo isso em voz
alta, para o agente não confundir contexto com conteúdo.

Pessoa desconhecida devolve `nao_cadastrado` — não é erro, é um lead a
coletar.

## As tabelas

```
crm.pessoas            espelho do HubSpot: identidade conversável
crm.pessoas_interno    sinais que orientam, mas não se dizem
crm.pessoa_produtos    o que cada pessoa adquiriu → catalogo.produtos
crm.pessoa_nps         NPS por pessoa E por produto
crm.leads_capturados   fila de leads coletados pelos bots, rumo ao HubSpot
crm.acessos            trilha de quem consultou dado de quem
crm.sync_estado        marca d'água do sincronismo
crm.mapa_produtos      de-para entre o vocabulário do HubSpot e o catálogo
```

### Duas chaves, não uma

`email` é a chave preferida — é o que o Yazo entrega ao concierge. Mas
**7,8% dos contatos do HubSpot não têm e-mail**, e o WhatsApp é
justamente por onde o Treble conhece a pessoa. Daí a segunda chave.

Um gatilho normaliza na entrada: e-mail vira minúsculo e aparado,
WhatsApp vira só dígitos com DDI (`11 98888-7777` → `5511988887777`).
Sem isso, `Maria@X.com` e `maria@x.com` viram duas pessoas.

Registro sem nenhuma das duas chaves é recusado: não haveria como
reencontrar essa pessoa depois.

## O ciclo do dado — uma verdade só

```
HubSpot ──sync──> crm.pessoas ──> bots ──> crm.leads_capturados ──> HubSpot
```

O HubSpot é a fonte da verdade. O espelho é leitura otimizada, escrito
apenas pelo sincronizador.

**Os bots nunca escrevem em `crm.pessoas`.** Lead novo vai para
`crm.leads_capturados` via `crm.registrar_lead(...)`, um processo envia
ao HubSpot, e o HubSpot devolve a pessoa no próximo sync. É o que impede
duas verdades brigando pelo mesmo cadastro.

## Produtos vêm do catálogo, não de texto solto

`crm.pessoa_produtos.produto_codigo` referencia `catalogo.produtos` — o
registro de produtos que vive na raiz, fora de qualquer vertical, e que
qualquer agente consulta para saber de que vertical é um produto e onde
estão seus dados.

A referência é rígida de propósito: produto que não está no catálogo
**bloqueia a carga e aparece em `crm.sync_estado.ignorados`**, em vez de
inventar um código novo. Falhar alto é melhor que criar um segundo
vocabulário de produto por acidente.

`crm.mapa_produtos` traduz os rótulos do HubSpot para códigos do
catálogo. É tabela, não código: opção nova no HubSpot vira uma linha
aqui, sem tocar no sincronizador.

## O que o espelho deliberadamente não guarda

Escolhido pela taxa de preenchimento real na base (11.536 contatos):

| Deixado de fora | Por quê |
|---|---|
| `mobilephone` | 5,6% preenchido; o WhatsApp cobre 58,3% |
| `produto_de_interesse` | 0% |
| `eduzz_buyer_id` | 0,2% |
| total de ingressos *lifetime* | incoerente na origem (462 < os 583 de 2026) |

Espelhar campo abandonado é dar ao bot uma resposta errada com cara de
certa. O total confiável é calculado do nosso lado.

Pela mesma régua, os UTMs entraram como **detalhe**, não como base: estão
em 7-8% dos contatos. A origem canônica (`origem_primeira` e
`origem_ultima`) vem dos campos que o HubSpot preenche em 100%. Quem
contar campanha pelos UTMs estará contando 8% da base achando que é o
todo.

## Privacidade

- **Segmento ≠ indivíduo.** Perfis e ICPs são conhecimento editorial e
  vivem em `mind.knowledge_documents` com `audiencia = 'interno'`. Dado
  individual é só aqui.
- **Minimização.** Espelhamos apenas campos que algum agente usa.
- **Auditoria.** Toda leitura individual grava em `crm.acessos`.
- **Consentimento.** `descadastrado_email` é sinal de recusa: respeitar
  antes de qualquer abordagem.
- Atender "quero saber/apagar meus dados" é uma consulta a um lugar só.

`concierge.acessos_dado_pessoal` audita `mind.people` (participante do
evento, identidade Yazo) e tem chave estrangeira para lá. O CRM é outra
população — todo contato e lead, tenha ou não vindo ao evento — e por
isso tem trilha própria.

## Pendências conhecidas

- **Sincronismo não construído.** Existem a marca d'água e o de-para;
  falta a função de upsert e o robô diário. A carga inicial será a
  primeira execução do mesmo mecanismo — não um carregamento manual que
  ninguém saberia repetir.
- **NPS sem fonte.** A propriedade do HubSpot está vazia em toda a base.
  A tabela nasceu pronta e vazia em vez de fingir que há dado.
- **Institute sem marcação.** As propriedades de formação existem no
  HubSpot e estão 100% vazias. O catálogo já aceita; falta marcar quem
  cursou o quê em 2025.
