# Retomar — onde a gente parou (28/08/2026)

> Este arquivo é o mapa de volta. Leia junto com `docs/ARQUITETURA.md` (desenho do sistema)
> e `BACKLOG.md` (fila). Se algo aqui divergir do banco, **o banco ganha**.

---

## O desenho em uma tela

```
      ENTRADA (WhatsApp/Treble · app · site · futuro: e-mail, IG, telefone)
            │
            ▼
   ┌─────────────────────────────────────────────────────────┐
   │  public.mind_inbound(evento)   ← porta única de entrada  │
   │  1. resolve/abre a conversa                             │
   │  2. PERSISTE A MENSAGEM   ← antes de identidade e de IA  │
   │  3. resolve identidade (ancorada na conversa)           │
   │  4. liga conversa + mensagens à pessoa                   │
   │  5. vincula ao CRM só quando há evidência nova          │
   └─────────────────────────────────────────────────────────┘
            │
            ▼
      pessoas.pessoas  ← A PESSOA CANÔNICA
            │
   ┌────────┴───────────────────────────────────────┐
   │                                                 │
   ▼                                                 ▼
engagement.identidades              CONTEXTO (o que se sabe dela)
(como a reconhecemos:               ├─ mind_crm_fatos()      → HubSpot  ✅
 whatsapp · email ·                 ├─ eduzz.v_ingressos     → bilheteria ✅
 hubspot · auth_user)               ├─ eduzz.v_vendas        → compras   ✅
                                    └─ mind_crm_comercial()  → deals   ⏳ Passo 5
                                                 │
                                                 ▼
                                    AGENT_CONTEXT → ROUTER → playbook  ⏳ não construído
```

**As quatro regras que não se quebram:**
1. Canal não define identidade. CRM não define identidade.
2. `pessoas.pessoas` é a pessoa. `engagement.identidades` diz **como** a reconhecemos.
3. `engagement.conversas` + `mensagens` preservam a interação — sempre, antes de tudo.
4. **Uma porta só escreve identidade:** `mind_identidade_resolver`. Espelho, carga, backfill
   e view **nunca** escrevem. Na dúvida, vai pra fila `engagement.identidade_fusoes`.

---

## O que foi feito hoje

### 1. Playbook de objeções substituído
`agentes.prompts` chave `objecoes` → versão 2, ativo, 14.789 caracteres. Chega no
`treble_agent_prompt('b2c')` (65.852 caracteres no total).

### 2. Motor de Silêncio — ⏸️ PAUSADO de propósito
Construído inteiro e **desligado** (cron job 13, `active := false`). Estado, relógio, claim,
reavaliação e decisão funcionam; **REVIEW ≠ FOLLOW-UP**; o relógio é do código, a IA só decide
o QUÊ. Não envia mensagem nenhuma (`envia_mensagem: false` no contrato da edge).

**Não religue antes de decidir três coisas (D1/D2/D3 no `BACKLOG.md`).**
Pra religar: `select cron.alter_job(13, active := true);`

### 3. Fundação universal dos agentes (Passo 2)
`mind_inbound` como porta única. Treble, app e site viraram **adaptadores de canal** — três
implementações paralelas foram substituídas por uma. Código morto removido
(`mindagent_treble_*` apontava para tabelas que não existem).

### 4. Endurecimento da identidade (Passo 3)
- E-mail **citado** numa mensagem não é identidade. Só e-mail confirmado.
- Conversa já identificada é **âncora**: ganha de qualquer palpite novo.
- Telefone compartilhado não é evidência suficiente pra fundir pessoa.
- Fila mínima de resolução: `engagement.identidade_fusoes` (238 pendências registradas).
- **Desfeita** a promoção errada de 354 identidades que eu mesmo tinha causado no Passo 2.
- Grants fechados: `anon` conseguia criar pessoa, gravar mensagem e ler perfil alheio.

### 5. Ponte pessoa ↔ CRM (Passo 4)
`mind_crm_vincular_pessoa` é a **única** função que escreve `crm.contato_espelho.pessoa_id`.
`mind_crm_fatos(pessoa_id)` devolve o que o HubSpot sabe — **só fatos**, sem score nem ICP.
Chega nos contatos por `engagement.identidades (canal='hubspot')`, **nunca** por
`pessoas.hubspot_id` (a projeção legada diverge em 70 pessoas e aponta pra contato
inexistente em 20).

### 6. Espelho Eduzz — ✅ carregado hoje
`3.202 ingressos + 3.192 vendas`, carga completa em 5,4 s, cron job 14 (`:20` e `:50`).
Detalhe completo em `ARQUITETURA.md`. O essencial:

- **Este projeto não fala com a Eduzz.** Quem fala é o Supabase `mind-summit-vendas-dashboard`
  (`tkludhksqcnhhpgqyfqq`), que tem os tokens no Vault e já sincroniza sozinho.
- A `EDUZZ_API_KEY` guardada aqui **não abre nada** — não existe app OAuth pra conta 14449348
  (`/oauth/token` responde `App not found`). Isso está **fechado**, não é palpite: pra puxar
  direto daqui, tem que **criar um app OAuth na Eduzz** primeiro.
- `pessoa_id` **não é coluna, é junção** (nas views `v_ingressos`/`v_vendas`), pra
  ressincronização nunca apagar a ligação.

**Faturas: a dúvida está respondida.** A própria Eduzz diz `totalItems: 3185` para
2019–2026 (`/myeduzz/v1/sales`, referenceDate=createdAt) — e o espelho tinha exatamente
3.185 naquele momento (hoje 3.192, porque o sync de lá continua rodando). **O histórico de
vendas está completo.** O que *não* está completo é a bilheteria — é o passo de amanhã.

---

## Passo de amanhã — ingresso que NÃO vem de venda Eduzz

**Boa notícia: a pergunta que eu tinha deixado aqui já está respondida.** Com o catálogo do
`mind-hubpost` e o credenciamento espelhados, o vocabulário de origem **já existe** — não precisa
ser inventado. O trabalho é **reconciliar e completar**, não criar do zero.

### O que já existe

| onde | campo | valores reais |
|---|---|---|
| `eduzz.produto_catalogo` | `tipo_de_acesso` | Pago (92) · Cortesia (38) · **Patrocínio (17)** |
| | `tipo_de_venda` | Eduzz (102) · **Direta (12)** · Não é venda (55) |
| | `motivo_concessao` | Convidado (21) · Parceria (9) · Palestrante (2) · Imprensa (1) |
| | `origem_do_acesso` | `Mind` (29) ou o patrocinador nominal (Beiersdorf, Vale, Natura…) |
| `credenciamento_summit_2026.participantes` | `ticket_origin` | Pago (992) · Cortesia (27) · **Convidado institucional (8)** · **Staff (1)** |
| | `ticket_type` | Mind (360) · VIP (298) · **SEM MAPA (213)** · Prime (157) |
| | `sponsor_company` | preenchido em 13 participantes |

### Os três buracos, medidos

1. **Dois vocabulários pra mesma coisa.** O catálogo diz `Patrocínio`; o credenciamento diz
   `Convidado institucional` e `Staff`. Qual vale?
2. **1.904 vendas sem mapeamento.** Juntando `eduzz.vendas.id_do_produto` →
   `produto_catalogo.eduzz_product_id`, casam 1.078 Pago + 178 Cortesia + 47 Patrocínio, e
   **1.904 ficam de fora**. São SKUs antigos, ou mapeamento faltando?
3. **213 participantes com `SEM MAPA`.** Produto que ainda não entrou em
   `credenciamento_produtos_mapa` (na origem, 33 linhas — só `Pago`/`Cortesia`, sem `Patrocínio`,
   e `empresa_patrocinadora` 100% vazia).

### As perguntas que só você responde

1. Qual vocabulário é o oficial — o do catálogo ou o do credenciamento? (Sugestão minha: o do
   catálogo, porque classifica o **produto** e não a pessoa, então vale pra todo mundo que comprar
   aquele SKU. Mas é chute meu, não fato.)
2. `tipo_de_venda = Direta` (12 produtos): venda fora da Eduzz (PIX/boleto/contrato)? Onde ela é
   registrada hoje?
3. Patrocínio: o patrocinador ganha N ingressos por contrato? Quem nomeia as pessoas, e quando?
4. As 1.904 vendas sem mapeamento — dá pra ignorar (histórico velho) ou precisam ser mapeadas?

**Outras tabelas do projeto Vendas que ainda NÃO espelhei** (não foram pedidas; digo que existem
pra não redescobrir): `cortesia_requisicoes` · `receita_participantes` (~120) ·
`ingressos_gerados` (~1.071) · `espelho_lotes_map` (67) · `credenciamento_produtos_mapa` (33).
Essa última **já tem porta de leitura aberta** (fonte `cred_produtos_mapa`) — é só pedir que eu
espelho, é uma linha.

---

## Depois disso — a fila

| | passo | estado |
|---|---|---|
| 5 | `mind_crm_comercial()` — deals, compras, oportunidade | investigado, **não autorizado** |
| — | AGENT_CONTEXT (juntar CRM + Eduzz + conversa num contexto só) | não começado |
| — | ROUTER (escolher função/vertical/playbook) | não começado |
| — | Religar o Motor de Silêncio (depende de D1/D2/D3) | pausado |
| — | Write-back pro HubSpot · porte da empresa (Lusha) | passos 5 e 6 do plano antigo |

**Coisas quebradas que eu vi e não consertei** (estão no `BACKLOG.md`):
- `mind_lead_capturar` **não existe**, mas a edge chama a cada turno. Quem faz o trabalho é
  `crm.registrar_lead`. `crm.leads_capturados` está com 0 linhas.
- cron `mindagent-sync-precos` (job 1) **falha de 30 em 30 min**.
- 19 funções ainda apontando pra schemas antigos.
- 5 slots de prompt de análise vazios (`analise_classificador`, `analise_vendas_*`).
- `playbook_summit_b2b` não está chegando na composição b2b.

---

## Comandos que você pode precisar

```sql
-- forçar uma sincronização do espelho Eduzz agora
select net.http_post(
  url := 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/eduzz-espelho-sync?token='
         || (select valor from intelligence.config where chave='analise_token'),
  body := '{}'::jsonb,
  headers := '{"Content-Type":"application/json"}'::jsonb,
  timeout_milliseconds := 250000);

-- como estão os espelhos (9 fontes, 2 projetos de origem)
select fonte, projeto_origem, destino, status, registros_gravados, erro, concluido_em
  from public.espelho_estado order by projeto_origem, fonte;

-- só uma fonte
select net.http_post(
  url := 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/eduzz-espelho-sync?token='
         || (select valor from intelligence.config where chave='analise_token'),
  body := '{"fonte":"cred_participantes"}'::jsonb,
  headers := '{"Content-Type":"application/json"}'::jsonb,
  timeout_milliseconds := 250000);

-- o que uma pessoa comprou
select evento_titulo, nome_do_lote, status, pessoa_criterio
  from eduzz.v_ingressos where pessoa_id = '<uuid>';

-- essa pessoa está credenciada?
select name, ticket_type, ticket_origin, sponsor_company, status, pessoa_criterio
  from credenciamento_summit_2026.v_participantes where pessoa_id = '<uuid>';

-- de onde veio cada venda (pago / cortesia / patrocínio)
select coalesce(pc.tipo_de_acesso, 'SEM MAPEAMENTO') as acesso,
       pc.tipo_de_venda, pc.origem_do_acesso, count(*)
  from eduzz.vendas v
  left join eduzz.produto_catalogo pc on pc.eduzz_product_id = v.id_do_produto
 group by 1,2,3 order by 4 desc;

-- fila de identidade pra resolver
select * from mind_pendencias_listar(null, 'pendente', 20, 0);

-- religar o Motor de Silêncio (só depois de D1/D2/D3)
select cron.alter_job(13, active := true);
```
