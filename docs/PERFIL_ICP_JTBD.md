# Perfil profissional da pessoa — ICP, JTBD, cargo e empresa (23/09/2026)

> Decisões da Adriana em 23/09: JTBD e ICP viram **tabelas no schema `intelligence`**; toda pessoa
> que passou pelo Summit 2026, informou cargo/empresa no credenciamento ou conversou com o Mind
> (concierge no app, vendedor no WhatsApp) passa pela classificação; o que a pessoa **escreveu** de
> cargo e empresa vai para `pessoas.pessoas` e para o HubSpot (`jobtitle`, `company`), com guarda
> contra typo e duplicata; as propriedades `icp` e `jtbd` do HubSpot (criadas por ela) são
> populadas a partir do banco. Este documento é o mapa do que existe e o plano do que vem.

## 1. Onde mora cada coisa

| o quê | casa | observação |
|---|---|---|
| catálogo de ICP (13 perfis + concorrente) | `intelligence.icp` | `rotulo` = label da opção no HubSpot; `hubspot_valor` = valor interno (3 opções antigas foram reaproveitadas com significado novo); `rotulo_legado` traduz os textos antigos já gravados em memória |
| catálogo de JTBD (13 jobs "mind" + 15 jobs-raiz JT01–JT15) | `intelligence.jtbd` | `produtos` liga cada job aos produtos no ar (`catalogo.produtos`); `jt_raiz` traduz o que o analisador de conversas emite; `sinais` guarda as regras de evidência |
| jobs que cada sessão do Summit resolve | `summit_2026.sessions.jtbd` | 62 sessões de conteúdo marcadas; check-in/reserva vira evidência |
| classificação de cada pessoa | `intelligence.participante_memoria` | tipo `icp` (chave `icp_atual`), tipo `jtbd` (chave `jtbd:<codigo>`), tipo `cargo`/`empresa`; origem `regra_perfil` quando veio da regra, `analise_*` quando veio de conversa |
| leitura para o Agent | `public.mind_customer_intelligence(mind_id)` | `professional_context.icp` (rótulo + code), `jobs_observed` |
| cargo/empresa da pessoa | `pessoas.pessoas.cargo/empresa` | o que ela escreveu no credenciamento, na forma de exibição (`intelligence.texto_exibir`), empresa com a grafia mais frequente |
| relacionamento com o Mind | `pessoas.pessoas.relacionamento_mind` (`text[]`) | `{lead}` por padrão; `staff`, `palestrante`, `professor`, `parceiro_venda` quando não é lead (pode ter mais de um). Mantido de hora em hora por `pessoas.relacionamento_atualizar()` a partir de `pessoas.relacionamento_derivado()` — só acrescenta; `parceiro_venda` e correções se marcam à mão na coluna. **Quem não é lead não tem ICP nem JTBD** (§2) |
| plano do HubSpot | `public.mind_hubspot_perfil_plano(p_desde)` | uma linha por pessoa: `jobtitle`, `company`, `icp` + `icp_confianca`, `jtbd[]`, `resumo`, `ultimo_escrito` (o que o Mind gravou por último no contato); `p_desde` recorta quem teve memória alterada (ou deixou de ser lead); quem não é lead vem com `nao_lead = true` — só cargo/empresa, e o ICP/JTBD/resumo que houver no contato é limpo; só `service_role` |
| resumo da inteligência por pessoa | `intelligence.perfil_resumo(mind_id)` → propriedade `mind_resumo_inteligencia` do HubSpot | texto por regra (sem IA): perfil, ICP e por quê, jobs ativos com evidência, hipóteses não confirmadas, última conversa (sem saúde pessoal), produtos com fit do job mais forte |
| memória de "última escrita" no HubSpot | `public.mind_admin_audit` (`resource = 'hubspot_contato'`, `record_id` = id do contato) | escrita por `public.mind_hubspot_perfil_registrar` a cada lote gravado; é a guarda que impede o automático de desfazer edição humana |
| automático | `pg_cron` `perfil_projetar_horario` (hh:36) e `hubspot_perfil_writeback_horario` (hh:41); gatilhos `icp_alinhar_hubspot` / `jtbd_alinhar_hubspot` | `intelligence.perfil_projetar_todos` reprojeta todo mundo; `public.mind_hubspot_perfil_disparar` chama a função só para quem mudou nas últimas 2 h; editar o catálogo alinha rótulos/opções no HubSpot |
| escrita no HubSpot | Edge Function `hubspot-perfil-writeback` (v5) | ENSAIO por padrão (`executar: false`); aceita `desde`; relatório com `substituicoes`, `equivalentes`, `conflitos`, `ignorados`, `preservados` (editado no HubSpot depois do Mind), `limpezas` (perfil apagado de quem não é lead) e `registrados` |

## 2. Como a regra decide

**ICP** (`intelligence.icp_por_cargo(cargo, empresa)`): determinístico, sem IA. Ordem das checagens
= decisão: concorrente pela empresa (`regex_empresa`, hoje só Vittude) → fora do mercado ("dona de
casa", aposentado → outros) → "executive"/owner que não é executivo (executive assistant, account
executive, product owner → analista) → **RH com nível** (gerente/diretor/coord/supte de RH, C&B, D&I,
L&D, saúde corporativa → gestor ou CHRO) → saúde → RH (consultor de RH, analista/BP, decisor, gestor) →
consultor/coach → academia → fundador/sócio → C-suite e executivo público (secretário de estado,
prefeito) → diretor → gestor → analista → outros. Aceita siglas e abreviações (coord, ger, dir, supte,
HRD, NR-1, SST). Cargo que é só um nível ("Gerente", "Diretora") entra com confiança 0,55 em vez de 0,70.
**Erro de digitação** (24/09): quando nada casa, cada palavra fora de um vocabulário fechado de nomes de
cargo é comparada com ele (`intelligence.cargo_corrigir_digitacao`: mesma primeira letra; distância 1 até
8 letras, 2 a partir de 9) e a regra roda de novo — "dirrtor", "Diretorna", "emoresaria", "funder",
"coodenador", "Pscióloga". Profissões (advogada, jornalista, engenheiro, economista…) viram
`analista_nao_rh`; `outros` fica só para quem está fora do mercado ou não escreveu um cargo (Adriana,
24/09). Regra completa: `REGRA_ICP_POR_CARGO.md` na raiz. Contrato: `tests/icp_por_cargo_digitacao_contract.sql`.
Fonte do cargo, por prioridade: credenciamento (Yazo) → conversa (`cargo_atual` do analisador) →
espelho do HubSpot → `pessoas.pessoas`. ICP marcado à mão no HubSpot vence — mas o valor que o próprio
Mind escreveu lá (registrado em `mind_admin_audit`) não conta como manual.

**JTBD** (`intelligence.perfil_evidencias` → `intelligence.perfil_projetar`): uma linha por evidência,
depois agregada por job: confiança = maior evidência + 0,05 por evidência extra que não seja reserva
nem contexto (+0,05 no total se houver reserva; teto 0,90); ≥ 0,70 vira memória `ativa`, abaixo vira
`proposta`. **Veto por ICP típico** (`icps_tipicos` do catálogo): job organizacional (programas, ROI,
NR-1, engajar, treinar, consultoria, patrocínio, boa empregadora, vender para RH, autoridade) para uma
pessoa cujo ICP não está entre os típicos do job fica em hipótese (≤ 0,65), a menos que ela tenha
**falado** disso em conversa; os jobs pessoais (liderar melhor, minha saúde e performance, encontrar
pares) não sofrem veto. A regra rebaixa o que ela mesma promoveu quando a evidência some ou a regra
aperta; memória de conversa nunca é tocada.

| evidência | confiança | de onde |
|---|---|---|
| check-in numa sessão marcada | 0,70 (sala < 150 pessoas) · 0,65 (150–299) · 0,55 (300+) | `"Check Ins Summit"` × `sessions.jtbd`; público = check-ins distintos da sessão |
| reserva sem check-in | 0,50 (nunca faz job ativo sozinha; 61% reservaram a mesma plenária) | `"Reservas_Agenda_APP"` |
| interesse/objetivo declarado na jornada do app | 0,50–0,70 (por chave) | `engagement.session_interests` via `sinais.interesses` |
| job-raiz observado em conversa (JT01–JT15) | a confiança da memória | `jt_raiz` + `sinais.jt_filtro` (NR-1 vs programas; JT04 → treinar lideranças só para RH) |
| o que a pessoa disse em conversa (memórias de interesse/objetivo/preferência comercial/delegação/patrocínio/outro e campos da análise) | 0,60, uma por job | `sinais.memoria_regex` por job (ex.: "delegação", "meu time" → liderar melhor; "NR-1", "riscos psicossociais" → NR-1) |
| sinal de patrocínio (memória ou análise) | 0,60 / 0,70 | `sinais.patrocinio` |
| produto preferido em conversa (Dash, consultoria) | 0,70 | `sinais.conversa.preferred_product_regex` |
| contexto por família de ICP | 0,50–0,60 | `sinais.contextual` (RH + liderança → contratar treinamento; especialista + programas/NR-1/ROI → autoridade, vender para RH) |

Regras de convivência: memória de conversa (`analise_*`) nunca é derrubada pela regra — quando
divergem, a regra entra como `proposta`; a conversa grava a própria linha (o escritor não pisa na
linha da regra) e, se entra ativa, a da regra cede; ICP marcado à mão no HubSpot vence (a regra não
escreve); rodar de novo é idempotente e **só carimba `atualizado_em` no que mudou** — esse carimbo é o
sinal que o write-back horário usa.

**Cargo e empresa no HubSpot** (`mapping.ts`): preenche vazio; quando já há valor, compara pela
chave normalizada (`texto_chave`); mesma chave, uma contendo a outra ("CEO / Fundador" × "CEO") ou
distância de edição pequena ("Beiersdorf" × "Beiwrsdorf") = **não escreve** (vai para
`equivalentes`); coisa diferente de verdade = escreve e lista em `substituicoes` para a Adriana rever
(o HubSpot guarda o histórico da propriedade, dá para voltar). Valor novo que parece headline do
LinkedIn/URL/e-mail, passa de 80 caracteres ou é um nível solto ("Gerente") no lugar de um cargo com
área não entra (`pior`). **Guarda de última escrita**: quando o valor que está no HubSpot não é o que
o Mind escreveu por último (`ultimo_escrito`, de `mind_admin_audit`), alguém editou lá depois —
fica como está e vai para `preservados`; quando é o nosso, a mudança do banco passa, inclusive no ICP.
JTBD: se o HubSpot tem exatamente o que o Mind escreveu, o conjunto do banco substitui (job
rebaixado sai); se alguém marcou algo lá, união — escolha humana nunca é apagada.

**Quem não é lead não tem ICP nem JTBD** (regra da Adriana, 23/09: *"se é professor ou parceiro de
venda não é lead e portanto não coletamos JTBD e ICP"*; staff e palestrantes idem). A casa é
`pessoas.pessoas.relacionamento_mind`; as fontes, só por vínculo determinístico (`mind_id`, nunca nome):
staff = credenciamento `staff_mind`, e-mail `@joinmind.com.br`, `seguranca.equipe`, `mind_admin_users`
ativos; palestrante = credenciamento `palestrante`, `ecossistema.perfis_publicos` ligado a
`palestrantes_especialistas`; professor = `institute.programa_pessoas` (formadora, curadoria,
convidado — o time do Institute que o site publica pelo `ecossistema`); parceiro de venda = e-mail (identificador
ou contato do HubSpot) num domínio de `intelligence.config.parceiro_venda_dominios` (hoje `maisdiversidade.com.br`;
*"por enquanto qualquer pessoa da Mais Diversidade"*, Adriana 23/09) ou marca à mão. A caixa genérica
`contato@joinmind.com.br` não faz ninguém staff: a equipe a usa para registrar convidados. Para quem não é lead: `perfil_projetar` apaga a classificação da própria regra e
marca `rejeitada` a de conversa (cargo e empresa ficam — são fato); o escritor de conversa ignora
`icp`/`jtbd` (grava o resto); o leitor do Agent não devolve ICP nem jobs; o plano do HubSpot manda
`nao_lead` e a função **limpa** `icp`, `icp_confianca`, `jtbd` e o resumo do contato — é a única
exceção à regra "a função nunca apaga valor", pedida por ela. O "antes" de cada limpeza fica no
registro de última escrita. Voltar a ser lead (tirar o tipo à mão) faz a regra reclassificar pelo cargo.

**Os prompts de IA que geram inteligência sobre a pessoa também não rodam para quem não é lead** (Adriana,
23/09: *"os prompts que geram inteligência sobre o cliente e lead não rodem para quem é professor, palestrante e
equipe"*). São dois: a análise pós-conversa (`analisar-conversa`, cron `analise_conversas` a cada 15 min —
classificador + analisadores de `agentes.prompts`, que gravam `intelligence.analise_conversa`, memórias e
continuidade) e a reavaliação do Silence (`silence-reavaliar`, cron desligado). Nenhuma das duas está versionada
aqui; a trava está nas três funções que elas consultam antes de chamar a IA: `analise_pendentes` (fila),
`analise_montar_contexto` (devolve `{nao_lead: true, transcrito: []}` — sem fala do lead a Edge Function não chama
a IA) e `silence_claim_pendentes`. O atendimento não muda: concierge, vendedor e router continuam respondendo a
professor, palestrante, staff e parceiro. Contrato: `tests/analise_nao_lead_contract.sql`.

## 3. O que foi feito em 23/09

- Migrations aplicadas em produção (ledger): `20260923081119 intelligence_icp_jtbd_catalogos`,
  `20260923081602 sessions_jtbd_marcacao_2026`, `20260923081831 intelligence_perfil_regra`,
  `20260923082020 intelligence_perfil_projetar_alias`, `20260923082744 escritor_e_leitor_validam_pelos_catalogos`,
  `icp_por_cargo_business_partner_nao_e_socio`.
- Classificação rodada para 3.855 pessoas (`perfil_projetar_lote`, 16 fatias): 2.250 ICPs `ativa`
  (+17 `proposta` divergentes da conversa), 6.970 jobs `ativa` + 4.990 `proposta`, 1.779 cargos e
  1.677 empresas como memória. Distribuição de ICP: psicólogo/saúde 321 · gestor não RH 305 ·
  diretor/VP não RH 249 · fundador/sócio 232 · gestor de RH 205 · CEO/C-suite 185 · consultor/coach
  160 · CHRO/diretor de RH 150 · analista/BP de RH 141 · outros 120 · analista não RH 109 ·
  professor/estudante 58 · consultor de RH 32 · concorrente 4.
- `pessoas.pessoas`: 1.815 cargos e 1.667 empresas gravados a partir do credenciamento.
- Escritor (`analise_projetar_memoria`) e leitor (`mind_customer_intelligence`) passam a validar pelos
  catálogos; o analisador de conversas continua emitindo JT01–JT15 e os 6 rótulos antigos de ICP, e
  tudo é traduzido na escrita/leitura.
- Edge Function `hubspot-perfil-writeback` publicada; ensaio: 2.627 pessoas no plano, 2.587 com
  contato no HubSpot; resultado da execução em `CHECKPOINT_ATUAL.md`.

**Tarde de 23/09 (segunda rodada, autônoma, com revisão crítica — §6):**

- Guarda de última escrita: `mind_hubspot_perfil_registrar`, `mind_admin_audit` (`hubspot_contato`),
  plano v2/v3 com `p_desde`, `resumo`, `ultimo_escrito` (`20260923085242`, `093258`).
- Revisita da inteligência gravada por regra: `sinais.memoria_regex` por job + fonte `memoria_texto`
  em `perfil_evidencias` (`20260923090316`); 60 hipóteses novas, 700 evidências de fala.
- Revisão da regra (`093110`): pesos por tamanho da sala, reserva 0,50, veto por ICP típico,
  rebaixamento, cargo ampliado (26 casos no contrato), ICP manual só quando não é do Mind,
  `texto_exibir` em caixa mista. Resultado: jobs ativos **7.068 → 3.844**, pessoas com 6+ jobs
  **221 → 34**, média 2,4 jobs por contato; `escolher_programas` 1.507 → 422, `provar_retorno` 835 → 141.
- Leitores (`093258`): resumo por regra (produtos só do job mais forte), plano sem ICP/JTBD/resumo para
  staff e palestrantes (46), `mind_customer_intelligence` com `source`/`evidence` e até 5 jobs.
- Escritor (`095020`): conversa não pisa na linha da regra; a regra é dona só da própria linha.
- HubSpot, v4 da função: propriedades `icp`/`jtbd` alinhadas ao catálogo (rótulo "Fundadot" corrigido,
  ordem), `mind_resumo_inteligencia` criada pela função (o token tem `crm.schemas.contacts.write`);
  execução em 4 lotes: **2.288 contatos**, 0 erros, 2.288 registros de última escrita; `jtbd` 1.368
  (1.343 conjuntos corrigidos), `mind_resumo_inteligencia` 2.252, `icp` 72 (BPs que estavam como CHRO),
  `jobtitle` 1 gravado e **5 preservados** (editados no HubSpot entre as duas rodadas — a guarda funcionou).
- Automático ligado (`pg_cron` hh:36 projeção, hh:41 write-back de quem mudou; gatilhos nos catálogos).

**Fim da tarde de 23/09 — relacionamento com o Mind (pedido dela: "limpa ICP e JTBD de staff e
palestrante do HubSpot e backend… professor ou parceiro de venda não é lead").**

- Migration `20260923143941 pessoas_relacionamento_mind_e_regra_nao_lead`: coluna
  `pessoas.pessoas.relacionamento_mind` (check: tipos conhecidos, `lead` nunca junto de outro),
  `pessoas.e_lead`, `pessoas.relacionamento_derivado`, `pessoas.relacionamento_atualizar` (roda no começo
  de `perfil_projetar_todos`, hh:36), a regra em `perfil_projetar`, no escritor, no leitor e no plano.
  Corrige também um erro do `095020`: o escritor perdia a memória de JTBD de conversa quando a regra já
  tinha o mesmo job **ativo** (o `update` que rebaixa a linha da regra sobrescrevia o `FOUND`) — caso A
  no contrato.
- Banco: **80 pessoas não são lead** — 57 palestrantes, 22 staff, 4 professores (3 com dois tipos);
  15.525 leads. Apagadas as memórias de ICP/JTBD da regra dessas pessoas (210, medidas antes da
  migration); 1 de conversa virou `rejeitada`; 0 ativas ou propostas restantes.
- HubSpot (v5, 14:47 UTC): 41 contatos, **86 limpezas** — `icp` 39, `icp_confianca` 39, `jtbd` 6,
  resumo 2; 0 erros; 41 registros de última escrita. Ensaio seguinte: 0 a escrever, 0 a limpar.
- Contrato `tests/perfil_icp_jtbd_contract.sql` → `PERFIL_OK` em produção (com rollback): caso A do
  escritor e a seção não-lead (check da coluna, atualizador só acrescenta, regra apaga/rejeita e é
  idempotente, escritor ignora ICP/JTBD e grava o resto, leitor sem ICP/jobs, plano `nao_lead`, recorte
  por data, volta a lead). Testes Node do `mapping.ts`: 45.

**Noite de 23/09 — IA fora de quem não é lead, fusões, parceiros e limpeza (decisões da Adriana).**

- `20260923145909`: os prompts de inteligência (análise pós-conversa e Silence) não rodam para não-lead
  (§2). Antes da trava, a análise ainda rodava para eles: 84 análises de 16 não-leads, a última às 14:55
  UTC. Contrato `tests/analise_nao_lead_contract.sql` → `ANALISE_NAO_LEAD_OK` em produção.
- Fusões pela porta única (`mind_fusao_decidir`, 8, 0 erros): Adriana Drulla (3 registros → 1; o nome da
  sobrevivente, "Adriana Campos", foi corrigido para "Adriana Drulla" — HubSpot, credenciamento e site dizem
  Drulla), Tamara Myles, Elaine Lizeo, Ivana Moreira (3 → 1), Juliana Elorza e Thiago Araújo (taraujo@ ×
  "Thiago Araujo Ferreira Barros"). O Thiago Barros de thiago@ **não** foi fundido: CPF e telefone
  diferentes — é outra pessoa. As sobreviventes herdaram perfil público e papéis do Institute.
- `20260923150946`: parceiro de venda por domínio (Mais Diversidade → 13 pessoas) e `contato@` fora do
  staff. HubSpot: 13 contatos, 22 limpezas, 0 erros.
- Apagadas as 3 contas "ZZ TESTE — apagar" (e os 3 leads de teste do pipeline inbound ligados a elas). A
  "Mayra Andrade Jacó Hnk" **não** foi apagada: é convidada do camarote Heineken, com ingresso, venda e
  check-in nos dois dias; era "staff" só pelo `contato@` usado no registro — voltou a lead.
- Hoje: 15.514 leads; 53 palestrantes, 17 staff, 15 parceiros de venda (13 da Mais Diversidade pelo domínio
  + Igor Gomes Menezes e Esabela Cruz à mão), 4 professores.

## 4. Plano — o que vem, na ordem (autônomo, com os gates marcados)

> Estado em 23/09 (tarde): **1, 2, 3, 4a e 5 feitos**; 4b (IA) continua atrás do gate de custo; 6 é o modo de operação.

1. **Escrita no HubSpot** (hoje): `executar: true` em `hubspot-perfil-writeback`; relatório de
   `substituicoes` fica no checkpoint para a Adriana rever. Gate D1 já exercido por ela em 23/09.
2. **Guarda de "última escrita"** (antes de qualquer automático): a função passa a registrar em
   `public.mind_admin_audit` o que escreveu por contato; o plano passa a saber o último valor que o
   Mind escreveu, e a regra vira: *só sobrescreve o que estiver vazio ou igual ao que o próprio Mind
   escreveu por último* — edição humana no HubSpot nunca é desfeita por um cron.
3. **Automático**: `pg_cron` de hora em hora chama a função com `executar: true` para quem teve
   memória `icp`/`jtbd`/`cargo`/`empresa` atualizada desde a última escrita (coluna `atualizado_em`
   de `participante_memoria`); assim, mudar a classificação no banco muda o HubSpot sozinho. Trigger
   em `intelligence.icp`/`intelligence.jtbd` chama `acao: "propriedades"` para alinhar rótulos/opções
   quando ela editar o catálogo — exige o escopo `crm.schemas.contacts.write` no app privado do
   HubSpot (hoje não sabemos se o token tem: a introspecção do token não devolve escopos; a própria
   chamada em ensaio diz `escopo_faltando` quando falta).
4. **Revisitar toda a inteligência já gravada com a lente ICP/JTBD**
   a. *Sem IA (regra, primeiro)*: as 7.1 mil memórias de `interesse`, `objetivo`, `preferencia_comercial`,
      `delegacao` e `patrocinio` ganham leitura por expressão regular por job (`sinais.memoria_regex`
      no catálogo) e viram evidência em `perfil_evidencias`, combinadas com a família do ICP — o
      exemplo dela: "interesse em delegação" + diretora de RH → `treinar_liderancas` (contexto) e
      `liderar_melhor`.
   b. *Com IA*: nova versão do prompt de `analisar-conversa` (Edge Function crítica, deploy manual)
      que emite ICP com os 13 rótulos, JTBD com os 13 jobs mind além dos JT raiz, e um **resumo da
      inteligência** de 3 linhas por pessoa; reprocessar as 4.921 análises existentes. **Gate**: custo
      e tempo do reprocessamento (modelo em `intelligence.config.openai_model`) — decisão dela.
5. **Resumo da inteligência no HubSpot**: propriedade de texto (multi-linha) — sugestão de nome
   `mind_resumo_inteligencia`, rótulo "Resumo da inteligência (Mind)" — que ela cria no HubSpot como
   fez com `jtbd` (ou a função cria, se o token tiver o escopo), preenchida por
   `intelligence.perfil_resumo(mind_id)`: cargo/empresa, ICP e por quê, jobs com a evidência, último
   objetivo em conversa, produto preferido, próxima ação sugerida. Entra no mesmo write-back e no
   mesmo automático. Enquanto a IA (4b) não existe, o resumo é por regra (template).
6. **Manutenção do catálogo pela Adriana**: editar `intelligence.icp` / `intelligence.jtbd` (rótulos,
   produtos, sinais, novos concorrentes em `regex_empresa`) é o jeito de mudar o sistema; nada é
   fixo em código.

## 5. Pendências pequenas

- ~~Opção `Fundadot / Sócio / Empreendedor` com typo~~ — rótulo corrigido pela função em 23/09 (o valor
  interno `Fundadot…` fica: é interno, contatos apontam para ele).
- `icp_confianca` no HubSpot recebe 7 (regra por cargo) ou 6 quando o cargo é só um nível ("Gerente").
- 18 pares de pessoas do banco apontam para o **mesmo contato** no HubSpot (`contato_repetido_no_recorte`):
  candidatas a fusão em `engagement.identidade_fusoes` — decisão dela.
- `treinar_liderancas` e `autoridade_escala` só aparecem por contexto (0,5–0,6 → `proposta`);
  para virarem `ativa` precisam de evidência direta (conversa ou 4a).

## 6. Revisão crítica de 23/09 (o que foi aplicado e o que ficou)

Um revisor independente (só leitura) mediu a primeira rodada: 34/40 ICPs corretos numa amostra
aleatória, mas ~110 fornecedores (CEO de consultoria, dono de clínica) rotulados como compradores;
8/15 pessoas com pelo menos um job ativo injustificado; `escolher_programas` em 82% dos contatos e
`liderar_melhor` em 85% (uma lista por job = a base inteira); 14,7% das ativas sustentadas só por
reservas; `perfil_projetar` nunca rebaixava; `hubspot_manual_vence` congelaria o ICP de todo mundo no
próximo espelho diário; `jtbd` como união nunca removia job errado. Os números, a amostra e a crítica
inteira estão no relatório do revisor (sessão de 23/09) e resumidos em `BACKLOG.md` §21.

**Aplicado no mesmo dia** (migrations `093110`, `093258`, `095020`, `mapping.ts` v4): pesos por
tamanho da sala e reserva fraca; agregação sem empilhar reservas; veto por ICP típico; rebaixamento;
regra de cargo ampliada (26 casos); ICP manual só quando não é do Mind; `texto_exibir` em caixa mista;
resumo com produtos só do job mais forte; staff/palestrantes fora do ICP no HubSpot; leitor com
fonte/evidência; JTBD como conjunto quando o HubSpot tem o que o Mind escreveu; guarda de qualidade do
valor novo (headline/URL, nível solto); escritor não pisa na linha da regra; `memoria_regex` sem
tokens largos (certificação, indicadores).

**Ficou para depois, com gate** (BACKLOG §21): tradução de evidência por família (fornecedor que vai
a sessão de programas → `vender_para_rh` com o mesmo peso); valores internos novos no HubSpot para os
3 rótulos reaproveitados; empresa como sinal (fornecedor de bem-estar, gente da casa, `summit_2026.exhibitors`);
peso de reserva por sessão; reprocessamento das análises de conversa com prompt novo (custo — dela);
rótulo "Cuidar da minha saúde mental e performance" no CRM (decisão de produto); "Outros" gravado em
~120 contatos (limpar por lista no HubSpot — a função não apaga valor de lead); ~~ICP/JTBD já gravados
em 41 staff/palestrantes~~ — limpos pela v5 em 23/09 (regra do não-lead, §2); 5 legados manuais lidos
com o rótulo novo pelo *fallback* do CRM.
