# CHECKPOINT ATUAL — Mind Agent

> **Leia este arquivo primeiro ao retomar o projeto.**
>
> Atualizado em **04/09/2026** a partir de `main`, das Edge Functions e do banco
> de produção. Planos datados preservam contexto histórico; não representam o
> estado operacional atual.

## 1. Ponto exato de retomada

| item | estado verificado |
|---|---|
| repositório | `main` em `44d831018772b39a764dd311b9cc839a9e2d1c43` |
| `mindagent-chat` | Supabase v39, `ACTIVE`, `verify_jwt=true` |
| `treble-inbound-agent` | Supabase v38, `ACTIVE`, webhook com autenticação própria |
| `hubspot-commercial-writeback` | Supabase v3, `ACTIVE`, `verify_jwt=true` |
| última migration | `20260903185027_kit_compose_decisioning_into_instructions` |
| arquitetura compartilhada | integrada em `main` e produção |

O Vendedor B2C/B2B no WhatsApp e o Concierge/App usam o mesmo Core agêntico:
Router → Gate → Kit → decisioning → ferramentas → guardrails → pós-turno. Canal,
rota e playbook mudam; identidade, memória e contratos não são reimplementados.

## 2. O que está vivo

- Concierge contextual no App, com busca de Intelligence antes de abster e
  possibilidade de entrar em venda quando houver intenção explícita e oferta oficial.
- Vendedor Summit B2C/B2B no Treble/WhatsApp, com falha de runtime explícita em vez
  de silêncio e versão interna do Vendedor em `1.9.0`.
- coleta comercial progressiva na pessoa canônica antes de proposta/checkout;
- checkout atribuído, clique e abandono transacional registrados;
- pós-turno, ICP/JTBD, memória segura e inbox de recuperação;
- programação, acesso, fotos, palestrantes, livros/autógrafos e avisos da Home;
- write-back do HubSpot publicado em modo seguro, condicionado por flag e validação.

Snapshot operacional do banco em 04/09/2026:

| estrutura | linhas |
|---|---:|
| `intelligence.recovery_inbox` | 815 |
| `engagement.recovery_dispatch_queue` | 0 |
| `intelligence.participante_memoria` | 1.779 |
| `intelligence.analise_conversa` | 935 |
| `summit_2026.sessions` | 77 |
| `summit_2026.session_speakers` | 81 |
| `ecossistema.palestrantes_especialistas` | 64 |

Contagens são observacionais e mudam com o uso; não são contrato.

## 3. Gates que continuam fechados

- não ligar disparo automático de recuperação sem aprovação explícita, janela,
  opt-out, rate limit, idempotência e teste controlado;
- não habilitar `HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED` sem revisar preview,
  pipeline/stage e divergências de identidade no portal real;
- não publicar oferta de Institute, upgrade, pré-venda ou Camarote sem fonte oficial
  e regra comercial aprovada;
- não tratar busca vetorial como requisito de disponibilidade: o fallback lexical
  segue obrigatório enquanto a geração de embeddings não estiver operacionalmente fechada;
- deploy de Edge Function é manual neste repositório; merge de código não prova que
  o runtime vivo foi atualizado.

## 4. Próximo movimento seguro

1. Executar smoke controlado do Vendedor no WhatsApp e do Concierge no App.
2. Conferir eventos, tools, latência, versão e ausência de silêncio nos dois canais.
3. Revisar os 815 candidatos da recuperação por elegibilidade e duplicidade, sem disparar.
4. Revisar preview do HubSpot antes de qualquer `apply`.
5. Só então abrir um gate operacional por vez, com rollback documentado.

## 5. Fonte de verdade

Ordem de precedência: produção → `main`/PR atual → decisão recente registrada → este
checkpoint → `PROJECT_STATE.md` → especificações históricas.

- arquitetura e decisões: [`PROJECT_STATE.md`](PROJECT_STATE.md)
- mapa do runtime: [`MAPA_DO_SISTEMA.md`](MAPA_DO_SISTEMA.md)
- detalhes da entrega: [`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md)
- contratos do Core: [`docs/CORE_UNIVERSAL.md`](docs/CORE_UNIVERSAL.md)
- incidente do Concierge: [`INCIDENTE_CONCIERGE_20260903.md`](INCIDENTE_CONCIERGE_20260903.md)
- trabalho deferido: [`BACKLOG.md`](BACKLOG.md)
