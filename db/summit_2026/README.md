# `summit_2026` — base de conhecimento do Mind Summit 2026

Fonte **declarativa** do schema da base de conhecimento que alimenta o concierge e a
inteligência comercial do Summit 2026. É o estado-alvo das tabelas — **ainda NÃO aplicado
em produção** (sem migração/`apply_migration` até as pré-condições do plano).

- `schema.sql` — definição declarativa de todas as tabelas, com o papel de cada uma.

## Princípios (ver plano aprovado)

- **Insumo, não comando.** As tabelas entregam fatos e recursos ao agente; o comportamento
  (o que dizer/quando) é do playbook.
- **Uma casa por conceito, nomes PT consistentes** — o agente sabe onde buscar cada info.
- **`[SYNC]`** = espelhado do git do site (`mindsummit2026/src/data/*.json`); o sync nunca
  sobrescreve campos **`[AUTORADO]`** (dossiê, `sessao_expectativa`, `posicionamento`…).
- **Preço, % vendido, datas, lote vigente = LIVE** em `mind-summit-propostas`
  (`rwqdperfphubzteckyqd`), sempre no fuso `America/Sao_Paulo` — nunca hardcoded aqui.
- **Palestrante canônico** = `ecossistema.palestrantes_especialistas` (ver `docs/adr/0001`).

## Mapa rápido (onde cada info vive)

evento · locais · sessoes · sessao_expectativa · sessao_palestrantes · experiencias ·
ingressos · ingresso_inclusoes · patrocinadores · posicionamento · recursos · faq ·
atendimento · transcricoes.
