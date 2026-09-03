# Estado da implementação — agentes comerciais e Concierge

Atualizado em 03/09/2026. Este documento separa o que está efetivamente em
produção do que ainda depende de acesso, decisão comercial ou teste externo.

## Resultado entregue

### Arquitetura agêntica compartilhada

- B2C, B2B e App usam o mesmo Agent Core: prompt-base, decisão, lupa/RAG,
  execução de ferramentas, memória, checkout rastreado e guardrails.
- Canal, contexto e playbook continuam específicos. Evoluções estruturais
  passam a beneficiar todos os agentes sem copiar lógica entre runtimes.
- O B2B preserva o contexto comercial; a redução anterior foi substituída por
  contexto pequeno com busca sob demanda, e não por perda de capacidade.
- O App começa como Concierge, mas pode trocar para venda B2C quando a intenção
  é Summit, upgrade ou outro produto que esteja oficialmente cadastrado.

PRs mesclados:

- [#84 — arquitetura agêntica unificada](https://github.com/Mind-Institute/mind-agent/pull/84)
- [#85 — jornada contextual do Concierge](https://github.com/Mind-Institute/mind-agent/pull/85)
- [#86 — inbox seguro de retomada](https://github.com/Mind-Institute/mind-agent/pull/86)
- [#87 — clique e abandono de checkout](https://github.com/Mind-Institute/mind-agent/pull/87)
- [#88 — abandono transacional e bootstrap vivo](https://github.com/Mind-Institute/mind-agent/pull/88)
- [#89 — índices e registro operacional](https://github.com/Mind-Institute/mind-agent/pull/89)
- [#91 — recuperação do Concierge e hotfix da Home](https://github.com/Mind-Institute/mind-agent/pull/91)

### Cadastro e CRM

- B2C e B2B coletam, antes do checkout: nome, e-mail, WhatsApp, empresa e cargo.
- Se a pessoa já existe em `pessoas.pessoas`, só são pedidos campos ausentes.
- O conector canônico é `pessoas.pessoas`; HubSpot Contacts vem antes de Lead.
- O runtime de criação/enriquecimento do contato e atualização do card foi
  publicado com modo preview seguro.
- Aplicação real no HubSpot continua desligada por
  `HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED`. Não ativar sem revisar o preview e os
  IDs de pipeline/stage do portal real.

### Checkout e atribuição

- App e WhatsApp registram `checkout_link_enviado` e entregam URL curta com UUID
  opaco; nenhuma UTM contém nome, e-mail, telefone ou CPF.
- `mindagent-checkout` registra o clique, reconstrói as UTMs e redireciona apenas
  para checkout Eduzz oficial.
- Origem, agente, motivo, rota, conversa, oferta e evento ficam associados.
- Compra paga vence qualquer inferência do modelo.
- Ausência de compra só vira `not_purchased` quando a sincronização completa de
  `eduzz.vendas` terminou depois do clique e a identidade canônica pode ser
  comparada por e-mail ou WhatsApp.

### Abandono e retomada

- Abandono é elegível 12 horas após o primeiro clique sem compra confirmada.
- WhatsApp respeita 09:30–20:30 e nunca agenda depois do fim da janela de 24h;
  fora da janela, o contato entra em grupo de HSM.
- Um abandono cria o item do inbox mesmo quando a análise assíncrona ainda não
  visitou a conversa. A evidência é determinística e auditável.
- Compradores, opt-outs e conversas pertencentes a humano são bloqueados.
- Estado atual do inbox em produção: 815 conversas; 520 acionáveis; 20 grupos de
  HSM. Distribuição: 2 `app_inbox`, 364 `needs_hsm`, 62 `waiting_window`, 92
  `purchase_check_required`, 86 `excluded_purchased`, 127 `blocked_optout` e 82
  `blocked_human_owned`.
- Dispatcher: `enabled=false`, `dry_run=true`. Fila: 0. Cron: inexistente.

### Concierge e programação

- Recomendações não mostram mais o falso botão “Salvar no meu Summit”.
- Respostas dos botões da jornada persistem sem depender de uma chamada ao LLM.
- Cargo e empresa geram apenas hipótese inicial de ICP; perguntas sutis refinam
  Job to be Done e interesses.
- Recomendações consideram o ingresso conhecido e falham fechadas para categoria
  cuja regra de acesso ainda não esteja cadastrada.
- O bootstrap oficial foi reparado para `summit_2026`, `ecossistema` e
  `concierge`. Resposta viva validada: 77 sessões, 63 pessoas, 10 temas e 18
  avisos.
- A curadoria de temas foi reposta na grade viva; 38 sessões têm tema hoje.
- O frontend também valida campos internos antes de desenhar, para que um valor
  nulo caia no fallback em vez de derrubar a Home.
- O deploy automático da Cloudflare foi confirmado após os merges: o app público
  já serve a validação nova e a rota `/c/:event_id` responde 307 para a Edge
  Function de checkout.
- A Home agora aceita avisos `no-ar` sem `disparo_em`; eles aparecem como `Agora`
  sem fabricar horário no banco.
- Se o modelo tenta dizer que não encontrou a informação sem usar a lupa, o runtime
  força uma chamada a `buscar_intelligence` antes da resposta final. Respostas
  factuais já sustentadas pelo Kit continuam sem busca e sem latência adicional.
- O input móvel usa 16px e a conversa contém URLs/palavras longas, evitando zoom
  automático do iOS e estouro horizontal.
- Diagnóstico completo: `INCIDENTE_CONCIERGE_20260903.md`.

## Testes executados

- 156/156 testes Edge/contrato.
- 76/76 contratos do guardrail de preço.
- Build completo do app Cloudflare e painel Admin.
- E2E real do App até o checkout Eduzz com identidade fictícia, sem informar
  cartão e sem concluir pagamento.
- Link testado: evento `065a3467-311c-5abf-8f14-6c10a2feecd4`, conversa
  `cd0d949d-9f36-4bd2-bcb6-af32b8f076a1`.
- O checkout abriu o ingresso Mind Lote 6 por R$ 1.647, preservou as UTMs do App
  e recebeu dois cliques (reabertura do navegador).
- Para o teste controlado, somente esses cliques fictícios foram retrodatados em
  13 horas. Resultado: zero conversões pagas, `not_purchased`, `app_inbox`,
  `very_hot`, objeção `checkout_abandonment`; nenhum item de fila e nenhum envio.
- RLS revisado nas tabelas novas. `checkout_clicks`, `recovery_inbox` e
  `recovery_dispatch_queue` têm RLS ativo, nenhuma policy pública e grants apenas
  para `service_role`. Índices de todas as FKs novas foram adicionados.

## Produção Supabase

Projeto: `ymnmotgglsrxmjmonwjz`.

Edge Functions ativas após esta entrega:

| Função | Versão | JWT | Papel |
| --- | ---: | --- | --- |
| `mindagent-chat` | 37 | sim | App/Concierge/venda |
| `treble-inbound-agent` | 38 | webhook próprio | WhatsApp B2C/B2B |
| `mindagent-checkout` | 1 | público controlado | clique e 302 para Eduzz |
| `mindagent-recovery` | 2 | sim/admin | refresh e rascunhos, sem envio |

Migrations desta sequência foram aplicadas manualmente, inclusive atribuição,
inbox, redirecionador, status transacional, bootstrap, temas, índices e a regra de
busca antes da abstinência do Concierge.

O Advisor ainda apresenta alertas antigos do projeto (principalmente funções
com `search_path` mutável, funções `security definer` historicamente expostas,
proteções de Auth e um índice duplicado em `summit_2026.sessions`). Os avisos
`RLS enabled no policy` das tabelas internas novas são intencionais: a ausência
de policy é o bloqueio, combinada com revogação de `anon`/`authenticated`.

Referências do Advisor:

- [Database linter — RLS sem policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
- [Database linter — índice duplicado](https://supabase.com/docs/guides/database/database-linter?lint=0009_duplicate_index)

## Pendências que exigem acesso ou decisão

1. **Domínio curto próprio.** A rota equivalente já funciona no Worker público;
   falta configurar `go.mindsummit.com.br/c/:event_id` na Cloudflare e definir
   `CHECKOUT_REDIRECT_BASE`. Até lá, a URL curta funcional continua sendo a Edge
   Function do Supabase.
2. **Embeddings.** O indexador está publicado, mas precisa ser invocado com
   credencial `service_role`/admin para gerar os embeddings. Busca lexical e
   lupa continuam funcionando enquanto isso.
3. **Rascunhos de retomada.** Invocar `mindagent-recovery` com credencial admin
   para `refresh` e `draft`; revisar os textos. Não usar `prepare`/fila para envio
   antes dessa revisão.
4. **Teste WhatsApp assinado.** Requer credencial Treble e deve ser feito em
   número controlado. Não houve mensagem real nem tentativa de contornar a
   assinatura do webhook.
5. **HubSpot APPLY.** Revisar preview, confirmar propriedades/pipeline e só então
   ativar `HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED`.
6. **Produtos no Summit.** Institute, upgrade e pré-venda 2027 dependem de preço,
   regra de elegibilidade, argumento e checkout oficiais. Até isso chegar, o
   agente não deve inventar nem vender uma oferta incompleta.
7. **Camarote.** A categoria existe no credenciamento, mas falta regra oficial de
   acesso por sessão; recomendações continuam conservadoras para ela.

## Ordem segura para liberar disparos

1. Gerar rascunhos e revisar amostra por objeção/canal.
2. Cadastrar e aprovar HSMs na Treble/Meta.
3. Fazer teste controlado em número interno, dentro e fora da janela de 24h.
4. Verificar opt-out, comprador, handoff humano, idempotência e horário.
5. Só então trocar itens aprovados de `draft` para `queued`.
6. Autorizar separadamente `enabled=true` e criar o cron.

Até essa autorização, o sistema observa, classifica e prepara; ele não envia.
