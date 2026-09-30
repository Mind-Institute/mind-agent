# Plano de coleta — Relatório de valor para o patrocinador (Mind Summit 2026)

> 24/09/2026. Pedido da Adriana: montar o plano para coletar os dados do relatório de valor para
> o patrocinador. O relatório não é "do evento". A lista de 61 dados e os 8 blocos são dela. Aqui
> cada dado aponta para **onde está hoje**, **o que falta construir** e **o que depende de gente
> ou de decisão**. A investigação foi feita no banco real (`mind-agent`, Supabase `ymnmotgglsrxmjmonwjz`).

Legenda: ✅ já existe e dá para contar hoje · 🟡 existe, mas precisa derivar/classificar ·
❌ não está no sistema e precisa ser coletado · 🔒 depende de gate da Adriana.

## 0. Base e números-âncora (já medidos)

| o quê | fonte | hoje |
|---|---|---|
| inscritos válidos | `credenciamento_summit_2026.controle_de_inscritos_e_presenca` (`valido_no_mind = 'sim'`) | **2.472** (105 cancelados à parte) |
| presentes (pelo menos 1 dia) | idem, `presenca_16_09` / `presenca_17_09` | **1.963** → comparecimento **79%** |
| Dia 1 · Dia 2 · os dois | idem | **1.770 · 1.558 · 1.365** (77% dos presentes do D1 voltaram) |
| empresa por pessoa | `pessoas.pessoas.empresa` (rodada de hoje, `crm.empresa_participantes_summit_2026()`) | 2.022 de 2.421 com empresa; 1.104 casadas com uma company do HubSpot |
| espelho de empresas | `crm.empresa_espelho` (novo) | 4.424 companies; setor em 3.066, funcionários em 3.218, receita em 396 |

**Regra de base:** todo número de audiência sai de **presentes**, não de inscritos (o que ela pediu:
"número de pessoas presentes, não número de inscrições"). Staff e palestrantes ficam fora (colunas
`staff_mind`, `palestrante` do controle; `pessoas.relacionamento_mind`).

## 1. Dimensão do Summit

| # | dado | status | fonte / como |
|---|---|---|---|
| 1 | inscritos | ✅ | controle, `valido_no_mind` |
| 2 | participantes únicos | ✅ | controle por `mind_id` canônico (`mind_pessoa_canonica`) |
| 3–5 | presentes D1, D2, nos dois | ✅ | controle (`presenca_*`, fonte Worknet em `credenciamento_worknet`) |
| — | % que voltou no D2 | ✅ | 1.365 / 1.770 |
| 6 | ticket (Mind/VIP/Prime) | ✅ | controle `categoria` + `participantes.ticket_type` |
| — | nº de empresas representadas | 🟡 | `pessoas.empresa` dos presentes. Contar por **company do HubSpot** quando houver (`hubspot_company_id`) e por nome nos outros casos. Antes, resolver os aliases (ver §3) |
| — | palestrantes · sessões · horas de conteúdo | ✅ | `summit_2026.session_speakers`, `summit_2026.sessions` (`duracao_min`, `tipo`, `formato`) |
| — | workshops/masterclasses | ✅ | `sessions.tipo`/`formato` |
| 37 | ocupação média das sessões | 🟡 | check-ins por sessão (`"Check Ins Summit"`, 9,7 mil) ÷ `sessions.vagas_total`. Palco principal sem vaga fixa: usar capacidade da sala (❌ pedir à produção) |

## 2. Quem estava na sala

| # | dado | status | fonte / como |
|---|---|---|---|
| 7 | cargo | ✅ | `pessoas.cargo` (credenciamento, gravado em 23/09) |
| 8 | **senioridade** (C-level/founder, VP, diretor, head, gerente, coordenação, especialista, outros) | 🟡 **construir** | Não existe hoje. Proposta: função determinística `intelligence.senioridade_por_cargo(cargo)`, igual ao `icp_por_cargo` (regex + siglas; sem IA). É a menor mudança e não cria tabela |
| 9 | área funcional (RH/People, gestão geral, marketing, comercial, estratégia, saúde, consultoria…) | 🟡 **construir** | Mesma função, com saída `area`. Hoje o `icp_por_cargo` já separa RH, saúde e consultor |
| 10 | ICP do Mind | ✅ | `intelligence.participante_memoria` (tipo `icp`), catálogo `intelligence.icp`: 13 perfis, em produção desde 23/09 |
| 11 | localização | 🟡 | cidade/UF do contato no HubSpot (`crm.contato_espelho.propriedades`); cobertura a medir. Alternativa: DDD do WhatsApp |
| — | "% decisores ou influenciadores" | 🟡 | Sai da senioridade (gerente+) somada ao ICP. **Só afirmar com cobertura ≥ 80% dos presentes com cargo** |

## 3. As empresas presentes

| # | dado | status | fonte / como |
|---|---|---|---|
| 12–14 | declarada · pelo domínio · normalizada | ✅ | feito hoje (`crm.empresa_participantes_summit_2026()`; auditoria em `mind_admin_audit`, resource `pessoas_empresa_summit_2026`) |
| — | aliases/duplicatas a resolver antes de contar | 🔒 **decisão** | "BDF Nivea" × Beiersdorf; "Editora Sextante" × GMT Editores; "Faculdade BP" × Beneficência Portuguesa; Heineken × HNK BR (duas companies no HubSpot). Precisa de uma decisão por par (fundir no HubSpot ou só agrupar no relatório) |
| 16–17 | nº de funcionários · porte | 🟡 | `crm.empresa_espelho.numberofemployees` cobre 73% das companies. Para as ~918 pessoas com empresa fora do HubSpot: enriquecer com **Lusha** (`prospecting_company_enrich`, conector já ligado) ou criar a company no HubSpot. Criar é write-back, então 🔒 |
| 18 | multinacional × nacional | ❌/🟡 | Não há campo. Usar `country` da company como proxy fraco, ou a Lusha (HQ). Marcar à mão o Top 50 |
| 19–21 | pessoas por empresa · Top 20 sem patrocinador · empresas com 2+, 5+, 10+ | ✅ depois da decisão de aliases | Patrocinadores vêm da coluna `"Empresa Patrocinadora, quando aplicável"` do relatório da Yazo (Heineken 135, BWG 89, Vale 43, WellZ 36, Beiersdorf 23, Sextante 22…). **Excluir por empresa e também por ingresso de cortesia do patrocinador** |
| — | "% em empresas com +1.000 funcionários" | 🟡 | depende de 16. Só publicar com cobertura conhecida ("entre os X% com porte identificado…") |

## 4. Setores

| # | dado | status | fonte / como |
|---|---|---|---|
| 15 | setor | 🟡 | `crm.empresa_espelho.industry` (69% das companies; enum do HubSpot em inglês). Construir o de-para `industry` → os ~14 setores da lista dela (tabela de tradução pequena, ou `case` numa view). Completar o resto com a Lusha |
| — | nº de setores · Top 10 | ✅ depois do 15 | contagem por presentes |

## 5. Engajamento no app

| # | dado | status | fonte / como |
|---|---|---|---|
| 22 | downloads | ❌ | A Yazo não mandou. **Pedir à Yazo** (ou App Store/Play, se o app é deles, é com eles) |
| 23 | ativações | ✅ | Yazo consolidado, `"Data/horário do primeiro acesso"` não nulo |
| 24–25 | ativos · taxa de adoção | 🟡 | ativos = acesso nos dias 16–17/09 (`"último acesso"` só guarda o último). **Pedir à Yazo os ativos por dia (D1, D2)**; hoje dá para medir "ativou" e "acessou durante/após o evento" |
| 26–27 | sessões adicionadas · média por usuário | ✅ | `"Reservas_Agenda_APP"` (21 mil) e `"Favoritos em agendas"` |
| 28–30 | conexões · quem conectou · contatos trocados | ✅ | Yazo: `"Trocas de contato"` (por pessoa: soma, % com ≥1, mediana) |
| 31 | mensagens | ✅ | Yazo: `"Mensagens trocadas"`. Feed: `Postagens`, `Curtidas`, `Comentários` |
| 32–34 | páginas vistas · cliques · materiais baixados | ❌ | Sem telemetria no banco (`engagement.jornada_eventos` vazio). **Pedir à Yazo** o analytics de telas, banners e materiais, **por patrocinador** (logo/banner clicado) |
| 35 | perguntas ao Concierge | ✅ | `engagement.conversas` + `engagement.mensagens` (canal app) e `intelligence.analise_conversa` (4,9 mil análises). Temas: `engagement.session_interests` |

## 6. O que as pessoas queriam

| # | dado | status | fonte / como |
|---|---|---|---|
| 36 | audiência por sessão | ✅ | `"Check Ins Summit"` (com `sessao_id`) |
| 38 | agenda saves | ✅ | reservas + favoritos |
| 39 | temas mais procurados | ✅ | `summit_2026.sessions.jtbd` / `trilhas` × check-ins; Concierge (`session_interests`, `analise_conversa`) |
| 40 | NPS/avaliação por conteúdo | 🟡 **amostra pequena** | `engagement.avaliacao_do_evento` (28 respostas), `avaliacao_do_dia` (39), `…_atividade` (437 notas de 0–5; **não é NPS**). `engagement.nps` está vazio. Não publicar nota por sessão com n < 20 |
| 41 | workshops mais disputados | ✅ | reservas + fila de espera (`"Fila de espera"`) ÷ vagas |
| 42 | perfil da audiência por tema | ✅ depois de 8 e 9 | check-in × ICP/senioridade/área (ex.: "entre RH, segurança psicológica no top 3") |

## 7. Resultado por patrocinador (2 a 4 páginas cada)

| # | dado | status | fonte / como |
|---|---|---|---|
| 43–45 | contratado · entregue · extras | ❌ | **Não está em sistema nenhum** (o `mind-summit-propostas` só tem nome e logo). Montar uma planilha por patrocinador com o time comercial e a produção, a partir dos contratos |
| 46 | exposição digital | ❌/🟡 | site/app/e-mails: HubSpot (e-mails com a marca → aberturas, via `get_marketing_email_analytics`); Instagram/LinkedIn: **Supermetrics** (conector ligado) para os posts que citam a marca |
| 47 | exposição física | ❌ | produção: lista de peças + fotos. Impressões = presentes no espaço/dia |
| 48–52 | visitas · leads · qualificados · reuniões · QR | ❌ | **Pedir a cada patrocinador** o que capturou; do lado Mind, check-in nas sessões/ativações que tinham `sessao_id` |
| 53–54 | audiência do conteúdo patrocinado + perfil | ✅ depois de 8 e 9 | check-ins das sessões do patrocinador × empresa/senioridade/ICP. Falta marcar **qual sessão é de qual patrocinador** (❌ um de-para curto, feito pela produção) |
| 55 | social/earned media | ❌ | Supermetrics + clipping da assessoria |
| — | **qualidade da audiência por patrocinador** | ✅ depois de 3, 8 e 16 | a mesma base, filtrada pelo que importa a cada um |
| — | Target Account Match (2027) | 🟡 pronto para receber | com o espelho de companies e `hubspot_company_id` por pessoa, a lista de contas do patrocinador casa por domínio e nome, pela mesma regra de hoje. Dá para oferecer já em 2026 como piloto |

## 8. Percepção

| # | dado | status | fonte / como |
|---|---|---|---|
| 56–59 | NPS geral · satisfação · voltar · recomendar | 🟡/❌ | só as 28 + 39 avaliações (0–5). Para NPS de verdade: **pesquisa pós-evento** |
| 60–61 | recall de patrocinadores · contribuição das marcas | ❌ 🔒 | **pesquisa pós-evento** (chamar de *recall pós-evento*, não *brand lift*). É **outbound para ~1.963 pessoas: precisa do gate da Adriana** (texto, canal, lista, horário). Canal sugerido: e-mail pelo HubSpot + WhatsApp só para quem tem janela |

## Ordem de execução proposta

**Fase A — hoje/amanhã, só banco (sem gate):**
1. `intelligence.senioridade_por_cargo()` e `area_por_cargo()` determinísticas, com contrato de teste, como o `icp_por_cargo`.
2. View `intelligence.v_relatorio_patrocinador_audiencia`: 1 linha por **presente**, com dias, ticket, cargo, senioridade, área, ICP, empresa, company do HubSpot, setor, porte, patrocinador de origem do ingresso e engajamento do app (métricas da Yazo). Todos os blocos 1–6 saem dela.
3. De-para `industry` do HubSpot → setores da lista.
4. Números dos blocos 1, 2, 5 e 6 com a cobertura de cada um explícita.

**Fase B — decisões e pedidos (esta semana):**
5. 🔒 Adriana decide os pares de aliases de empresa (fundir no HubSpot ou só agrupar).
6. 🔒 Enriquecer porte/setor das ~918 pessoas cuja empresa não está no HubSpot: Lusha (custo de créditos) e/ou criar as companies no HubSpot (write-back).
7. Pedir à **Yazo**: downloads, ativos por dia, telas/cliques/banners por patrocinador, materiais baixados.
8. Pedir à **produção/comercial**: contratado × entregue × extras por patrocinador, peças físicas com fotos, sessões patrocinadas (de-para sessão → patrocinador) e capacidade das salas.
9. Pedir a **cada patrocinador**: leads, scans e reuniões da ativação.

**Fase C — percepção (depende de gate):**
10. 🔒 Pesquisa pós-evento curta (NPS, voltar, recall aided de patrocinadores, contribuição). Quanto antes, melhor: o recall decai rápido.

**Fase D — montar:** relatório geral (Audience + Engagement + Delivery) e 2–4 páginas por patrocinador.
A segunda devolutiva (60–90 dias, leads → reuniões → pipeline) usa a mesma view mais o que cada patrocinador reportar.

## Cuidados de método

- Toda porcentagem vem com o **denominador** e a **cobertura** ("entre os N presentes com cargo identificado…").
- Patrocinador sai do Top 20 por empresa **e** por ingresso de cortesia (Heineken tem 96 pessoas; a maioria veio pelo patrocínio).
- Avaliação 0–5 não é NPS; não converter.
- Nada de afirmação por tema/perfil com n < 20.
- Recall sem medição pré-evento **não é brand lift**.
