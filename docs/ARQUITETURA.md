# Mind Intelligence — arquitetura real

> O que o sistema **é hoje**, não o que uma IA imaginou. Fonte da verdade: banco real
> (`mind-agent`, Supabase). Quase tudo é teste/placeholder — dá pra remodelar à vontade.

## O que estamos construindo

Três agentes sobre um mesmo núcleo compartilhado:
- **Vendas** — conduz oportunidade comercial (qualquer vertical) e atualiza o HubSpot.
- **Atendimento** — pós-venda / suporte de quem já comprou.
- **Concierge** — embarcado no app do MindSummit; ajuda quem está no evento.

### Como um agente é montado
`prompt base` (comum a todos, em `agentes`) **+** `prompt da plataforma` (`concierge` p/ o
app, `treble` p/ WhatsApp) **+** `playbook da função` (vendas / atendimento / concierge —
independentes) **+** `contexto do produto` buscado na hora.

O vendedor vende Summit, Dash ou Institute com **o mesmo** playbook de vendas — muda só o
**contexto do produto** que ele busca. Playbooks vivem em `agentes.playbooks`, por função.

### O que acontece quando um lead chega
1. Identifica a pessoa e registra que ela chegou (e por onde) em `pessoas.pessoas`.
2. Deriva a **vertical** de onde veio: `intelligence.vertical_da_entrada(site, url)`
   (site do chat ou domínio do `first_url`) → grava em `intelligence.sinais_comerciais.vertical`.
3. Junta o que já se sabe dela, antes de responder:
   - histórico de vida no Mind → `crm.contato_espelho` + `crm.negocios_historicos`;
   - deal **aberto** agora → `crm.pipeline_summit_leads_captados` (e pipelines futuros por vertical).
4. Atua com o playbook da função; se for venda, ao fechar atualiza o card do pipeline /
   cria caso e reflete no HubSpot.
5. Destila **inteligência** sobre a pessoa (`intelligence`) e registra o **engajamento**
   (`engagement`) — enriquecendo o que sabemos dela a cada conversa.

## Mapa dos schemas (o que é real × teste × futuro)

**Núcleo do lead**
- `pessoas` — identidade canônica (1 linha = teste).
- `crm` — espelho do HubSpot. **REAL:** `contato_espelho` (11.587), `negocios_historicos`
  (7.092), `pipeline_summit_leads_captados` (2.675 = pipeline aberto), `mapa_produtos` (9).
- `intelligence` — o que sabemos do lead (sinais, intenções, dossiê, objetivos…). Teste/placeholder.
- `engagement` — conversas/mensagens/sessões. Dados de teste. *(candidato a virar vizinho de/parte de `intelligence`.)*

**Verdades transversais**
- `ecossistema` — universais: `palestrantes_especialistas` (13). *(catálogo e políticas devem vir pra cá.)*
- `catalogo` — mapa vertical→produtos→pipeline: `produtos` (11), `vertical_dominios` (3). *(alvo: dentro de `ecossistema`.)*
- `agentes` — `prompts` base (5) e `playbooks` (por função).
- `platform` — infra de LLM: providers/models/routes + integrações. Real, útil.

**Verticais de produto** (produtos/ofertas + pipeline de cada frente)
- `summit_2026` — **RICO:** 67 sessões, 61 speakers, 27 locais, 25 ofertas (Prime/VIP/Mind,
  delegações, patrocínios), 17 docs. É a inteligência do evento deste ano.
- `institute` (formações), `dash` (consultoria), `eventos` (promocionais) — **vazios**,
  placeholders para o futuro. Tudo bem ficarem vazios.

**Plataformas dos agentes**
- `concierge` — config/inteligência do agente embarcado no app do Summit (templates, ferramentas, flags).
- `treble` — config dos agentes no WhatsApp (Treble).

## Schemas do sistema (do Supabase — não são design nosso, ignorar)
`auth`, `storage`, `supabase_migrations` (histórico de migrations), `vault` (segredos),
`net`/`pg_net`, `pgbouncer`, `realtime`, `cron`, `extensions`, `graphql`/`graphql_public`
(GraphQL do PostgREST — não usamos, pode ignorar).

## Limpeza / pendências
- `quarentena` — **removido** (lixo).
- `mind` — `policies` (6) devem ir p/ `ecossistema`; `organization_content` vazio. Depois `mind` some.
- `public` — só tem o backend do painel admin (`mind_admin_*`); ideal mover p/ schema `admin`.
- **Faxina** de `engagement`+`intelligence` (feedback espalhado em 6 tabelas, perfis
  duplicados) — decidir tabela a tabela o que fica; são as casas da saída dos agentes.
- **Edge functions** (12) — inventariar e remover os mortos (`*-diag`); manter `hubspot-sync`,
  `treble-inbound-agent`, `mindagent-chat`.
