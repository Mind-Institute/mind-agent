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
| plano do HubSpot | `public.mind_hubspot_perfil_plano()` | uma linha por pessoa: `jobtitle`, `company`, `icp` + `icp_confianca`, `jtbd[]`; só `service_role` |
| escrita no HubSpot | Edge Function `hubspot-perfil-writeback` | ENSAIO por padrão (`executar: false`); relatório com `substituicoes`, `equivalentes`, `conflitos`, `ignorados` |

## 2. Como a regra decide

**ICP** (`intelligence.icp_por_cargo(cargo, empresa)`): determinístico, sem IA. Ordem das checagens
= decisão: concorrente pela empresa (`regex_empresa`, hoje só Vittude) → saúde → RH (consultor de RH,
analista/BP, decisor, gestor) → consultor/coach → academia → fundador/sócio → C-suite → diretor →
gestor → analista → outros. Fonte do cargo, por prioridade: credenciamento (Yazo) → conversa
(`cargo_atual` do analisador) → espelho do HubSpot → `pessoas.pessoas`.

**JTBD** (`intelligence.perfil_evidencias` → `intelligence.perfil_projetar`): uma linha por evidência,
depois agregada por job: confiança = maior evidência + 0,05 por evidência extra (teto 0,90); ≥ 0,70
vira memória `ativa`, abaixo vira `proposta`.

| evidência | confiança | de onde |
|---|---|---|
| check-in numa sessão marcada | 0,70 | `"Check Ins Summit"` × `sessions.jtbd` |
| reserva sem check-in | 0,60 | `"Reservas_Agenda_APP"` |
| interesse/objetivo declarado na jornada do app | 0,50–0,70 (por chave) | `engagement.session_interests` via `sinais.interesses` |
| job-raiz observado em conversa (JT01–JT15) | a confiança da memória | `jt_raiz` + `sinais.jt_filtro` (NR-1 vs programas; JT04 → treinar lideranças só para RH) |
| sinal de patrocínio (memória ou análise) | 0,60 / 0,70 | `sinais.patrocinio` |
| produto preferido em conversa (Dash, consultoria) | 0,70 | `sinais.conversa.preferred_product_regex` |
| contexto por família de ICP | 0,50–0,60 | `sinais.contextual` (RH + liderança → contratar treinamento; especialista + programas/NR-1/ROI → autoridade, vender para RH) |

Regras de convivência: memória de conversa (`analise_*`) nunca é derrubada pela regra — quando
divergem, a regra entra como `proposta`; ICP marcado à mão no HubSpot vence tudo (a regra não
escreve); rodar de novo é idempotente (a origem `regra_perfil` atualiza o que ela mesma gravou).

**Cargo e empresa no HubSpot** (`mapping.ts`): preenche vazio; quando já há valor, compara pela
chave normalizada (`texto_chave`); mesma chave, uma contendo a outra ("CEO / Fundador" × "CEO") ou
distância de edição pequena ("Beiersdorf" × "Beiwrsdorf") = **não escreve** (vai para
`equivalentes`); coisa diferente de verdade = escreve e lista em `substituicoes` para a Adriana rever
(o HubSpot guarda o histórico da propriedade, dá para voltar). ICP só preenche vazio. JTBD é a união
com o que já está lá.

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

## 4. Plano — o que vem, na ordem (autônomo, com os gates marcados)

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

- Opção `Fundadot / Sócio / Empreendedor` no HubSpot tem typo no rótulo e no valor interno: o valor
  fica (é interno), o rótulo ela corrige na tela (ou `acao: "propriedades"` corrige, com o escopo).
- `icp_confianca` no HubSpot recebe 7 (regra por cargo, escala 0–10) — a taxonomia chama de "forte".
- 18 pares de pessoas do banco apontam para o **mesmo contato** no HubSpot (`contato_repetido_no_recorte`):
  candidatas a fusão em `engagement.identidade_fusoes` — decisão dela.
- `treinar_liderancas` e `autoridade_escala` só aparecem por contexto (0,5–0,6 → `proposta`);
  para virarem `ativa` precisam de evidência direta (conversa ou 4a).
