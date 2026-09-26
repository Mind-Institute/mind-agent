# CHECKPOINT ATUAL — go-live Vendedor + Concierge

> **Leia este arquivo primeiro se estiver entrando no projeto sem contexto.**
>
> Atualizado em **04/09/2026**. O estado operacional mais recente está consolidado
> em `IMPLEMENTATION_STATUS.md`; a auditoria do incidente do App está em
> `INCIDENTE_CONCIERGE_20260903.md`.

### Catálogo no painel · Summit fora de venda · Join no mesmo banco — 25/09/2026

Da Adriana (25/09): *"O Summit não tá mais à venda. Pode parar de copiar a cada 30 minutos."* ·
*"As ofertas do instituto precisam ser todas as ofertas do Mind. Vão ser manipuladas a partir de um
painel de admin ligado ao agente aqui."* · *"comece a tela de catálogo primeiro"* · *"vou querer editar
no frontend e essa edição ir para o backend quando eu quiser salvar"* · *"o git deve ser o git do mind
agent"* · *"Pare de dizer que o Vinicius irá executar qualquer coisa"*.

- **Catálogo no painel — EM PRODUÇÃO no banco e na função; a tela sai no merge.** `/catalogo` no
  `admin/` lê e edita `catalogo.produtos`. Banco: `mind_admin_read_catalogo` e
  `mind_admin_mutate_catalogo` (ledger `20260925183716`, arquivo com o mesmo número e md5), só
  `service_role` executa; papel conferido de novo, versão obrigatória (409 em conflito), antes/depois em
  `mind_admin_audit` (`resource = 'products'`); `codigo` (chave de 13 tabelas) e `schema_dados` não se
  editam; nada se cria nem se apaga. Contrato `tests/catalogo_painel_contract.sql` → `CATALOGO_OK`
  (rodado em produção, sem rastro). Edge Function nova `mindagent-catalogo` **v2 viva = o código do
  repo**, `verify_jwt = false` (valida a sessão por dentro, como a `mindagent-home`); conferida pelo
  `pg_net`: `health` 200, sem login 401, origem estranha 403, token falso 401. A tela manda ao banco só
  o que mudou (a janela de venda guarda segundos). Painel: 218/218 testes, build Cloudflare verde.
- **Summit fora de venda — executado.** Jobs `mindagent-sync-precos` (30 min, ledger `20260925181108`)
  e `mindagent-sync-disponibilidade-diaria` (21h, ledger `20260925182409`) desligados, não apagados. As
  3 linhas do Lote 7 passaram a `ativo = false`, `publico = false`. Nenhuma oferta do Summit ativa.
- **Projetos do Summit fora deste banco — decisão dela:** `mind-summit-vendas-dashboard` **nunca
  apagar** (pode virar "mind financeiro"; renomear não quebra nada, este banco usa o ref
  `tkludhksqcnhhpgqyfqq`) — é a única conta com token válido da Eduzz e a origem do
  `eduzz-espelho-sync`, por onde entram as vendas do Institute (30 desde 18/09). `app-palestrantes` e
  `convites-temporario` ficam. O site do Summit fica no ar como está. `mind-summit-propostas`: **deixar
  inativo, não apagar** — **não pausado ainda**: o site do Summit ainda chama a função `site-lote` dele
  (10 vezes em 24 h, de um worker Cloudflare) e a `pricing` foi aberta por navegadores; pausar faz essas
  chamadas falharem. Decisão dela (25/09): não mexer nele por enquanto.
- **Decidido (produto):** o painel único é o `admin/` deste repo, servido pelo worker `mind-agent`. O
  modelo de oferta do Institute vira o de todas as ofertas do Mind; **onde ele mora** (generalizar
  `institute.ofertas` por `produto_codigo` ou ocupar `catalogo.ofertas`, hoje vazia) é troca de
  autoridade — D2 antes de implementar. Docs (`CLAUDE.md`, `AGENTS.md`, `PROJECT_STATE.md`, mapa vivo):
  D2 continua com ela como única aprovadora; a atribuição de execução ao Vinicius saiu.
- **Verificado — Join:** `joinmind.com.br` e `mindinstitute` usam este projeto (`ymnmotgglsrxmjmonwjz`).
  O `/admin` do joinmind está no código publicado, mas não está em uso: a única conta da equipe não é a
  da Adriana (último login 17/09), nas últimas 24 h só houve acesso sem login (401), 7 das 9 telas servem
  o checkout próprio, desligado desde 16/09, e a última mudança de oferta (21/09) foi SQL direto.
- **Auditoria de acesso (login com Google — auditar antes, implementar depois):** 4.156 usuários de
  login, 4.155 anônimos (o app); **uma** conta com e-mail e senha, a única de `mind_admin_users` e de
  `seguranca.equipe`. Nenhuma identidade Google. A Adriana não tem conta própria neste projeto.
  A equipe do Mind está em `pessoas.pessoas.relacionamento_mind` (15 pessoas `staff`, 14 com e-mail
  `@joinmind.com.br` em `engagement.identidades`) — ser staff não dá acesso ao painel; quem dá é
  `mind_admin_users`, por `user_id`.
- **Permissões de função — EXECUTADO (decisão dela, 25/09).** As 19 funções internas das filas
  (`silence_*`, `summit_*` de status/contato, `treble_*` de evento/status) e `espelho_para_mind` passaram
  a ser só do `service_role` (ledger `20260925201217`, arquivo com o mesmo número e md5). Quem as chama
  é o próprio sistema (chave secreta e os jobs `treble_status_dia`/`treble_status_noite`); nada mais
  dependia delas, e as chamadas do sistema seguiram em 200 depois da troca. **Função nova nasce sem
  EXECUTE para PUBLIC** (padrão global do postgres): a migration concede explicitamente a quem chama.
  Contrato `tests/permissoes_funcoes_contract.sql` → `PERMISSOES_OK`. Pedido dela, na sequência: as duas
  portas do site, `mind_origem` e `mind_utm_registrar`, também fecharam (ledger `20260925212628`; sem uso:
  `engagement.utm_sessoes` parou em 22/08). Aberta de propósito ficou só `mind_fusao_decidir`, que confere
  admin/aprovador por dentro. No `mind-summit-vendas-dashboard` (fora deste git), as 4 funções do espelho
  de lá (`espelho_blinket_*` e `espelho_cupons_*`, fire e load) passaram a ser só do sistema (ledger de lá
  `20260925212819`); os jobs delas rodam como o dono e seguem iguais.
- **Segredo do espelho de vendas — trocado (25/09).** O par `intelligence.config.vendas_espelho_segredo`
  (aqui) ↔ `mind_agent_espelho_segredo` (Vault do `mind-summit-vendas-dashboard`) ganhou valor novo,
  gerado no banco e levado de um projeto ao outro por `pg_net`, sem passar pela conversa; a porta
  temporária da troca foi apagada. Sessões antigas da conta admin encerradas.
- **Admins do sistema por Mind ID — banco e função no ar; o login Google espera a configuração dela.**
  Da Adriana (25/09): *"não é backoffice mas admins deste sistema e daí sim podemos fazer por Mind ID e
  sempre antes de colocar a pessoa ela deve existir como um Mind ID e em Mind ID da equipe tem que poder
  marcar equipe para não confundir com lead"*; e, antes, *"mesmo banco, porta própria"*.
  - `mind_admin_users` ganhou `mind_id` (ledger `20260925232508`, arquivo com o mesmo número e md5):
    a pessoa tem que existir, não pode ser fundida e, com acesso ativo, tem que estar marcada como
    equipe (`staff` em `relacionamento_mind`, a marca de 23/09). A lista nunca cria pessoa. `user_id`
    fica vazio até o primeiro login; chave nova `id`. A conta genérica antiga (sem pessoa) vale até o
    Google entrar e depois sai.
  - `mind_admin_vincular_login` (só `service_role`) liga a conta no primeiro login: Google, e-mail
    verificado @joinmind.com.br, uma pessoa só com esse e-mail, acesso ativo e equipe; o login vira
    identidade pela porta única, sem criar pessoa. Contrato `tests/admins_do_sistema_contract.sql` →
    `ADMINS_OK` (12 casos, rodado em produção, sem rastro).
  - A Adriana é a primeira admin, pelo Mind ID. Edge Function nova `mindagent-acesso`
    (`POST /admin/vincular`), **v1 viva = o código do repo**, conferida pelo `pg_net`. Painel: botão
    "Entrar com o Google da Mind" (PKCE, `hd=joinmind.com.br`); 403 em `/admin/me` → vincula uma vez
    → `/admin/me` de novo. Painel 223/223, raiz 419/419, build verde.
  - **Falta (dela):** app de login "Interno" no Google Workspace; Client ID e Secret colados no
    provedor Google do Supabase; Redirect URLs do painel (produção e previews). Depois: tirar e-mail e
    senha do painel, apagar a conta genérica, aposentar `seguranca.equipe` e o admin antigo do Join,
    endereço próprio do painel e a tela "Admins do sistema" para ela dar e tirar acesso.
- **Painel em `admin.minddash.pro` (pedido dela, 26/09).** O domínio foi ligado por ela ao worker
  `mind-agent` pelo painel da Cloudflare. O mesmo worker separa por endereço: ali só o painel (raiz e
  navegação levam a `/admin/`, arquivo do app público é 404); o `/admin` de **qualquer outro endereço**
  do worker — o `workers.dev`, o domínio do app, um domínio ligado depois — leva para lá (302); só os
  endereços de teste (previews e máquina local) seguem com o painel no próprio endereço. Pedido dela:
  *"duas coisas diferentes em dois endereços distintos"*. Regras em `cloudflare/roteamento.js`, teste
  `tests/roteamento_painel.test.mjs`. `avaliacao.mindsummit.com.br` foi desligado do worker por ela
  (26/09, *"não vou usar ele aqui"*): a regra da pesquisa no Worker fica parada, sem efeito. **Aberto
  (dela):** um worker ou dois. Código do app na raiz, do painel em `admin/` (não importa nada de
  fora); separar depois muda só o worker atrás do endereço — Supabase e Google não se refazem. **Falta (dela):** secret `ADMIN_ALLOWED_ORIGINS =
  https://admin.minddash.pro` nas Edge Functions (hoje as quatro do painel recusam a origem nova) e a
  Redirect URL `https://admin.minddash.pro/admin/` no Auth. Previews montam sem as variáveis de build do
  Supabase e abrem em demonstração: o teste de login é em produção.
- **Conteúdo do admin — ela define.** Da Adriana (26/09): *"eu quero um admin da empresa, da
  inteligência da empresa de modo geral"* · *"eu prefiro construir do que você assumir o que eu quero"*.
  O painel atual nasceu como admin do app do Summit; o que entra no admin da empresa sai dela, sem
  proposta pronta.
- **Descoberta lateral:** a `espelho_para_mind` **deste** projeto (fonte `institute_vendas`, feita para
  o projeto Midias) confere `midias_espelho_segredo`, que não existe no Vault daqui — hoje ela recusa
  toda chamada. A migration dela (`20260914212957`) está no ledger sem arquivo no repo.
- **Próximo:** decidir o login com Google (provedor no
  Supabase, app OAuth do Google Workspace e como liberar a equipe por e-mail) · D2 da casa das ofertas.

### ICP e JTBD — catálogos em `intelligence`, perfil por regra e HubSpot — 23/09/2026, EM PRODUÇÃO

Pedidos da Adriana (23/09, manhã): *"crie essas duas tabelas na intelligence"*, *"colocar todas as
pessoas que foram no summit para passar por essa classificação"*, *"usar o que as pessoas escreveram
de empresa e cargo para fazer update em cargo no hubspot, empresa no hubspot (sempre checando… typo
ou duplicação)"*, *"escrever cargo e empresa em pessoas.pessoas"*, *"eu já criei as propriedades
[icp e jtbd no HubSpot]; agora a gente tem que popular"*. Mapa completo e plano: `docs/PERFIL_ICP_JTBD.md`.

- **Catálogos (D2 exercida por ela):** `intelligence.icp` (13 perfis = as 13 opções que ela deixou na
  propriedade `icp` do HubSpot, com `hubspot_valor` = valor interno — 3 valores antigos reaproveitados
  com significado novo — e `rotulo_legado` para traduzir memórias antigas; + `concorrente`, Vittude por
  `regex_empresa`) e `intelligence.jtbd` (13 jobs mind = as 13 opções da propriedade `jtbd` + JT01–JT15
  do estudo, com `produtos`, `icps_tipicos`, `jt_raiz` e `sinais`). `summit_2026.sessions.jtbd`: 62 sessões.
- **Regra:** `intelligence.icp_por_cargo` (determinística), `perfil_evidencias` (check-in 0,70 · reserva
  0,60 · jornada do app · jobs-raiz de conversa traduzidos · patrocínio · produto preferido · contexto por
  família de ICP), `perfil_projetar` grava em `participante_memoria` sem derrubar memória de conversa nem
  ICP manual do HubSpot; `perfil_projetar_lote` por prefixo de uuid; `perfil_gravar_pessoas` leva cargo e
  empresa a `pessoas.pessoas`. Escritor e leitor validam pelos catálogos (rótulos antigos traduzidos).
- **Executado:** 3.855 pessoas classificadas (2.250 ICP `ativa` + 17 `proposta` divergentes da conversa;
  6.970 jobs `ativa` + 4.990 `proposta`; 1.779 cargos e 1.677 empresas como memória);
  `pessoas.pessoas`: 1.815 cargos e 1.667 empresas gravados. Ledger: `20260923081119`, `081602`,
  `081831`, `082020`, `082744`, `083527`. Contrato `tests/perfil_icp_jtbd_contract.sql` → `PERFIL_OK`.
- **HubSpot (manhã):** Edge Function `hubspot-perfil-writeback` (v2, publicada às 08:40 UTC; ensaio por padrão)
  — plano de 2.627 pessoas, 2.587 com contato; `icp` 2.230 (0 conflitos), `jtbd` 1.795, `jobtitle` 1.654
  (712 trocas reais listadas em `substituicoes`; 82 variações da mesma coisa seguradas), `company` 1.278
  (83 trocas; 91 seguradas, ex.: "Beiwrsdorf"). **Executado às 08:42–08:44 UTC em 5 lotes (25 + 700 +
  700 + 700 + 502): 2.318 contatos atualizados, 0 erros; `icp` 2.231 gravados e 9 conflitos (ICP manual
  já existia, não sobrescrito); `jtbd` 1.805; `jobtitle` 1.664 (722 trocas); `company` 1.283 (84 trocas).**
  Relatórios completos (com a lista das trocas, para ela rever) em `public.mind_admin_audit`
  (`resource = 'hubspot_perfil_writeback'`, `record_id` = `ensaio-7560`, `execucao-7561…7565`).
- **Descobertas:** 18 pares de pessoas do banco apontam para o mesmo contato no HubSpot (candidatas a
  fusão); opção `Fundadot / Sócio / Empreendedor` com typo no HubSpot (rótulo corrigível na tela);
  o token do app privado não devolve escopos na introspecção (HTTP 400) — `crm.schemas.contacts.write`
  só se descobre tentando (`acao: "propriedades"` em ensaio).
- **Tarde de 23/09 — segunda rodada, com revisão crítica (docs/PERFIL_ICP_JTBD.md §6).** Ledger:
  `085242` (guarda de última escrita: `mind_hubspot_perfil_registrar`, plano com `p_desde`/`resumo`/
  `ultimo_escrito`, `perfil_resumo`), `090316` (`memoria_regex`: o que a pessoa disse vira evidência),
  `091022` e `093110` (regra revisada: check-in pesa pelo tamanho da sala, reserva 0,50 nunca faz job
  sozinha, veto por ICP típico, rebaixamento, cargo com siglas/abreviações/RH antes de saúde, ICP manual
  só quando não é do Mind), `093258` (resumo, plano sem staff/palestrantes, leitor com fonte/evidência),
  `095020` (conversa não pisa na linha da regra), `095258` (**automático**: `pg_cron` hh:36 reprojeção +
  hh:41 write-back de quem mudou em 2 h; gatilhos `icp_alinhar_hubspot`/`jtbd_alinhar_hubspot`).
  Resultado no banco: jobs ativos **7.068 → 3.844**, pessoas com 6+ jobs **221 → 34**, 2,4 jobs por
  contato. Edge Function **v4** (guarda + JTBD como conjunto + qualidade do valor novo; 41 testes Node).
  HubSpot: propriedades alinhadas pela função (rótulo "Fundadot" corrigido; `mind_resumo_inteligencia`
  criada — o token tem `crm.schemas.contacts.write`); execução em 4 lotes às 09:45–09:48 UTC: **2.288
  contatos, 0 erros, 2.288 registros de última escrita**; `jtbd` 1.368 (1.343 conjuntos corrigidos),
  resumo 2.252, `icp` 72 (BPs que estavam como CHRO), `jobtitle` 1 gravado e **5 preservados** (editados
  no HubSpot entre as rodadas — a guarda funcionou). Contrato `tests/perfil_icp_jtbd_contract.sql` →
  `PERFIL_OK` (26 casos de cargo, pesos, reserva fraca, rebaixamento, idempotência, escritor × regra).
- **Fim da tarde de 23/09 — relacionamento com o Mind (pedido dela: *"limpa ICP e JTBD de staff e
  palestrante do HubSpot e backend… se é professor ou parceiro de venda não é lead e portanto não
  coletamos JTBD e ICP… guardar em pessoas.pessoas uma coluna com o tipo de relacionamento"*).** Ledger
  `20260923143941`: coluna `pessoas.pessoas.relacionamento_mind` (`{lead}` ou staff/palestrante/professor/
  parceiro_venda), derivada de hora em hora das fontes (credenciamento `staff_mind`/`palestrante`, e-mail
  `@joinmind.com.br`, `seguranca.equipe`, `mind_admin_users`, `ecossistema.perfis_publicos`,
  `institute.programa_pessoas`); `parceiro_venda` sem fonte no banco (marca-se à mão). Regra: quem não é
  lead não tem ICP nem JTBD — a regra apaga a própria classificação, a de conversa vira `rejeitada`, o
  escritor ignora, o leitor do Agent não devolve, o HubSpot é limpo. **80 não-leads** (57 palestrantes,
  22 staff, 4 professores); memórias de ICP/JTBD deles zeradas (210 da regra apagadas, 1 de conversa
  rejeitada); Edge Function **v5** executada às 14:47 UTC: 41
  contatos, 86 limpezas (`icp` 39, `icp_confianca` 39, `jtbd` 6, resumo 2), 0 erros; ensaio seguinte 0/0.
  Corrigido junto: o escritor perdia JTBD de conversa quando a regra já tinha o job ativo (`FOUND`
  sobrescrito no `095020`). Contrato → `PERFIL_OK` em produção; 45 testes Node.
- **Noite de 23/09 — decisões da Adriana executadas.** (1) `20260923145909`: os prompts de inteligência
  (análise pós-conversa `analisar-conversa` e Silence) não rodam para não-lead — trava em `analise_pendentes`,
  `analise_montar_contexto` e `silence_claim_pendentes` (contrato `tests/analise_nao_lead_contract.sql` →
  `ANALISE_NAO_LEAD_OK`). (2) 8 fusões por `mind_fusao_decidir`: Adriana (3→1, nome corrigido para Drulla),
  Tamara, Elaine, Ivana (3→1), Juliana, Thiago Araújo; Thiago Barros (thiago@) fica separado (outro CPF).
  (3) `20260923150946`: parceiro de venda por domínio (`intelligence.config.parceiro_venda_dominios` =
  Mais Diversidade → 13) e `contato@joinmind.com.br` fora do staff; HubSpot 13 contatos/22 limpezas/0 erros.
  (4) Apagadas as 3 contas "ZZ TESTE — apagar"; a "Mayra … Hnk" ficou (convidada Heineken com ingresso e
  check-in; voltou a lead). Parceiros marcados à mão: Igor Gomes Menezes (deu workshop com a Mais
  Diversidade) e Esabela Cruz (registro de palestrante).
- **Gates que restam:** reprocessar as 4.921 análises de conversa com prompt novo (custo — dela);
  decisões de produto/semântica listadas em BACKLOG §21 (tradução de evidência por família, valores
  internos novos no HubSpot, empresa como sinal, rótulo de saúde pessoal no CRM); limpar por lista no
  HubSpot o "Outros" de ~120 contatos (a função não apaga valor de lead); espelho diário de contatos do HubSpot travado desde 20/09 no teto de 10 mil da busca (BACKLOG §21.18).

### D6 — o ID universal chama-se `mind_id` — 23/09/2026, APLICADA EM PRODUÇÃO

Pedido da Adriana: *"varra todas as tabelas do banco e, nas colunas onde a gente tem o universal ID,
renomeie a coluna como universal MIND ID"*. Migration `20260923071424` (`d6_mind_id.sql`), provada em
produção em `begin … rollback` (migration + contrato D5 + fumaça de 35 funções e 12 views) e depois
aplicada.

- **53 colunas renomeadas para `mind_id`**: 51 FKs para `pessoas.pessoas` (`pessoa_id` em 20 tabelas,
  `participante_id` em 27, `participant_id` em `intelligence.recovery_inbox`, `person_id` em
  `summit_2026.registrations`) mais `crm.empenho_summit_2026.pessoa_id` e
  `crm.pipeline_leads_inbound.pessoa_id`, que estavam vazias e sem FK e ganharam a FK. Nas 11 tabelas
  da Regra #1 as companheiras viram `mind_id_criterio` e `mind_id_resolvido_em`. Índices e constraints
  com o nome antigo foram renomeados; 63 funções reescritas só nas referências a coluna.
- **O que não mudou, de propósito**: as chaves dos payloads das funções (`pessoa_id`, `participante_id`
  em jsonb e em `returns table`) e os nomes de saída das views (`api.*`, `v_participantes`,
  `v_ingressos`…) — contrato de API lido pelas Edge Functions e pelo app. **Nenhuma Edge Function
  precisou de deploy.** `pessoas.v_pessoa_360` é a única view cuja saída muda (`mind_id`).
- Não são o ID universal e ficaram: `"Check Ins Summit".participante_id`, `"Reservas_Agenda_APP".participante_id`,
  `controle_de_inscritos_e_presenca.participante_id` (id do credenciamento) e `yazo_envio_fila.participant_id`
  (id de `participantes`).
- Descobertas laterais registradas em `BACKLOG.md` §20 (`v_participantes` ainda resolve por junção;
  `api.me` lia schema inexistente; funções presas a `engagement.checkout_clicks`, tabela que saiu).
- **Varredura das 160 tabelas concluída (07:37 UTC)** — `scripts/infra/identidade/60_varredura_mind_id.sql`:
  das 164 tabelas, 110 não tinham FK para pessoa; 5 com informação de cliente entraram na Regra #1
  (`crm.pipeline_leads_inbound`, `crm.status_summit_hs`, `treble.status_hs_contatos`,
  `treble.status_da_conversa`, `engagement.verificacoes_email`) e foram preenchidas **sem criar pessoa**:
  15.406 linhas ligadas por identificador já conhecido, 71 pelo `mind_id` do espelho, 149 marcadas como
  "sem pessoa" (contato fora do espelho ou telefone de teste). `engagement.treble_eventos` (log bruto) e
  `crm.empenho_summit_2026` (pessoa em `propriedades._contatos`, gate) ficaram de fora de propósito; as
  103 restantes não falam de cliente ou herdam a pessoa do pai. Lateral nova: BACKLOG §20.8.
- Testes: `tests/d5_identidade_universal_contract.sql` adaptado a `mind_id` (13 cenários, verde em
  produção dentro da prova); os demais contratos SQL do repo renomeados mecanicamente.

### D5 — identidade universal — 23/09/2026, APLICADA E PASSADA EXECUTADA EM PRODUÇÃO

Regra #1 em `READ_ME_FIRST.md` (regras v2 combinadas com a Adriana na madrugada de 23/09:
**e-mail + nome/sobrenome vencem; depois WhatsApp; depois CPF; depois CNPJ**; nome parecido é o
mesmo nome; nome e e-mail distintos = pessoas diferentes inscritas por terceiro; telefone/CPF
de linha comprada por terceiro ficam de fora; bater sempre com `pessoas.pessoas` antes de criar).

Quatro migrations no ledger de produção, todas provadas antes num Postgres 16 descartável com
`tests/d5_identidade_universal_contract.sql` (13 cenários, inclusive secretária/colega) e com
hash das funções conferido byte a byte: `20260923024555` (a porta em toda fonte),
`20260923033919` (a regra do nome/e-mail), `d5_3_enriquecer_indexado` (fase A por índice) e
`d5_4_proposta_guarda_a_evidencia_mais_forte`. A passada foi executada pelo Claude, a pedido
dela ("nada deve ficar comigo, execute"), entre 03:55 e 04:47 UTC:

- **incidente desfeito**: a primeira migration (02:47) deixou o telefone vencer o e-mail; o sync
  das 02:50 colou 13.205 identificadores a pessoas erradas (colegas inscritos pelo comprador).
  Triggers desligados às 03:12, tudo apagado e refeito com a regra nova
  (`scripts/infra/identidade/20_desfazer_janela_2309.sql`);
- **fase A**: 9.451 pessoas enriquecidas, 0 criadas;
- **fase C** na ordem dela: HubSpot 13.321/13.321 com pessoa (6.784 criadas, 705 ligadas) ·
  Eduzz vendas 4.572/4.739 (167 ficaram sem pessoa de propósito: e-mail já é de outra pessoa
  com nome diferente) · Blinket 4.764/4.765 · Treble 4 ligadas (38 conversas não têm
  identificador nenhum) · credenciamento 2.577/2.577 · Yazo 2.910/2.910 · Relatório Yazzo
  2.367/2.415 · pedidos 10/11. `pessoas.pessoas`: 9.451 → ~16.800.
- **fase B — só a Adriana decide**: fila em `engagement.identidade_fusoes` por `padrao`
  (`mesmo_id_de_terceiro` e `mesmo_email*` alta; `mesmo_telefone_emails_diferentes` média;
  `nomes_divergentes`/`mesmo_email_nomes_diferentes` baixa, nunca em bloco). Nada foi fundido.

O sync da Eduzz/credenciamento apaga e regrava as quatro tabelas espelhadas a cada 30 min
(:20 e :50): o trigger D5 refaz `pessoa_id` a cada sync — funciona, mas custa ~80 s e disputa
locks com qualquer passada rodando ao mesmo tempo (deadlock em 04:20). Melhoria registrada:
`eduzz_espelho_gravar` passar a upsert. Branch `claude/trusting-einstein-pydyqb`, PR #110.

### Avaliação do evento — NO AR desde 18/09/2026

A segunda pesquisa: o Summit inteiro, respondido depois que ele acaba. As mesmas
oito perguntas da Avaliação do dia com "hoje" trocado por "o evento", e SEM nota
por atividade — as duas pesquisas do dia já colheram 273 notas com a memória fresca.

**LIGADA. Migration aplicada, Edge publicada na versão 2 (runtime `1.2.0`) e app
na `main` em `67ab260`. Janela aberta: 18/09 a 02/10, no fuso do evento.**

**Dois canais, desde 18/09.** No app a Yazo manda nome e e-mail na URL e a pessoa
não digita nada. Fora do app, `#avaliacao` abre a pesquisa direto e o formulário
pergunta quem está respondendo. Quem decide qual dos dois é a camada de
identidade, e NÃO a barra de endereço — a URL é limpa na partida, de propósito.

É identidade autodeclarada no segundo canal: quem digita o e-mail de outra pessoa
responde no lugar dela. Já valia para a URL, que qualquer um escreve à mão; o
campo torna fácil. Decisão de produto de 18/09.

O que NÃO está ligado: o convite por link. A migration dele está no repo e não
foi aplicada — é gate da Adriana.

Conferido no ar: `/health` responde `1.2.0`; `/estado`, `/evento/estado` e
`/admin/evento/relatorio` pedem sessão; `/convite/estado` responde
`convite_invalido` em vez de `sem_sessao`, provando que ele roda antes da
exigência de sessão; o app abre sem erro de console e a home continua a mesma.

| commit | o que é | estado |
|---|---|---|
| `14f6e15` | migration `20260918120000_avaliacao_do_evento.sql` | escrita, provada, **não aplicada** |
| `46b318f` | rotas `/evento/*` na Edge `mindagent-avaliacao` | escritas, **não publicadas** |
| `7862dd9` | tela `avaliacao/evento.js` e card no momento `depois` | na `dev` |
| `529b91d` | página do painel `/avaliacao-do-evento` | na `dev` |
| `92a7599` | migration do convite `20260918140000` | **GATE ADRIANA**, não aplicada |
| `cfa002e` | rotas `/convite/*` e emissão de convites | escritas, não publicadas |
| `24bcd2c` | entrada do app pelo link (`#c=…`) | na `dev` |

**Para ligar a pesquisa pelo app, nesta ordem:**

1. aplicar `20260918120000_avaliacao_do_evento.sql`;
2. publicar `mindagent-avaliacao` — a viva é a `1.0.0`, o repo está na `1.2.0` —
   comparando com a versão anterior antes de trocar, como manda o boundary de
   deploy deste repo;
3. definir a janela em `concierge.config`, chave `avaliacao_do_evento`:
   `{"ativo": true, "abre": "AAAA-MM-DD", "fecha": "AAAA-MM-DD"}` — **as datas ainda
   não foram decididas**;
4. mergear `dev` em `main` para o app subir.

Os passos 1 e 2 não quebram nada se forem feitos antes do 3: a pesquisa nasce
desligada, e o card só aparece quando o servidor confirma que ela está aberta.

**O que está atrás de gate da Adriana, e por quê:** o convite por link faz um token
valer como identidade sem login. Isso é auth. O disparo por WhatsApp ou e-mail é
gate separado. A migration do convite não pode ser aplicada junto com a primeira
sem essa decisão. Falta também decidir limite de tentativa nas rotas `/convite/*`,
que são as únicas da função que respondem sem sessão.

**Decisões congeladas desta lane:**

- tabela própria, e não a do dia: lá o `dia` é parte da chave, e o relatório, o
  painel e o PDF agrupam por ele. Uma resposta sobre o evento inteiro não tem dia;
- `engagement.evento_feedback`, `engagement.feedbacks` e `engagement.nps` não
  servem — a primeira é ledger de reclamação escrito pelo agente, a segunda é
  chave/valor sem contrato, a terceira é NPS, que não se mistura com isto;
- sem nota por atividade, de propósito;
- a janela é dado em `concierge.config`, lida no fuso do evento e conferida no
  envio, não só na abertura da tela;
- o token do convite nunca é gravado: o banco guarda só o SHA-256, e quem calcula
  é a Edge — se a troca fosse no banco, o token cru apareceria no log de consulta;
- token desconhecido e token revogado devolvem o mesmo motivo, para a função não
  virar oráculo de adivinhação;
- as duas portas (app e convite) validam pelo mesmo corpo e disputam a mesma trava.

**Defeito encontrado e corrigido de passagem:** a Edge recusava nota `4.5` e `"5"`
na porta e deixava `-1` e `6` atravessarem até o banco. Valia para as duas
pesquisas. O banco sempre recusou, mas validação que pega metade parece garantia e
não é.

**Ressalva de leitura da pesquisa do dia, que vale para qualquer número dela:**
cinco pessoas responderam entre 00h15 e 07h47 do dia 17 falando do dia 1, e o
formulário gravou como dia 2 — com 47 notas para sessões que ainda não tinham
começado. No total dos dois dias não muda nada (4,44 de relevância e 4,33 de
programação sobre 39 respostas de participantes); no dia 2 sozinho muda de 4,33
para 4,60. A pesquisa vira o dia à meia-noite e o app só trocou a tela pela manhã.
A correção seria virar num horário de corte, e **não foi feita** — o evento acabou
e não há nada vivo para consertar.


### Hotfix mais recente — Vendedor Treble / PR #98

- PR #98 mergeada em `main`: `2581f6632339b4606f887d340b6c00821de9a3c5`;
- `treble-inbound-agent` viva na Supabase v41, runtime `1.10.2`,
  `ACTIVE`, `verify_jwt=false`;
- `router_universal` ativo na v4;
- B2C é o padrão comercial;
- para ingressos, B2B exige **destino empresa/equipe + mais de uma pessoa**;
- cargo, empresa, pagamento corporativo de um único ingresso e quantidade sem
  destino corporativo não bastam;
- empresa sem quantidade volta ao Router para esclarecer; patrocínio continua
  B2B como demanda própria;
- cadastro pode enriquecer o CRM, mas nunca bloqueia resposta, preço,
  recomendação, calculadora, proposta ou checkout;
- 185/185 testes Edge, 17/17 casos do classificador e health vivo em `1.10.2`;
- E2E externo de entrega no aparelho continua pendente porque esta execução não
  tem um WhatsApp controlado configurado.

### Hotfix operacional mais recente — PR #91

- commit de produto da PR #91: `3ad409969135effc70ead9374fcebd764869f9fc`;
- Home tolera aviso `no-ar` sem `disparo_em` e o exibe como `Agora`;
- Concierge força `buscar_intelligence` quando tenta abster sem investigar;
- E2E real: resposta direta com zero tools; recuperação com uma tool e
  `recuperacao_forcada=true`;
- `mindagent-chat` viva na versão 37, `ACTIVE`, `verify_jwt=true`;
- playbook `playbook_concierge_summit` ativo na versão 6;
- 156/156 testes e build Cloudflare/Admin verdes;
- embeddings continuam pendentes: 30 chunks, zero vetores. A busca lexical está
  funcional; o indexador requer invocação administrativa em ambiente confiável.

### Captura comercial e Contact HubSpot — decisão de 03/09, parcialmente superada

> A PR #98 substituiu a parte que transformava cadastro em pedágio de venda.
> O fluxo ainda aproveita dados conhecidos e espontâneos, mas não pede campo
> apenas para enriquecer CRM e não retém venda por campo ausente.

- consultar primeiro `pessoas.pessoas`, CRM e credenciamento e nunca reperguntar dado conhecido;
- persistir cada resposta imediatamente na pessoa canônica;
- o `hubspot-commercial-writeback` passa a localizar o Contact por vínculo/e-mail/telefone, criar quando não existir ou enriquecer apenas campos vazios;
- divergência de identidade ou perfil bloqueia o write-back, sem merge ou sobrescrita automática;
- depois do Contact, vincular o `hubspot_id` por `engagement.identidades` e só então criar/atualizar o Lead;
- `apply` e qualquer cron/outbound continuam desligados até publicação e teste controlado.
> Commit de produto verificado nesta entrega: **`6f9c899bc994e7f8a9d8f2fe312f8368c636943f`** (merge da #70; atualizações documentais posteriores).
>
> Este é o ponto de retomada operacional. `PROJECT_STATE.md` preserva arquitetura/decisões congeladas; `GO_LIVE_PARALLEL_20260830.md` preserva ownership; `BACKLOG.md` preserva investigações deferidas; `docs/CORE_UNIVERSAL.md` descreve o sistema vivo, mas ainda contém snapshot de 29/08 em alguns trechos. **PRs e issues são mais frescos que este arquivo para trabalho ainda não integrado.**

> **Mudança pendente em 03/09/2026:** a branch `codex/unify-agent-runtime` unifica
> App/WhatsApp e B2B/B2C sobre o mesmo `kit.playbook`, decisioning comercial e runtime
> de Intelligence. Acrescenta contexto compacto, busca híbrida sob demanda, indexador de
> embeddings, `gpt-5.4` e RLS defensivo. A migração passou completa em produção dentro de
> `BEGIN/ROLLBACK`, sem alteração persistida; instruções medidas: B2B 19.122 caracteres e
> B2C 22.606. Ver `CORE_AGENTICO_UNIFICADO.md`, na raiz. **Não está em produção.**

---

## 0. Prompt exato para uma nova janela

Cole isto na nova janela:

```text
Estamos continuando o projeto Agentes do Mind no repositório GitHub `Mind-Institute/mind-agent`.

Antes de responder ou propor qualquer mudança, reconstrua o checkpoint pelo sistema real.

LEIA, nesta ordem:
1. `CHECKPOINT_ATUAL.md` na raiz — é o ponto exato de retomada.
2. `PROJECT_STATE.md` — arquitetura, runtime, gates e decisões congeladas.
3. `GO_LIVE_PARALLEL_20260830.md` — ownership das lanes e ordem de integração.
4. `BACKLOG.md` apenas nas seções relacionadas às lanes ativas.
5. `docs/CORE_UNIVERSAL.md` para o que já está vivo; atenção: alguns trechos ainda refletem o snapshot de 29/08, então sistema real/PRs mais recentes vencem.

Depois, ANTES de agir:
- confira no GitHub o estado atual, HEAD, diff, comments/reviews e CI das PRs #47, #50, #46, #51 e #48;
- leia os comentários mais recentes das issues #40, #41, #42 e #43;
- confira `main` atual e produção Supabase antes de qualquer merge/deploy;
- se algum HEAD tiver avançado depois do checkpoint, atualize mentalmente o estado usando PR/issue como fonte mais fresca;
- não reinvestigue decisões fechadas sem fato novo material.

Você assume o papel de arquiteto/supervisor desta janela. Claude Code continua executor por lane. GitHub é memória/barramento: coordene diretamente nas issues/PRs; não use Adriana como mensageira entre janelas.

Ritual obrigatório:
INVESTIGAR → ENTENDER O QUE JÁ EXISTE → DECIDIR A MENOR MUDANÇA → IMPLEMENTAR → TESTAR SÓ O AFETADO → DOCUMENTAR → CONTINUAR ATÉ E2E OU GATE REAL.

Regras importantes:
- lane é dona da capacidade até E2E real, não até o primeiro PR;
- ordem de deploy ≠ ordem de trabalho;
- merge em `main` é boundary de deploy para migrations/app;
- as Edge Functions `treble-inbound-agent` e `mindagent-chat` NÃO são publicadas automaticamente hoje porque o repo não tem `supabase/config.toml`; publicação é manual;
- não criar segunda identidade, segundo backend ou segundo lifecycle para Play;
- não criar `mind_lead_capturar`;
- não ligar cron 13/outbound sem gate explícito;
- não mudar preço/regra comercial/source of truth/auth/RLS/security/identidade ou comportamento material sem o gate correspondente;
- não insistir em preview pago/recriado quando já existe prova transacional suficiente e a supervisão fechou que isso não bloqueia.

PONTO DE RETOMADA:
A Lane A/Core está concluída e em produção. As lanes ativas são B/C/D/E. Leia o estado detalhado neste `CHECKPOINT_ATUAL.md` e compare com os HEADs vivos.

Não faça recap genérico. Primeiro me diga em poucas linhas:
1. qual é o `main` atual;
2. qual é o HEAD vivo de B/C/D/E;
3. qual é o PRIMEIRO próximo movimento seguro na ordem de integração;
4. se existe algum gate meu neste exato momento.

Depois continue automaticamente tudo que não depender de gate meu.
```

---

## 1. Objetivo agora

Fechar dois produtos sobre o mesmo Core:

1. **Vendedor Summit** no Treble/WhatsApp, B2C e B2B, com Router → Gate → Kit → Decisioning/Agent → resposta/handoff e zero invenção comercial.
2. **Concierge Summit + Play** no app, com programação/palestrantes/recomendação factual, actions person-bound (NPS/feedback/insight) e o mesmo runtime/identidade.

Depois fechar memória/pós-turno/write-back/continuidade dentro dos gates e rodar E2E transversal.

---

## 2. O que já está fechado em `main` e produção

### Lane A / Core — CONCLUÍDA

Já integrados/verificados:

- speakers canônicos: **81/81 vínculos**, 63 pessoas, 60 sessões;
- Kit Loader universal mínimo (#36): `mind_kit_meta` + `mind_agent_kit`;
- Capability Gate lendo Kit real (#44);
- `mind_kit_evento` corrigido pela correspondência real `evento.produto_codigo = catalogo.produtos.codigo` (#49);
- #49 mergeada no commit `a226e2888d029b1fd661795b16c18a9dc02a6dac` e já refletida no Supabase;
- último ledger de produção observado depois de #49: **285 migrations**;
- B2C/B2B em WhatsApp: Gate/Kit disponíveis com blocos obrigatórios.

Não reabrir Lane A sem fato novo.

---

## 3. Lanes ativas — estado mais recente conhecido

### B — Vendedor Summit / Treble

- **Issue:** #40
- **PR:** #47, draft
- **Branch:** `claude/go-live-vendedor-runtime-hjobov`
- **HEAD mais recente verificado:** **`ff223c0df3323734a4ecb47fd9ce5e5c64816a87`**

O runtime/guardrail está **encerrado na revisão estática**:

- `treble-inbound-agent` v1.4.0 preparado para Router → Gate → Kit;
- Gate roda para qualquer rota canônica decidida; Kit comercial só para B2C/B2B;
- clarify preserva `candidatas` e não grava audience nova;
- `mind_lead_capturar` removida como chamada morta, sem writer substituto;
- guardrail comercial valida **papel + faixa + experiência**, percentual, centavos e contexto local por valor;
- fixture espelha Kit vivo por asserção: 3 experiências, 3 ofertas vigentes, 12 linhas de volume;
- **71/71** contratos + `tsc --strict` limpo;
- #49 sincronizada e revalidada;
- smoke não usa mais telefone fake hardcoded: exige `TREBLE_SMOKE_CELLPHONE`, falha antes de tocar produção se faltar/inválido e não apaga pessoa/identidade/CRM;
- `node --check` smoke ✅; sem env → exit 2, zero request;
- `core_rota_kit` continua desligado;
- Edge não publicada.

**Próximo movimento B:** revisar o HEAD vivo/CI `ff223c0`, marcar Ready/merge quando seguro, confirmar migration, comparar código versionado com Edge viva, **parar no gate de publicação manual se exigido**, publicar `treble-inbound-agent`, ligar flag e rodar smoke E2E real no WhatsApp controlado.

DoD: HTTP 200 não basta; resposta tem de chegar no aparelho. Se houver turno devolvido pela Edge que não chega no WhatsApp, flag volta a `false`.

---

### C — Concierge Summit / runtime canônico

- **Issue:** #41
- **PR:** #50, draft
- **Branch:** `claude/go-live-concierge`
- **HEAD mais recente verificado:** **`b0e51356991f8d7d02d4e761f264ae43bfc5a9e8`**

SQL/retrieval/Kit aceitos neste estágio:

- `mindagent_chat_search` corrigido para nomes parciais, tema, dia/faixa, múltiplos dias, minuto real, nested speaker sessions, horário local e ausência de fonte;
- `mind_kit_programacao` separa `pergunta` (seleciona) de `interesses` (só rerankeia);
- `event_slug` preservado e resolvido explicitamente;
- playbook v7 copiado byte a byte para `agentes.prompts['playbook_concierge_summit']`; `concierge.prompts` fica intacta/histórica por decisão fechada;
- Kit `concierge_summit` = `evento` + `programacao`;
- **17 contratos SQL** em `BEGIN/ROLLBACK` contra produção, produção intacta.

Runtime real já versionado na PR:

- baseline Edge viva `mindagent-chat` v23 versionada em commit isolado `0deca7f` antes das alterações;
- hash vivo conferido: `26a607f19992ee559bf3072a54f8fd741f7447a33432ac44a68115875dd1b0fd`;
- código atual: auth/sessão/bind/contexto → salva mensagem do usuário → modo action Play OU Gate → Kit → OpenAI;
- sem Router no app dedicado;
- fail-closed sem Kit/playbook/blocos;
- `sensitivity` obrigatório em cada `interest`, enum `none` + 10 chaves existentes, repassado intacto à RPC;
- modo Play no **mesmo** `mindagent-chat`, allowlist explícita, sem OpenAI;
- pessoa identificada pode entrar direto no Play sem conversa anterior; sem `pessoa_id`, coleta não executa;
- `npm run test:edge`: **19/19**; `tsc --noEmit` limpo;
- Edge **não publicada**.

Compatibilidade C→D fechada: é correto C começar a enviar `sensitivity` **antes** do gate SQL da D; RPC atual recebe JSON extra e ignora até #51 entrar.

**Próximo movimento C:** revisão final do diff do runtime no HEAD vivo → merge controlado das migrations/código → confirmar DB vivo → **gate/publicação manual da `mindagent-chat`** → E2E real no app. Não insistir em branch Supabase paga/recriada para #50.

#### 01/09 — O FLUXO CANÔNICO DO APP MUDOU

Branch `claude/go-live-vendedor-runtime-hjobov`. **Migrations aplicadas em produção e `mindagent-chat` publicada como version 25 (v1.6.0).** O que estava escrito acima — *"sem Router no app dedicado"*, *"Kit `concierge_summit` = `evento` + `programacao`"* — deixou de valer.

Fluxo do App agora:

```text
mensagem
  → identidade/contexto
  → ORIGEM AUTORITATIVA (se a porta já define a competência) ─┐
  → POLÍTICA DO CANAL (agentes.canal_competencia)             │
  → ROUTER (só quando há o que decidir)                       │
  → GATE  ←───────────────────────────────────────────────────┘
  → KIT DA ROTA
  → AGENT (com tool loop)
```

**`mind_summit_app` é uma entrada com rota autoritativa.** Quem chega pelo app oficial do
Summit já disse, pela porta, qual competência quer: `mind_summit_app → concierge_summit`,
sem chamar o Router. É a única entrada assim hoje, e ela mora em `ROTA_POR_ORIGEM`, na Edge
— um mapa de uma linha, não uma taxonomia nova. A origem vem do frontend em
`origem_codigo`, é persistida **uma vez** em `engagement.conversas.origem_codigo` (o banco
grava com `where origem_codigo is null`) e é a persistida que decide: um turno posterior
não reescreve a porta de entrada. Toda outra origem continua passando pelo Router, e o
**Gate continua obrigatório** nos dois caminhos — a origem diz qual competência foi
acionada, nunca se ela executa. Medível em `rota_origem` (`origem_autoritativa` vs
`router`) e em `blocos.origem_codigo`.

Quatro mudanças:

1. **O nome da URL chega à identidade.** `mindagent_chat_bind_identity` ganhou `p_nome` e repassa ao `mind_identidade_resolver`, que já sabia preencher nome faltante sem sobrescrever nome canônico. Antes o e-mail ligava a pessoa e `pessoas.pessoas` ficava sem nome.
2. **O App deixou de forçar `concierge_summit`.** A rota vem do Router, com o canal declarado; o universo legal é `concierge_summit` + `cliente_suporte`, e essa lista **não está escrita na Edge** — vem de `agentes.canal_competencia`. Quando o Router não decide, o desempate é a primeira candidata que ele mesmo devolveu; quando o Router não responde, o piso é `concierge_summit` — e os dois casos saem em `rota_origem`, medíveis.
3. **`cliente_suporte` executa no App.** O Gate devolvia `missing_kit` porque a rota tinha zero linhas em `agentes.kit_blocos` (o playbook sempre existiu). Agora tem `evento` + `programacao` + `inclusoes`, os mesmos providers já vivos. Vale para os dois canais.
4. **O Concierge ficou agentic.** `mind_agent_kit` parou de devolver `tools: []` fixo: a rota declara em `kit_blocos` (`secao='tools'`) e o descritor vem de `concierge.ferramentas`, filtrado por `escrita = false`. Duas tools, ambas já existentes desde 20260831070000: `buscar_intelligence` e `ler_intelligence`. Tool loop na Responses API, no máximo 2 rodadas por turno, múltiplas chamadas por rodada.

Estado vivo: `mindagent-chat` **version 25**, `router` version 5 (inalterado), `treble-inbound-agent` version 30 (inalterado).

**E2E no runtime real, 8/8** (via `pg_net`, sessão anônima igual à de qualquer visitante):

| teste | resultado |
|---|---|
| identidade (email + nome da URL) | nome persistido, 1 pessoa, sem duplicata |
| memória (persistir → recuperar em turno seguinte) | recuperou sem repetir os temas |
| Router App → concierge | `concierge_summit` |
| Router App → atendimento | `cliente_suporte`, **executando**, não `missing_kit` |
| agentic factual (Maslach) | grounded no `structured`, sem tool desnecessária |
| agentic por significado | `buscar_intelligence` → `ler_intelligence` → resposta, num turno |
| sem necessidade de tool | respondeu do `structured` |
| sem fonte | disse que não encontrou, não inventou |

**Ponto fraco conhecido, não bloqueante:** em 8 turnos a tool disparou 1 vez. Em `"O que combina comigo?"` o Kit voltou com 0 sessions e 0 speakers, as 2 tools estavam expostas e o modelo **não** buscou — respondeu que não conseguia apontar sessões. É afinação de prompt, não arquitetura: o caminho existe e foi provado no teste por significado.

**Divergência pré-existente registrada, não corrigida:** `mind_identidade_resolver` usa `split_part(nome, ' ', 1)` para `primeiro_nome` e não preenche `sobrenome` — "Adriana Teste E2E" virou `primeiro_nome='Adriana'`, `sobrenome=null`. É comportamento anterior a esta entrega e fora do escopo dado ("deixar o resolvedor atual cuidar do preenchimento").


---

#### 02/09 — Concierge utilizável: retrieval, Executor e conduta

Estado vivo: `mindagent-chat` **version 28 (v1.8.0)**, `router` version 5 (inalterado),
`treble-inbound-agent` version 30 (inalterado). Dez migrations aplicadas hoje, **todas com
arquivo no repo e todas idempotentes** — as guardas de todas as dez foram re-executadas
contra a produção atual e passaram, com o hash dos prompts inalterado.

**1. O retrieval parou de se comportar como AND.** `mindagent_chat_search` escalava o piso
de cobertura com o número de termos da pergunta (`0.1 * least(2, greatest(1, n_foco))`).
Como `ts_rank_cd` devolve exatamente `0.1` para um lexema único de peso D, dois termos
exigiam os dois — um AND acidental. O piso virou constante, os filtros estruturais passaram
a sair de `summit_2026.sessions.tipo` (não de lista manual), e existe fallback: tipo pedido
nunca devolve zero. Medido: `workshop RH` 0 → 12; `workshops sobre liderança` 12, nenhum
de outro tipo; `dia 17` 6; `masterclasses` 4; Amy/Maslach preservados; sem fonte, 0.
Lacuna conhecida e registrada, não disfarçada: `painel/painéis` (o stemmer devolve `pain`).

**2. O Executor deixou de ser um segundo playbook.** `contratoDoExecutor` (7.060 chars de
prosa dentro da Edge) dizia como recomendar, como escrever e o que fazer no suporte — isso
é competência, e competia com o playbook da rota. Foi removido; `instrucoes` agora é
`kit.playbook` e nada mais. Cada regra foi para a casa dela: transversal → `agentes.prompts['base']`;
conduta do concierge → `playbook_concierge_summit`; semântica de campo → `description` do
JSON Schema; horário → removido, porque a `nota` do bloco de programação já dizia. O que o
runtime garante continua garantido **em código**: allowlist de tool, validação de argumento,
teto de rodadas por `tool_choice`, timeout, schema estrito, Gate, Kit, persistência,
redaction e telemetria.

**3. Follow-up funciona.** `history` existia, vinha filtrado pelo vocabulário errado
(`user`/`assistant` em vez de `lead`/`agente`), chegava vazio e ainda era descartado pela
Edge. Corrigido nas duas pontas.

**4. O tool loop disparou em produção.** `presenteísmo` → `rodadas_tool: 2`,
`chamadas_tool: 2`, 6,7 s: buscou, leu e respondeu honestamente que não há sessão com esse
nome, oferecendo três adjacentes reais. O ponto fraco registrado em 01/09 está resolvido.

**5. Seis defeitos de conduta medidos e corrigidos por prompt, não por código** — cada um
na casa que a arquitetura define. Lista parcial anunciada como completa; total do recorte
atribuído ao evento inteiro (`sessions_total` vs `totais.sessoes`); total citado em
recomendação, onde ninguém pediu; justificativa formatada como sessão irmã; encaminhamento
oferecido para o que a própria pessoa faz no app; e o sistema vazando na fala ("o contexto
não trouxe", "com o que veio neste turno").

**Residual conhecido, não bloqueante:** em pergunta de seguimento com pronome ambíguo
("Por quê essa?" depois de três recomendações) o agente responde certo — usa a conversa e
dá o motivo — mas ainda abre com uma ressalva desnecessária em vez de perguntar de qual
sessão se trata. É afinação de redação, não caminho quebrado.


---

#### 02/09 — a programação do backend estava 3 dias atrasada

Descoberto ao ser perguntado se eu tinha trocado a programação. **Não tinha**: nas dez
migrations de hoje só há `update agentes.prompts`, nenhuma escrita em `sessions`,
`session_speakers`, `espacos` ou `knowledge_documents`. Mas a pergunta expôs coisa pior.

**A cadeia de sync existia e nunca funcionou.** `mindsummit2026` tem
`.github/workflows/sync-programacao.yml` (push em `src/data/programacao.json` → Edge
Function `summit-programacao-sync` → RPC `summit_sync_programacao`). Rodou 3 vezes desde
30/08, **as 3 vermelhas**, sempre `401 x-sync-secret invalido ou ausente`: o log mostra
`-H "x-sync-secret: "` — o secret `SYNC_SECRET` **não existe naquele repositório**. O
único sync bem-sucedido (30/08 19:33) foi manual.

Resultado: o commit de ontem 15:18 (`troca dos workshops "Bem-estar começa na agenda" e
"Falhar melhor"`) nunca chegou ao backend, e o Concierge respondia dia, horário e sala
errados para 3 workshops — com a confiança que o trabalho de hoje aumentou, porque agora
ele lista dias inteiros e afirma totais. Dado velho entregue de forma mais completa é pior,
não melhor.

**Corrigido no runtime, com a normalização canônica.** Um diff caseiro meu deu um falso
positivo (`d2-1720` tem `superTitulo: "Mind Talks"`, e a função normaliza o título para
"Mind Talks" de propósito) — por isso a correção foi feita chamando a própria Edge
Function, não reimplementando a regra. As 3 sessões que mudaram de horário mudaram de
`id`, e a função nunca apaga; então: sync criou as 3 novas → migrei os 2 vínculos de
palestrante → apaguei as 3 antigas, depois de provar que nenhuma tinha agenda pessoal,
feedback, jornada ou recomendação ligada (as 5 FKs são `CASCADE`). Backend voltou a 77
sessões, 39/38, idêntico ao site. Medido no runtime: `Falhar melhor` → 16/09 15:00–17:00,
Sala Workshop 2.

`summit-programacao-sync` foi para **version 6**: `VALIDO_ATE` de `2026-09-07` para
`2026-09-16`, a pedido da Adriana (a programação muda até a véspera e o Concierge lê esta
tabela).

**PR aberto no repo do site:** Mind-Institute/mindsummit2026#31 — `schedule` de 07:00 e
19:00 BRT no workflow, parando sozinho depois de 16/09.

**Pendências que são gate da Adriana, não minhas:**
- criar `SYNC_SECRET` em `mindsummit2026`. Sem isso o job continua 401, agendado ou não;
- **o segredo do sync está hardcoded em texto claro** dentro da Edge Function, como
  fallback. É por isso que esta função **não tem arquivo neste repo**: guardá-la aqui
  espalharia o segredo por um segundo lugar. A divergência repo/produção fica registrada
  de propósito e se resolve junto com a rotação do segredo para env var;
- toda troca de horário vira `id` novo e exige limpeza manual da linha velha — hoje fiz as
  3 à mão. Se isso virar rotina até o evento, vale decidir uma regra;
- `who` do JSON não vira vínculo de palestrante (o sync não escreve palestrante, por
  contrato): `Bem-estar começa na agenda` está sem palestrante no backend, embora o site
  traga "Esabela Cruz, Clarissa Daroit".


**Segunda rodada, 04:17 — o padrão se confirmou.** No check-in seguinte o site já tinha
mais dois commits (`Arena Top Voice` virou `Arena LinkedIn`; credenciamento passou a abrir
às 07:30) e alguém já os tinha aplicado no banco à mão, fora do sync — `sincronizado_em`
nulo, sem log. O conteúdo estava certo, mas **o credenciamento continuava com o `id`
antigo** (`d1-0800-credenciamento` com hora 07:30), enquanto o site já usava
`d1-0730-credenciamento`. Sem corrigir, o próximo sync inseriria os dois novos e deixaria
quatro credenciamentos.

Aqui o `id` era a única diferença, então a menor mudança correta foi **renomear**
`site_session_id`, não inserir-e-apagar: renomear preserva o UUID, os vínculos e todas as
FKs.

Depois disso rodei o sync com o JSON **completo** — a prova que faltava:
`200 · ok:true · recebidas 77 · inseridas 0 · atualizadas 77 · sumiram 0 · sem_id 0`.
Backend idêntico ao site, e o workflow ficará verde assim que o secret existir. Confirmado
no runtime: "credenciamento abre às 07:30 nos dois dias".

**O padrão, agora com duas ocorrências:** mudança de horário no site vira `id` novo, a
função nunca apaga, e alguém precisa limpar a linha velha à mão. Enquanto a programação
mudar até a véspera, isso vai se repetir. Vale decidir uma regra — a mais simples é o
sync aceitar remover o que sumiu do JSON quando a sessão não tiver nenhum dado de
participante ligado (as 5 FKs são CASCADE), mantendo a recusa quando tiver.

#### 02/09 — PASSOS 5 E 6: PROMPTS FINAIS, MEMÓRIA EM DOIS TEMPOS E HANDOFF EXECUTÁVEL

Branch `claude/go-live-vendedor-runtime-hjobov`, commit `4bae649`. **Migrations aplicadas em
produção e `mindagent-chat` publicada como version 29 (v1.9.0).** Especificações-fonte:
`SUMMIT_2026_STEP5_PROMPTS_SPEC.md`, `SUMMIT_2026_STEP5_MEMORY_ADDENDUM.md` (que prevalece
sobre a spec nos trechos de memória) e `SUMMIT_2026_STEP6_HANDOFF_SPEC.md`.

**Prompts (`agentes.prompts`).** Quatro reescritos e conferidos por `md5` repo↔produção:
`base` `39bb6406`, `playbook_concierge_summit` `a11ff293`, `playbook_cliente_suporte`
`3b6d80e0`, `analise_concierge` `01a77062`. Atenção para quem for conferir: **a coluna
`atualizado_em` de `agentes.prompts` não é mantida na escrita** — ela ainda mostra datas de
agosto para linhas reescritas hoje. Só o hash do conteúdo vale como prova de frescor.

**Memória rápida** (`engagement.session_interests`, escopo de sessão). Caíram os cortes
artificiais: `interests.maxItems = 2`, `.slice(0,2)`, `.slice(0,8)` do perfil, `.slice(0,3)`
do Kit, o teto de 12 por sessão e a rejeição de payload com mais de 5 itens. Caiu também o
campo `confirmed`. Entrou o gate de sensibilidade que o runtime **afirmava em comentário mas
não existia no banco**: `mindagent_chat_save_interests` agora lê `sensitivity` e só persiste
`none`; um item sensível é descartado sozinho, sem derrubar o resto do payload. A promoção
de interesse de sessão para memória durável saiu daqui — memória rápida é sessão, não
memória permanente.

**Memória durável** (`intelligence.participante_memoria`). Em `analise_projetar_memoria`,
**apenas no ramo `p_analisador = 'analise_concierge'`**: `sensitivity` ausente ou diferente
de `none` não persiste; `scope='temporary'` não vira durável; `high` + (`stable`|`opportunity`)
→ `ativa`. A semântica dos outros analisadores fica intacta — `analise_vendas_summit` continua
com `stable + high → ativa` e continuou escrevendo normalmente durante todo o dia.

**Read path.** `mindagent_chat_get_context` passou a devolver `memories` (só `status='ativa'`
e não expirada, aceitando as duas formas históricas `valor.text` e `valor.label`) e
`rota_ativa`. Antes desta mudança a memória durável era escrita e **nunca lida** — o
Concierge não reutilizava nada do que o analisador gravava.

**Passo 6 — handoff Concierge ↔ Atendimento.** Sem tabela nova, sem coluna nova, sem segunda
conversa, sem Router no App. A competência corrente mora em
`engagement.conversas.variables.rota_ativa`; `origem_codigo` continua imutável como porta de
entrada. Precedência do turno: **`rota_ativa` persistida > origem autoritativa > Router**, e o
Gate continua obrigatório depois de qualquer uma das três. O contrato Agent→runtime é o campo
`next_route` do schema de saída, cujo enum é montado em runtime a partir de
`mind_canal_rotas('mindagent-web')` — não existe segunda lista hardcoded de rotas. A escrita
acontece dentro de `mindagent_chat_save_message`, na **mesma transação** da gravação da
mensagem, depois de revalidar a rota por `mind_rota_capacidade` com o canal lido da conversa.
Isso fecha o estado impossível "a resposta disse que encaminhou, mas a rota não mudou".

**E2E real do App, produção, v1.9.0.** Cadeia completa da DoD do Passo 6 numa única pessoa,
sessão e conversa (`2f71c556`): turno 1 `origem_autoritativa`→`concierge_summit` com
`next_route=cliente_suporte` e `variables.rota_ativa` persistida; turno 2 `rota_ativa`→
`cliente_suporte` sem Router; turno 3 Atendimento devolve com `next_route=concierge_summit`;
turno 4 volta ao Concierge. Nenhuma pessoa, conversa ou sessão nova foi criada na troca.

Comportamento conferido no runtime real: "cardápio do almoço" sem dado → diz que não
encontrou e **não** troca para Atendimento; "como faço para reservar?" → orienta e não
executa; "quais sessões eu já reservei?" → não finge ler a agenda; VIP → Masterclass → Prime,
sujeito a reserva e disponibilidade, sem reservar; Mind → workshop → VIP como menor upgrade;
"me lista todos os workshops" → **12 de 12**, sem corte. Entrada `mindagent-web` sem origem
autoritativa continua caindo no Router (`rota_origem: router`).

Fail-closed conferido direto no writer: `next_route` com rota inexistente e com rota fora da
política do canal (`summit_b2c`) **não persistem** e não afirmam handoff; rota igual à atual
vira `null` antes de gastar Gate.

Memória conferida: 6 interesses permitidos num turno → 6 salvos; 4 permitidos + 1
`saude_do_titular` → `saved 4, blocked 1, promoted 0`; `opportunity + high` → `ativa`;
`temporary`, sensível e sem classificação → não persistem; `medium` → `proposta` e `proposta`
não volta para o Agent; numa sessão com 10 interesses e 3 memórias ativas, "me indica uma
sessão boa pra mim" respondeu ancorado em liderança, segurança psicológica e cultura — a
memória chega ao modelo e ao Kit sem corte em 3.

**Divergência material nova.** `analise_concierge` **não é exclusivo do App**: o cron
`analise_conversas` (job 12) também o aplica a conversas de **WhatsApp**. Com o Passo 5 ele
passou a de fato gravar memória durável — 12 linhas desde 05:30 de hoje, as 12 com
`sensitivity`, e antes disso ele nunca havia gravado nenhuma. O impacto está contido: a única
função que **lê** `intelligence.participante_memoria` é `mindagent_chat_get_context`, ou seja,
o App. `treble-inbound-agent` não lê. Não há efeito no comportamento da lane #40, mas quem for
mexer no analisador precisa saber que o contrato de memória do Passo 5 hoje governa também as
conversas de WhatsApp. Registrar em #42.

**Pendência que não é regressão desta lane.** O modo ação do Play responde
`502 acao_falhou` porque as RPCs `mind_play_nps`, `mind_play_feedback_sessao`,
`mind_play_feedback_evento` e `mind_play_feedback` **não existem no banco** — nunca existiram
neste repo, que só tem o ledger de idempotência (`mind_play_chamada_iniciar/concluir`). O
caminho de ação dentro da `mindagent-chat` está intacto e não foi tocado pelos Passos 5 e 6
(`git diff 4bae649^ 4bae649` não altera nenhuma linha de Play): ele valida a ferramenta,
resolve a sessão e recusa com o código certo. Os writers são da lane E/#43.

**Divergência conhecida e aceita entre repo e produção.** O código publicado difere do arquivo
do repo em exatamente dois pontos: `/[\u0300-\u036f]/g` no repo aparece como a classe literal
equivalente no bundle publicado. Mesma faixa de caracteres, nenhuma diferença semântica.


#### 02/09, mais tarde — REVISÃO, INCIDENTE E O TECLADO

Quatro coisas depois do bloco acima. Branch `claude/go-live-vendedor-runtime-hjobov`.

**Os 3 deltas da revisão da Adriana** (`292f2f0`, `mindagent-chat` version 30 / v1.9.1):

1. **O App estava fora do pós-turno.** `analise_pendentes` filtrava
   `c.agente in ('treble','treble-inbound-agent')` — só WhatsApp. Todas as análises daquele
   dia vieram de `agente='treble'`; nenhuma do App. Ou seja, o contrato de memória durável
   do Passo 5 nunca era exercido numa conversa do App. `20260902120000` acrescenta uma
   palavra ao universo; quem escolhe o analisador continua sendo o `analise_classificador`,
   que já é canal-agnóstico. Registro de erro meu: o comentário anterior dizia
   "`analise_concierge` também roda no WhatsApp" porque juntei `participante_memoria` a
   `conversas` por `participante_id` — isso conta qualquer conversa da pessoa, não a que
   produziu a análise. O caminho certo é por `analise_conversa`.
2. **Evidência do interesse** — `20260902...`/runtime: a correção do PR #52 (`27af67a`)
   trazida verbatim, `userMessage.mensagem_id` no lugar de `.id`, mais o stub do harness
   passando a espelhar a forma real. Antes: 19/19 interesses com `evidencia_message_id`
   nulo, e zero linhas com evidência em toda a tabela.
3. **Menus e reserva no playbook** — `20260902130000`. O menu chama-se `Programação`,
   nunca "Agenda"; ao recomendar Arena LinkedIn, Arena Sextante, workshop ou Masterclass,
   lembrar de agendar e conferir em `Minha Agenda`; Arena Mind é exceção e não exige
   reserva.

**A home passa a trocar de tela pela data** (`da5c77a`). A regra JÁ EXISTIA e estava
desligada: `api.mindagent_home_publico`, em `modo='programado'`, resolve o momento pegando
a última troca cujo horário já passou, no fuso do evento, sem cron. Faltava o dado —
`trocas` vazio e `modo` em `manual`, com a home pregada em `no-evento` desde 01/09. A
programação está em `docs/sql/home-v3/07-programacao-das-telas.sql`; a tela própria do Dia 2
não existe e está em `BACKLOG.md` §15.

**INCIDENTE — o App e o vendedor ficaram fora do ar** (`f0c9dd5`). Às 06:58,
`mindagent-chat` devolvendo `503 official_data_unavailable` em toda conversa.
`public.mind_customer_intelligence`, da entrega de Customer Intelligence
(`20260902140000`), ordenava a identidade de HubSpot por `i.atualizado_em` — coluna que
`engagement.identidades` não tem. PL/pgSQL só resolve nomes de coluna na execução, então a
função foi criada sem erro e o `BEGIN/ROLLBACK` estrutural não podia pegar.

O bloco `customer_intelligence` entrou nos Kits das QUATRO rotas, e como `mind_agent_kit`
monta todos os blocos, a exceção derrubava o Kit inteiro — App (Concierge e Atendimento) e
vendedor no WhatsApp. **O fail-closed funcionou como projetado**: foi ele que transformou
um erro de coluna em indisponibilidade visível em vez de resposta inventada sem dado
oficial. Corrigido em `20260902150000` trocando um token para `i.criado_em`; as outras
referências a `atualizado_em` no corpo são válidas e ficaram. Varreduras depois: 60 pessoas
de perfis variados e 30 conversas reais nos dois canais, zero exceções.

**Lição para o dia do evento, não resolvida:** qualquer bloco de Kit que levante exceção
derruba o Kit inteiro e cala o agente. Se um bloco OPCIONAL pudesse falhar sozinho sem
levar junto `evento` e `programacao`, um erro assim viraria degradação em vez de queda. É
mudança no contrato do fail-closed — decisão da Adriana, não feita.

**O teclado deixou de empurrar a tela do Concierge** (`c044d4b`). Causa: a tela é uma
coluna flex de `height: 100dvh`, e no iOS o teclado não encolhe o viewport de layout nem
muda `100dvh`/`innerHeight` — encolhe só o VISUAL. A página continuava desenhada com a
altura inteira e o Safari rolava o viewport de LAYOUT para trazer o campo focado à área
visível: quem subia era a página, não o campo. `teclado.js` publica `visualViewport.height`
em `--app-altura` e o body virou `position: fixed` com essa altura.

Segundo defeito no mesmo sintoma: ao enviar, o código fazia `campoChat.disabled = true` —
desabilitar um campo focado tira o foco, e no iOS isso fecha o teclado; o `focus()` de
volta, fora de um toque, o iOS ignora. O teclado fechava a cada mensagem e não voltava.
Quem impede envio duplicado é `respostaEmAndamento`.

Medido em navegador em 393×852, 852×393 e 375×667, nos quatro estados: header imóvel,
composer no fim da área visível, distância até o fim da conversa zero, `scrollY` zero, foco
preservado inclusive durante o envio. **Não testado em iPhone real** — o critério de aceite
que pede isso continua aberto. A bottom navigation do diagrama da Adriana **não existe
nesta tela** (o `#fnav` é o telefone simulado do tour); a regra que a esconde está escrita e
inerte, e falta saber se a barra é do app hospedeiro.

---

### D — pós-turno / memória / write-back / Silence

- **Issue:** #42
- **PR #46:** coletor de memória, draft
  - HEAD mais recente: **`1244b1809301246f9110a57a176d3c8c3f18ef97`**
- **PR #51:** memória segura + D1/D2, draft
  - HEAD mais recente: **`5712fe027531a42a5f057695b7c8d83deff40c60`**

- **PR #70:** write-back comercial HubSpot — **MERGEADA** em `6f9c899bc994e7f8a9d8f2fe312f8368c636943f`
  - migration registrada em produção: `20260903041743_hubspot_commercial_writeback`;
  - Edge `hubspot-commercial-writeback` **version 1 / ACTIVE**, `verify_jwt=true`;
  - modo padrão `preview`; `apply` continua atrás de `HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED=true` e permanece desligado.

**03/09 — gate aprovado e publicação segura da #70.** A migration exata do commit mergeado foi
aplicada e registrada no ledger oficial do Supabase. O contrato SQL versionado passou novamente
em produção dentro de `BEGIN/ROLLBACK`: DDL, RLS/grants, FKs sem cascade, deduplicação por pessoa,
idempotência, backoff e teto de três tentativas apenas para update, sem retry automático para
create. O rollback removeu todas as fixtures; a tabela `crm.hubspot_commercial_writeback`
permaneceu com **zero linhas**.

A Edge publicada corresponde ao código mergeado, exige JWT no gateway e valida credencial
administrativa no runtime. Smoke com chave pública foi recusado com **401 `unauthorized`**.
Não foi criado atalho, não se desligou JWT e não se expôs chave administrativa para completar
o teste HTTP.

A prévia de negócio em produção, com corte `2026-09-02T00:00:00Z`, encontrou exatamente
1 pessoa candidata e terminou em **0 creates, 0 updates e 1 bloqueio**
(`contato_hubspot_ausente`). O ledger ficou vazio. A amostra histórica de Marianne Santana
continua inalterada no HubSpot: estágio `1401915457` (Novo lead), sem `hs_lead_label`;
portanto a sugestão Novo lead → Aguardando contato humano + HOT não foi aplicada.

A implementação continua sem escrever identidade e consome somente os contratos canônicos
`public.mind_crm_comercial(pessoa_id)` e `public.mind_pessoa_fatos(pessoa_id)`. O backfill
de todas as conversas e a fila humana de divergência de estágio permanecem no
`BACKLOG.md` §7. O próximo gate é um teste HTTP autenticado em `preview` por uma execução
server-side autorizada; só depois cabe discutir habilitar `apply` num teste controlado.

**03/09 — auditoria incremental e trava terminal (#81).** Enquanto o HTTP autenticado de preview
aguarda execução em ambiente local confiável, foram auditadas as 722 conversas que já possuíam
análise comercial desde 29/08, sem produzir backfill. Cinco análises tinham estado terminal
incompatível com a própria transação: 3 `CLOSED_WON` sem compra/negócio ganho e 2
`CLOSED_LOST` com negócio ainda aberto. A leitura das conversas confirmou falsos positivos
materiais, incluindo nota 5 da pesquisa de encerramento confundida com venda, checkout falho
confundido com ganho e encerramento operacional confundido com perda.

A PR #81 foi mergeada em `a6bcbdcb268bd40620017b67d45252bd70d537eb`. A Edge
`hubspot-commercial-writeback` foi republicada como **version 2 / ACTIVE**, com
`verify_jwt=true`. Agora ganho exige `purchase_status=purchased` ou
`deal_status=won/closed_won`; perda exige `deal_status=lost/closed_lost`. Estado terminal
sem confirmação fica bloqueado por `estado_terminal_sem_confirmacao_transacional`.
Passaram 16/16 contratos. `apply` continua desligado, o ledger continua com zero linhas e
não houve escrita no HubSpot nem em identidade.

A revisão dos 15 casos do runtime novo mostrou boa coerência geral nos drivers usados pelo
write-back. `asked_discount` perde parte dos pedidos explícitos de condição especial, mas não
tem consumidor no runtime, SQL ou write-back atual; não foi alterado.

Chunk atual aceito tecnicamente:

- `mind_memoria_fatos(pessoa_id)` pronto/desligado;
- coletor só expõe `valor.sensitivity='none'`; legado v1 fica preservado e invisível;
- `analise_vendas_summit` v2 emite `sensitivity`;
- `analise_projetar_memoria` fail-closed **só para analisador sob contrato**;
- revalidação adiciona marcador sem duplicar;
- substituição `ativa → ativa` identidade/cargo/empresa corrigida;
- `mindagent_chat_save_interests` também é fail-closed **antes** de `session_interests`, memória e perfil;
- Silence D1 corrigido no contrato; D2 exige `followup_count > 0` para `followup_exhausted`;
- #51: **11 contratos** em transação revertida;
- #46: **9 contratos** em transação revertida;
- produção segue sem coletor/gate novos; cron 13/outbound desligado.

**Rename da #46 JÁ FOI FEITO**:

```text
20260830230000_15_mind_memoria_fatos.sql
→ 20260830234000_15_mind_memoria_fatos.sql
```

HEAD #46 atual `1244b18`. O preview da #46 ficou **stale e vermelho por causa do ledger antigo do próprio preview** (`Remote migration versions not found in local migrations directory`). Isso não é evidência contra o diff atual. Não recriar/resetar preview só para deixá-lo verde. Evidência válida: 9/9 contra produção em transação revertida com a migration atual.

Produção observada: **887 memórias**; a 887ª veio de atividade real do cron 12, não de fixture. Prompt ainda v1; coletor não existe; cron 13 off.

**Próximo movimento D:** aguardar/acompanhar integração C para ordem correta, então integrar migrations seguras e continuar a lane — wiring de leitura da memória no runtime correto, pós-turno do Concierge, write-back realmente necessário dentro do gate de CRM/source-of-truth e continuidade/Silence até o limite permitido. **Não ligar cron 13/outbound.**

---

### E — Play / experiência do Concierge

- **Issue:** #43
- **PR:** #48, draft
- **Branch:** `claude/go-live-play-labrz9`
- **HEAD mais recente verificado:** **`2a08e26eb756dc9d33b5aa307710fc15cc3a256d`**

Já feito:

- writers person-bound `mind_play_feedback_sessao`, `mind_play_nps`, `mind_play_feedback_evento`, `mind_play_feedback` + agregado;
- zero tabela/coluna nova;
- UI real tenta persistir insight/nota/NPS e não mente dizendo “Guardei” quando falha;
- Play não exige conversa prévia; reusa auth/sessão/identidade;
- v1 não aceita coleta anônima;
- slides/materiais deferidos até source canônico;
- contrato cliente já é compatível com executor Play da #50;
- SQL 9 contratos; navegador real 8 contratos no estado atual da PR.

**Rename E ainda está pendente** para manter E por último:

```text
20260830231500_lane_e_play_coleta.sql
→ 20260830235000_lane_e_play_coleta.sql
```

Depois: sincronizar com C, apontar `CONFIG.playActionUrl` para a mesma `mindagent-chat` quando ela estiver publicada e fazer E2E real: pessoa identificada, sem conversa prévia, entra no Play e grava coleta person-bound nas casas canônicas.

Não consertar `mindagent_bootstrap` pela metade: hoje o fallback local preserva temas que o banco ainda não consegue devolver sem regressão.

---

## 4. Ordem de migrations pretendida

```text
#47 B   20260830210000
#49 A   20260830220000   [JÁ EM MAIN/PROD]
#50 C   20260830223000
#50 C   20260830233000
#46 D   20260830234000   [RENAME FEITO]
#51 D   20260830234500
#48 E   20260830235000   [RENAME PENDENTE]
```

Não crie segunda migration para corrigir número de arquivo que nunca rodou em produção.

---

## 5. Ordem de integração/deploy

```text
B — review final do HEAD vivo → merge → deploy manual Edge → flag → E2E WhatsApp
→ C — review final → merge migrations/código → DB vivo → deploy manual mindagent-chat → E2E Concierge
→ D — migrations seguras → wiring pós-turno/memória/write-back/continuidade dentro dos gates
→ E — rename + migration/UI integrada ao executor C → E2E Play
→ E2E transversal Vendedor + Concierge + Play
→ reconciliar CORE_UNIVERSAL/BACKLOG/PROJECT_STATE no estado final
```

**Ordem de deploy ≠ ordem de trabalho.** D/E podem corrigir coisas independentes enquanto B/C fecham.

---

## 5B. 03/09 — checkout atribuído + venda contextual no App

Gate de produto dado pela Adriana nesta conversa. Implementado e publicado em produção:

- migration `20260903002220_checkout_attribution_agents.sql` aplicada;
- `mindagent-chat` **version 32 / v1.10.0**, `verify_jwt=true`;
- `treble-inbound-agent` **version 32 / v1.6.0**, `verify_jwt=false` como antes;
- `mindagent-web → summit_b2c` ativo, sem mudar a entrada `mind_summit_app → concierge_summit`;
- checkout aceito somente se for `https://*.eduzz.com` e corresponder exatamente a um
  `checkout_url` oficial do Kit, preservando parâmetros de negócio como cupom;
- URL emitida com canal, `ai_agent`, campanha/id, motivo, Agent e token opaco; nenhuma PII;
- ledger idempotente em `engagement.agente_eventos` e leitura de conversões em
  `intelligence.v_conversoes_agente`.

Evidência: 10/10 testes novos, 16/16 contrato de resposta longa, 71/71 guardrail comercial e
contrato SQL real em `BEGIN/ROLLBACK`. O teste SQL provou retry sem duplicação e venda espelhada
voltando para evento + conversa. Não houve compra real: `envios_reais=0` e `conversoes_reais=0`
logo após o deploy.

Correção de conversão publicada depois na PR **#76** (`c2f62103e4145b904f517136275308069019b6c6`):
`treble-inbound-agent` **version 35 / v1.6.2**. O checkout oficial agora é resolvido antes da
decisão do guardrail. Se a copy livre do modelo contiver um preço rejeitado, o runtime descarta
toda a copy, mantém somente uma frase neutra sem preço e envia o checkout oficial rastreado. Sem
checkout oficial, o bloqueio e o handoff continuam fail-closed. E2E direto na Edge com
“Quero comprar um ingresso Prime agora. Pode me enviar o checkout?” retornou HTTP 200,
`checkout_sent=true`, `needs_human=false`, rota `summit_b2c` e gravou
`checkout_link_enviado` (`7d09e03f-85ef-50a0-bde3-160516ed00b8`). Contratos locais: 76/76 do
guardrail e 10/10 de atribuição/runtime.

Institute e pré-venda do Summit seguinte ficaram deliberadamente sem oferta/URL nesta entrega.
O runtime já suporta ambos; falta cadastrar a verdade comercial e o `checkout_url` oficial nos
Kits antes de permitir qualquer envio.

---

## 5D. 03/09 — credenciamento person-bound + cadastro B2B obrigatório

Gate explícito dado pela Adriana nesta conversa. Implementação registrada para publicação:

- `public.mind_credenciamento_fatos(pessoa_id)` lê o espelho existente pelo `pessoa_id`
  canônico e devolve cadastro do participante, categoria(s) ativa(s) e quantidade;
- nome, e-mail e WhatsApp do participante entram somente quando são inequívocos; dados do
  comprador permanecem armazenados no espelho, mas não entram no contexto do modelo, não são
  tratados como dados do participante e não ganharam endpoint de consulta;
- `mind_agent_context`, `mind_conversa_estado` e `mindagent_chat_get_context` recebem o mesmo
  bloco factual; WhatsApp e App deixam de ter leituras diferentes do ingresso;
- `SEM MAPA` e registros revogados não viram ingresso ativo; múltiplas categorias são
  preservadas sem inventar hierarquia;
- no B2B, se faltar primeiro nome, sobrenome, e-mail, WhatsApp, empresa ou cargo em perfil ou
  credenciamento, o agente sempre coleta o próximo campo, uma pergunta por mensagem;
- resposta, preço, calculadora, checkout e handoff vêm antes da pergunta cadastral no turno, mas
  não encerram a coleta enquanto faltarem campos e houver conversa;
- e-mail e WhatsApp informados chegam mascarados ao modelo e têm o formato validado pelo Core;
  WhatsApp declarado é gravado como evidência não verificada, sem substituir o número do canal;
- nome coletado também hidrata a identidade sem usar nome como chave;
- o ingresso é Intelligence da pessoa, não bloco do Product Kit. O Kit continua responsável por
  produto, disponibilidade, oferta e restrições.

Dry-run em produção dentro de `BEGIN/ROLLBACK`: 13 contratos SQL passaram, incluindo fixture
com 2 ingressos VIP ativos, 1 `SEM MAPA` e 1 Mind revogado. Nenhuma fixture sobreviveu.

---

## 6. Gates vigentes

Exigem decisão/gate explícito antes da execução perigosa:

- preço, desconto ou regra comercial;
- alteração destrutiva/irreversível de dados;
- auth/RLS/security/secrets/identidade;
- source of truth;
- outbound/disparo, inclusive cron 13;
- write-back material em CRM sem contrato já fechado;
- publicação de runtime vivo quando a mudança materializa comportamento novo de produto/canal;
- outra mudança material de produto não congelada.

Já fechado e não precisa ser rediscutido:

- Router com seis rotas;
- semantics Gate/Kit;
- regra comercial atual = exatamente regras/playbooks ativos, sem D1–D4 revelado;
- `mind_lead_capturar` não deve ser criada;
- Play v1 person-bound;
- slides deferidos;
- `sensitivity` usa taxonomia existente e escrita fail-closed;
- `concierge.prompts` fica intacta/histórica por enquanto;
- C pode emitir `sensitivity` antes de D estar live;
- `schema_dados` não volta como proxy no `mind_kit_evento`.

---

## 7. NÃO reabrir agora

- completar toda Intelligence do Summit;
- taxonomy/conceitos novos;
- RAG/vector sem necessidade real;
- ~~Intelligence Inbox/autodiscovery~~ — **liberado em 21/09/2026**: esta linha protegia o
  prazo do Summit, que já aconteceu. Ver a revogação em `BACKLOG.md` §12.11;
- limpeza de legado por estética;
- segunda identidade/backend/session lifecycle para Play;
- `mind_lead_capturar`;
- cron/outbound antes do gate;
- fonte falsa para slides/materiais;
- `mindagent_bootstrap` retornando `temas=[]` só para “ficar verde”.

---

## 8. Regra de retomada para IA nova

1. leia o prompt da seção 0 e os documentos na ordem indicada;
2. **re-fetch** PRs #47/#50/#46/#51/#48 e issues #40–#43 antes de confiar nos HEADs acima;
3. PR/issue mais recente vence este snapshot para trabalho ainda não integrado;
4. produção vence documentação em claims de estado vivo;
5. preserve decisões fechadas;
6. comece pelo **primeiro próximo movimento seguro** na ordem de integração;
7. não pare por CI, review ou espera técnica; pare somente em gate real.

GitHub é o barramento entre lanes. Coordene por comentário/review nas issues/PRs, não por Adriana.


---

## 5C. 03/09 — B2B ligado ao produto do playbook

Gate explícito dado pela Adriana e publicado em produção:

- migration `20260903050000_contexto_produto_b2b_por_playbook.sql` aplicada;
- `playbook_summit_b2b` version 8 ligado a `mind-summit-2026` por `produto_codigo`;
- B2B recebe somente o produto ligado ao próprio playbook, nunca o catálogo inteiro;
- catálogo confirma `ativo` e `vende`; quando `vendavel_agora=false`, ofertas e preços por volume ficam vazios e nenhum checkout pode ser oferecido;
- a proibição de coleta cadastral registrada neste passo foi superada pela decisão explícita da seção 5D;
- módulos genéricos duplicados deixaram de ser montados no B2B; B2C permaneceu inalterado;
- avisos operacionais do Concierge e ofertas duplicadas dentro de inclusões deixaram o Kit B2B.

Validação viva: contrato SQL passou; prompt B2B caiu de 77.018 para 32.184 caracteres e o `structured` de 46.093 para 24.616. B2C continua em 80.757 + 36.335 e ainda recebe quatro produtos, portanto exige auditoria própria. Busca dinâmica de agenda/palestrantes continua ativada em `treble.config.bloco_agenda_busca=true`.

A compra prévia da pessoa não é equivalente à vendabilidade global. Exemplo: uma participante Prime não deve receber nova oferta individual do Summit, mas ainda pode comprar uma delegação corporativa. A elegibilidade por pessoa, momento, produto já possuído e upgrade permitido ficou para a auditoria B2C/person-state. Código reconciliado no commit `28d682bdbb6a4e4c90a0426aeaa295959b9705bc`.


---

## 5D. 03/09 — pós-turno: fila por recência, ICP visível, backfill e classificador v3

Auditoria do pós-turno/memória (Lane B, 03/09 05:30 UTC, sistema real) e quatro correções
autorizadas pela Adriana e aplicadas em produção. Detalhe e evidência na issue #42.

O que estava acontecendo:

- `analise_pendentes` ordenava por uuid, e o `analisar-conversa` pula sem gravar nada a conversa
  sem texto do lead ou classificada para analisador de prompt vazio; as 10 menores uuids pendentes
  eram todas desse tipo → 77 conversas substantivas (10 do App) presas atrás da cabeça; das 31
  análises feitas desde 02/09 20:00, 30 tinham uuid menor que a cabeça;
- na janela de rollout do Passo 4 (02/09 06:45–10:15 UTC), 28 análises `analise_concierge` do App
  emitiram 63 itens válidos — incluindo os 16 únicos ICP/JTBD já emitidos pelo sistema — e nenhum
  chegou a `participante_memoria`;
- todo ICP emitido era `medium` → `proposta` → invisível; `crm.contato_espelho.icp` preenchido em
  13 de 12.394 contatos;
- o classificador v2 não mandava cargo/empresa/desafio profissional ao `analise_concierge`, único
  analisador que conhece ICP/JTBD (258 análises de vendas com cargo/empresa; 16 também concierge).

O que foi feito (migrations persistidas neste repo; aplicadas via MCP em 03/09 05:45–05:55 UTC):

- `20260903060000_fila_do_pos_turno_por_recencia.sql` — `order by ult_msg desc` e fala do lead
  com texto (o mesmo filtro que `analise_montar_contexto` já aplicava);
- `20260903061000_icp_medium_ocupa_slot_vazio.sql` — patch cirúrgico no writer (padrão Passo 4 §4):
  ICP `medium` vira `ativa` só quando não há ICP ativo; `medium` continua não derrubando ativo;
  `high` continua substituindo;
- `20260903062000_backfill_projecoes_perdidas_0209.sql` — replay do writer nas análises concierge
  sem memória vinculada, sem passar por `analise_gravar` (não reexecuta Silence): 72 linhas
  ligadas às 28 análises (62 ativas); ICP 2 ativos, JTBD 6 ativos + 6 propostas;
- `20260903063000_classificador_v3_conhece_a_pessoa.sql` — critério 5 inclui cargo/função/empresa/
  desafio profissional; o exemplo do RH com 30 gestores passa a acionar vendas + concierge.

Validação viva: `tests/pos_turno_fila_e_icp_contract.sql` (transação encerrada em ROLLBACK) —
contratos 1, 2 e 3 PASSARAM. Pessoas do App com Customer Intelligence visível ao Kit: ICP 0→2,
jobs 0→6, interesses 4→13, cargo 2→4 (de 33).

Ficou para a Lane D (BACKLOG §18): marcador durável de "pulada" no `analisar-conversa` (não
versionado aqui); 1.253 memórias `proposta` de `analise_vendas_summit` invisíveis a todo leitor;
analisadores de prompt vazio.
