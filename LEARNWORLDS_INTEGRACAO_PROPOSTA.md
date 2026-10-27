# LearnWorlds — levantamento e proposta de integração

> **23/10/2026: Fase 1 no ar** (aprovada pela Adriana: credenciais, tabelas e sincronização). Webhook: não
> agora. Matrícula automática (Fase 3): depois, disparada pelo pagamento da Eduzz — o LearnWorlds não recebe
> pagamento, só entrega o curso. Detalhe do que está no ar em §7.
>
> **Estado em 22/10/2026.** Levantamento feito na documentação oficial da API do LearnWorlds
> (learnworlds.dev, 150 páginas) e no Supabase `mind-agent` (`ymnmotgglsrxmjmonwjz`).
> Nada foi criado além do que já estava aprovado (identidade da MIA, §6). Tabelas novas (D2),
> funções (D7), segredos e matrícula (write-back) são gates da Adriana: cada item diz o seu.
> Pedido dela (22/10): tudo de LearnWorlds no schema `learnworlds`; saber os cursos e os códigos,
> as matrículas das pessoas, cruzar com o catálogo (à venda ou não) e, depois, matricular.

## 1. O que a API do LearnWorlds oferece (FATO, documentação oficial)

**Acesso**
- Só nos planos **Learning Center** ou **High Volume**. As credenciais saem da escola em
  *Settings → Developers → API* (Client ID e Client Secret).
- OAuth2 *client credentials*: `POST https://{escola}/admin/api/oauth2/access_token` devolve um token
  (`expires_in` em segundos). Toda chamada leva `Lw-Client: {id da escola}` e `Authorization: Bearer {token}`.
- Limite: **30 chamadas a cada 10 segundos** (acima disso, 429).
- Versão da API: v2, inalterada com a plataforma nova (v4). Bundles e assinaturas antigas viraram
  "Learning Programs", mas os endpoints antigos continuam funcionando (mapeamento interno).

**O que interessa a nós**

| Para quê | Endpoint |
|---|---|
| Cursos e o código de cada um (`id` é o slug) | `GET /v2/courses` (50 por página), `GET /v2/courses/{id}` |
| Programas / bundles | `GET /v2/bundles`, `GET /v2/subscription-plans` |
| Pessoas da escola | `GET /v2/users` (20 por página; filtros `registration_after`, `tags`, `cf_*`) |
| Matrículas de uma pessoa | `GET /v2/users/{id ou e-mail}/courses` (com `created` e `expires`), `.../products` |
| Quem está num curso / produto | `GET /v2/courses/{id}/users`, `GET /v2/users/by-product` |
| Progresso | `GET /v2/users/{id}/progress`, `.../courses/{cid}/progress` |
| Histórico de eventos | `GET /v2/event-logs` (filtros por pessoa, atividade e data) |
| Matricular / desmatricular | `POST` e `DELETE /v2/users/{id ou e-mail}/enrollment` (`productId`, `productType` course/bundle/subscription, `price`, `send_enrollment_email`) |
| Criar pessoa | `POST /v2/users` (`email`, `username`) |
| Login único (SSO) | `POST /admin/api/sso` (por e-mail ou ID; cria a conta se não existir) |

**Webhooks** (assinados com `Learnworlds-Webhook-Signature`, segredo em *Settings → Developers → Webhooks*):
cadastro/atualização de pessoa (`user_updated`), compra (`new_purchase`, inclui matrícula feita pelo
admin), matrícula em curso gratuito (`enrolled_free`), desmatrícula (`unenrolled_from_product`),
curso concluído (`course_completed`), programa concluído, certificado, tags, assinaturas e pagamentos.

**Identidade no navegador**: o código colado na escola recebe `{{USER.EMAIL}}`, `{{USER.NAME}}`,
`{{USER.ID}}` e campos `{{USER.CF_*}}` da pessoa logada (sem assinatura).

## 2. O que já existe do nosso lado (FATO)

- **Schema `learnworlds`** ("a entrega: a fila de matrícula no LMS"):
  - `learnworlds.produtos` (4 linhas): **o mapa programa → curso/bundle do LearnWorlds** (tratamento,
    preenchido à mão em 12/09). `certificacao-lideranca-positiva → bundle certificacao-avancada`,
    `mind-journey → course mind-journey-2026`, `seguranca-psicologica-aplicada-a-inovacao →
    course formacao-em-seguranca-psicologica`, `significado-e-proposito-no-trabalho →
    course formacao-em-engajamento-e-significado-no-trabalho`.
    Fora de propósito: `lideranca-consciente` (curso `teste` em rascunho no LW) e
    `certificacao-gestao-estrategica-bem-estar` (candidato `formacao1`, a confirmar).
  - `learnworlds.acessos` (2 linhas, ambas de teste, `pendente`): o **direito** que nasce de um pedido
    pago em `checkout.pedidos`. É a fila de matrícula: `api.fila_de_provisionamento` entrega o que falta
    matricular e `api.registrar_provisionamento` grava o resultado. O consumidor era o Worker do site
    do Join, **desligado desde 17/09**. **Sem `mind_id`** (lacuna da Regra #1).
- **Catálogo**: não há coluna que ligue `catalogo` direto ao LearnWorlds; o caminho é
  `catalogo.produtos.codigo ← institute.programas.produto_codigo ← learnworlds.produtos.programa_codigo`.
  "À venda" = `catalogo.produtos.vende` (+ `ativo`, `vende_de`, `vende_ate`). Dos 6 produtos do Institute
  à venda, 4 têm vínculo com o LW e 2 não (gestão estratégica, liderança consciente).
- **Identidade**: a porta única já aceita `learnworlds_user_id` (canal `learnworlds`, força 3) e
  `pessoas.v_pessoa_360` já tem a coluna; hoje **0** pessoas com ID do LearnWorlds.
  `mind_pessoa_enriquecer` já lê `learnworlds.acessos.destino_user_id`.
- **Segredos**: padrão vigente = **secret de Edge Function** + uma linha em `platform.integracoes`
  com o **nome** do secret (`eduzz → EDUZZ_API_KEY`, `hubspot → HUBSPOT_TOKEN`). O valor nunca entra
  no banco. Não existe credencial do LearnWorlds em lugar nenhum.
- **Modelo a copiar**: o Eduzz. Entrada "como a API devolve" (`eduzz.produtos`) separada do tratamento
  (`eduzz.produto_catalogo`, D9); sync por Edge Function com cron (`?token=analise_token`), estado em
  `public.espelho_estado`; pessoa resolvida pela porta única antes da escrita (`mind_pessoa_ligar_tabela`).
- **Nenhuma Edge Function fala com a API do LearnWorlds hoje.** `docs/CORE_UNIVERSAL.md`: o histórico de
  matrícula ainda não foi trazido.

## 3. Proposta

### Fase 0 — Credenciais (Adriana)
1. Confirmar que o plano da escola inclui a API (Learning Center ou High Volume).
2. Na escola: *Settings → Developers → API* → gerar Client ID e Client Secret.
3. No Supabase (*Edge Functions → Secrets*): `LEARNWORLDS_CLIENT_ID`, `LEARNWORLDS_CLIENT_SECRET`.
   Não colar os valores em conversa.
4. Linha `learnworlds` em `platform.integracoes` (`base_url = https://my.mindinstitute.com.br/admin/api`,
   `secret_ref = LEARNWORLDS_CLIENT_SECRET`) — casa existente, eu faço.
- **Gate:** segredos (Adriana).

### Fase 1 — Espelho de leitura: cursos, pessoas e matrículas
Tabelas de **entrada** no schema `learnworlds` (D9: guardam o que a API devolve, sem tratamento):

| Tabela | Uma linha por | Colunas principais |
|---|---|---|
| `learnworlds.cursos` | curso | `id` (o código/slug), `titulo`, `acesso` (gratuito, pago, privado, rascunho…), `categorias`, preços do LW, `criado_em`, `modificado_em`, `payload` |
| `learnworlds.programas` | bundle / learning program / plano | `id`, `tipo`, `titulo`, `cursos` (o que inclui), `payload` |
| `learnworlds.usuarios` | pessoa da escola | `id` (ID do LW), `email`, `nome`, `tags`, `criado_em`, `ultimo_login`, `suspenso`, `payload`, **`mind_id`** |
| `learnworlds.matriculas` | pessoa × produto | `usuario_id`, `produto_id`, `produto_tipo`, `matriculado_em`, `expira_em`, `payload`, **`mind_id`** |

- `usuarios` e `matriculas` entram na Regra #1 por `mind_pessoa_ligar_tabela` (e-mail +
  `learnworlds_user_id` → porta única, antes da escrita). Isso grava o ID do LearnWorlds em
  `engagement.identidades` para todo mundo da escola — a MIA reconhece a pessoa mesmo antes da
  primeira conversa.
- **Tratamento** continua em `learnworlds.produtos` (o mapa programa → produto do LW). Uma view
  `learnworlds.v_cursos_no_catalogo` cruza cada curso/programa do LW com o mapa e com
  `catalogo.produtos`: **à venda / não à venda / sem programa no catálogo**.
- Edge Function **`learnworlds-sync`** (cron, como o espelho do Eduzz): token OAuth → cursos, programas,
  pessoas (incremental por `registration_after`) e matrículas, respeitando 30 chamadas/10 s.
  Estado em `public.espelho_estado`.
- **Gates:** 4 tabelas novas (D2) e 1 função nova + cron (D7).

### Fase 2 — Tempo real (opcional)
Edge Function **`learnworlds-webhook`**: recebe cadastro, compra, matrícula gratuita, desmatrícula e
conclusão; confere a assinatura; grava o evento cru numa tabela de entrada
(`learnworlds.eventos`) e atualiza `matriculas`. O cron da Fase 1 continua como conferência.
- **Gates:** 1 tabela (D2), 1 função (D7), segredo do webhook.

### Fase 3 — Matricular pela API
A casa já existe: a fila `learnworlds.acessos` + `api.fila_de_provisionamento`/`api.registrar_provisionamento`.
Falta quem consome. Proposta: Edge Function **`learnworlds-matricular`** aqui (D8: nada de n8n), que
cria a pessoa se faltar (`POST /v2/users`) e matricula (`POST /v2/users/{e-mail}/enrollment`).
Antes, três decisões da Adriana:
1. **Quem consome a fila**: esta função ou o Worker do site do Join (desligado desde 17/09)? Os dois ao
   mesmo tempo matriculariam em dobro.
2. **Que vendas abrem acesso**: hoje só `checkout.pedidos` (Join) cria linha em `acessos`; as vendas do
   Eduzz (7.608 em `eduzz.vendas`) não têm caminho até lá.
3. **`mind_id` em `learnworlds.acessos`** (Regra #1): ligar a tabela pela `mind_pessoa_ligar_tabela`.
- **Gates:** write-back operacional (matrícula de verdade), função nova (D7).

### Ordem proposta
Fase 0 → Fase 1 (ler e cruzar; nada é escrito no LearnWorlds) → mapear no painel os programas que
faltam → Fase 3 (matrícula) → Fase 2 se o atraso do cron incomodar.

## 4. Decisões pedidas à Adriana
1. Plano com API e credenciais nos secrets do Supabase (Fase 0).
2. Aprovar as 4 tabelas de entrada e a `learnworlds-sync` com cron (Fase 1).
3. Fase 3: quem consome a fila e que vendas abrem acesso.

## 5. Achados laterais (registrados, não mexidos)
- As ofertas do Institute moram em `institute.ofertas` (16 linhas) e não em `catalogo.oferta_precos`,
  o que diverge da regra "preço mora no catálogo" (26/09).
- Os repositórios `Mind-Institute/LMS` e `Mind-Institute/joinmind.com.br` (consumidor antigo da fila)
  não estão liberados nesta sessão e não foram verificados.

## 6. Já feito nesta frente (22/10)
- MIA no LearnWorlds: bloco `learnworlds/mia-embed.html`; identidade pelo LearnWorlds (e-mail + ID) com
  `mindagent_chat_bind_identity` de 7 parâmetros (aplicada) e `mindagent-chat` 1.18.0 (não publicada).
  Ver `CHECKPOINT_ATUAL.md`.

## 7. Fase 1 no ar (23/10/2026)

- **Credenciais:** secrets `LEARNWORLDS_CLIENT_ID` e `LEARNWORLDS_CLIENT_SECRET` (Adriana). Conferidas pelo
  modo diagnóstico da função. `platform.integracoes` ganhou a linha `learnworlds` (só o nome do secret).
- **Migration `20261023115452_learnworlds_espelho_fase1`:** `learnworlds.cursos`, `learnworlds.programas`,
  `learnworlds.usuarios`, `learnworlds.matriculas` (entrada, D9; RLS; só `service_role`); `usuarios` e
  `matriculas` na Regra #1; escritor único `learnworlds_espelho_gravar` e estado `learnworlds_espelho_estado`
  (em `crm.sync_estado`); cruzamento nos dois schemas, como a Adriana pediu: `learnworlds.v_cursos_no_catalogo`
  e `catalogo.v_produtos_learnworlds` (quem lê o catálogo vê o ID do curso no LearnWorlds).
- **Edge Function `learnworlds-sync` 1.0.0** (v3, `supabase/functions/learnworlds-sync/`): lê cursos, bundles,
  planos, pessoas (200 por página) e matrículas por produto; grava em lotes de 50 (a porta única leva ~20 ms
  por pessoa nova e o banco corta a chamada em 8 s); retoma de onde parou se passar de 120 s.
- **Agenda:** cron `learnworlds_sync`, `11 */6 * * *` (migration `20261023120016_learnworlds_sync_cron`).
- **Primeira carga (23/10, 70 s):** 20 cursos, 3 bundles, 0 planos, **2.558 pessoas** e **2.334 matrículas**.
  Pessoas: 2.498 achadas pelo e-mail no cadastro, 60 criadas pela porta única; 0 conflito, 0 erro;
  2.558 IDs do LearnWorlds em `engagement.identidades`; 2.492 pessoas distintas (66 contas do LearnWorlds
  caíram numa pessoa que já tinha outra conta).
- **O mapa `learnworlds.produtos` está desatualizado** (aponta para cursos de 2025 e para `mind-journey-2026`,
  que não existe). A correção é decisão da Adriana; sugestão entregue a ela em 23/10:

| Produto do catálogo (à venda) | Mapa hoje | Sugestão (no LearnWorlds) |
|---|---|---|
| Certificação Liderança Positiva 2027 | bundle `certificacao-avancada` (rascunho) | bundle `certificacao-unificada` |
| Segurança Psicológica 2027 | curso `formacao-em-seguranca-psicologica` (2025) | curso `seguranca-psicologica-sugestao-pq-unica` |
| Significado no Trabalho 2027 | curso `formacao-em-engajamento-e-significado-no-trabalho` (2025) | curso `engajamento-sugestao-pg-unica` |
| Liderança Consciente 2027 | nenhum | curso `lideranca-consciente-sugestao-pg-unica` |
| Gestão Estratégica 2027 | nenhum | curso `especializacao` |
| Mind Journey 2027 | curso `mind-journey-2026` (não existe) | bundle `mind-journey2027` |

