# ADR 0001 — `ecossistema.palestrantes_especialistas` como identidade canônica do palestrante

- **Status:** Aceito
- **Data:** 2026-08-29
- **Decisora:** Adriana (joinmind)
- **Relacionados:** `docs/02_TARGET_DATA_MODEL.md`, `docs/09_SOURCE_OF_TRUTH_DRAFT.md`,
  `docs/15_CURRENT_TO_TARGET_MAP.md` (D5), plano `summit_2026` (base de conhecimento do Summit).

## Contexto

O modelo alvo congelado (`docs/02`) define a **identidade canônica de pessoa** em
`people.people`, com o palestrante representado como um **papel** (`summit.session_people`)
sobre uma pessoa canônica, e o perfil/obras em `people.profiles`/`works`/`affiliations`.
`docs/15` (D5) classifica `comum.speakers` como `SPLIT/MOVE → people.people + profiles`.

A realidade do banco divergiu desse alvo:

- `comum.speakers` (a antiga tabela de palestrantes) **foi extinta**.
- `pessoas.pessoas` existe (~2.900 linhas), sincronizada do HubSpot — é a identidade
  **operacional de participantes/leads/contatos**, não um registro curado de palestrantes.
- Foi criada `ecossistema.palestrantes_especialistas` (PK **bigint**, 31 dossiês) — um
  **registro curado e rico** de cada palestrante/especialista do ecossistema Mind, escrito à
  mão: `quem_e`, `formacao_e_posicao`, `principais_contribuicoes`, `conceitos_chave_explicados`,
  `por_que_o_conteudo_e_importante`, `dores_e_problemas_que_ajuda_a_compreender`,
  `relevancia_para_os_icps_do_mind`, `principais_livros`, `principais_papers`,
  `limites_e_cuidados_cientificos`, `fontes_gerais`, além de `nome`/`cargo_curto`/
  `instituicao`/`slug`/`aliases`.
- `summit_2026.session_speakers` liga sessão↔palestrante por **dois** caminhos: `speaker_id`
  (bigint → `ecossistema.palestrantes_especialistas`, populado em **9 de 61** linhas) e
  `palestrante_id` (uuid, **NOT NULL, sem FK** — apontava para `comum.speakers`, hoje
  pendurado).

`ecossistema` e `palestrantes_especialistas` **não estão em nenhum documento de arquitetura**;
são uma divergência não documentada. `docs/09` exige um ADR/plano de migração para qualquer
mudança de autoridade. Este ADR registra essa decisão.

## Decisão

**`ecossistema.palestrantes_especialistas` é a identidade canônica do palestrante/especialista
do Summit** (e, por extensão, do ecossistema Mind), carregando identidade **e** dossiê.

- `summit_2026.session_speakers` liga a sessão ao palestrante **exclusivamente** por
  `speaker_id` (bigint → `ecossistema.palestrantes_especialistas.id`).
- Após o backfill das 61 linhas, `speaker_id` torna-se `NOT NULL` e o `palestrante_id`
  pendurado é **removido**.
- O palestrante é uma **população distinta** de `pessoas.pessoas`:
  - `ecossistema.palestrantes_especialistas` = figuras públicas curadas (palestrantes/
    especialistas), autoradas no banco, com dossiê rico que alimenta o concierge e a
    inteligência comercial;
  - `pessoas.pessoas` = participantes/leads/contatos (identidade operacional, sync HubSpot).
- **Fonte da verdade dividida:** a *grade/grafia* do palestrante vem do git do site
  (`Mind-Institute/mindsummit2026`, `src/data/speakers.json`); o *dossiê* é autorado no banco.
  Um palestrante adicionado no site é **criado automaticamente** no `ecossistema` (stub de
  identidade) e sinalizado para o dossiê ser escrito; o sync **nunca sobrescreve** dossiê já
  existente.

Isto é uma **divergência deliberada** do `people.people` congelado, restrita à população de
palestrantes/especialistas.

## Consequências

**Positivas**
- Uma fonte única e rica de conteúdo de palestrante, pronta para concierge + comercial.
- Conserta o vínculo sessão↔palestrante hoje quebrado (`palestrante_id` órfão).
- Preserva o investimento de curadoria já feito nos 31 dossiês.

**Negativas / dívidas assumidas**
- Passa a existir **duas populações de pessoa** (palestrante em `ecossistema`, participante em
  `pessoas.pessoas`), contra o invariante "pessoa canônica existe uma vez". Fica em aberto a
  **regra de ponte** para quando um palestrante também for participante/lead.
- `ecossistema.palestrantes_especialistas` **mistura identidade e dossiê**; um split futuro
  (identidade × perfil/obras × conhecimento científico) pode ser necessário e exigirá novo ADR.
- Parte do dossiê é conhecimento científico (`conceitos_chave`, `principais_papers`,
  `limites_e_cuidados_cientificos`) que idealmente referencia a camada `knowledge`; por ora
  fica no dossiê, com provenance.

## Alternativas consideradas

1. **Seguir o alvo congelado** (`people.people` + `profiles`/`works`, palestrante como papel).
   Rejeitada agora: descartaria a curadoria já feita e adicionaria mais peças móveis sem
   necessidade para o escopo atual (base de conhecimento do Summit 2026).
2. **Manter os dois caminhos de link** (`palestrante_id` uuid + `speaker_id` bigint).
   Rejeitada: `palestrante_id` está pendurado (sem FK, tabela-alvo extinta) e mantém o vínculo
   quebrado.

## Reversibilidade

Decisão de identidade é de alto impacto. A reversão (para `people.people`) exigiria novo ADR,
migração coordenada de FKs e preservação do conteúdo do dossiê. O backfill de `speaker_id` e a
remoção de `palestrante_id` devem vir em migração versionada com rollback e verificação de que
100% das linhas resolvem em `ecossistema` antes do `DROP`.
