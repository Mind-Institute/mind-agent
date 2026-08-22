# Migrations aplicadas sem arquivo no repositório — recuperadas

**Projeto Supabase:** `ymnmotgglsrxmjmonwjz` (mind-agent, sa-east-1)
**Data da recuperação:** 2026-08-22
**Branch:** `checkpoint/pre-mind-intelligence-architecture`

## O que é isto

Levantamento de `supabase_migrations.schema_migrations` no Supabase de produção
comparado com `supabase/migrations/` no repositório:

| | |
|---|---|
| Migrations aplicadas no Supabase | **99** |
| Arquivos em `supabase/migrations/` | 33 |
| Aplicadas **com** arquivo correspondente (mesma versão) | 28 |
| Aplicadas **sem** arquivo correspondente | **71** |
| Recuperadas aqui | **71** |
| Não recuperadas | **0** |
| Total de bytes preservados | **422.382** |

Também existem **4 arquivos no repositório sem registro aplicado** com a mesma
versão — `20260822052925_materiais_pendentes.sql`, `20260822052857_origens_do_site.sql`,
`20260822055230_produtos_e_calendario.sql`, `20260822044818_treble_momento_e_materiais.sql`.
O conteúdo deles foi aplicado sob outros nomes/versões e está preservado neste
diretório. Nada foi alterado nesses arquivos.

## Como o conteúdo foi obtido e conferido

Cada arquivo é **byte a byte** o conteúdo de
`supabase_migrations.schema_migrations.statements[1]` da respectiva versão.
Todas as 99 migrations aplicadas têm exatamente **um** elemento em `statements`,
então não houve junção nem separação de comandos.

O SQL **não foi normalizado, reformatado, corrigido nem combinado**. Migrations
que hoje referenciam objetos que já não existem (`agenda_sessoes`, `participantes`,
`taxonomia`, `mind.people`) foram preservadas exatamente como rodaram na época.

A conferência foi feita comparando o `sha256` calculado **pelo próprio Postgres**
sobre o statement:

```sql
select version,
       length(convert_to(array_to_string(statements, E'\n'), 'UTF8')) as bytes,
       encode(sha256(convert_to(array_to_string(statements, E'\n'), 'UTF8')), 'hex') as sha256
from supabase_migrations.schema_migrations;
```

com o `sha256sum` do arquivo gravado. **71 de 71 conferem. 0 divergências.**
(O heredoc do shell acrescenta um `\n` final quando o statement original não tem;
a conferência aceita o arquivo com ou sem esse último byte, e nada mais.)

## Estes arquivos NÃO são uma cadeia executável

Este diretório é **arquivo histórico**, não `supabase/migrations/`. Nenhum destes
arquivos deve ser aplicado: eles descrevem o estado do banco em agosto de 2026,
antes da reestruturação Mind Intelligence, e vários deles se contradizem entre si
(o mesmo objeto criado, renomeado e movido de schema em migrations diferentes).

Servem para responder "como o banco chegou até aqui" — e para que o histórico do
Supabase deixe de existir só em produção.

## Inventário

| # | Versão | Nome | Bytes | Status | Arquivo |
|---|---|---|---|---|---|
| 1 | `20260820045345` | 001_schema | 17108 | RECOVERED | `20260820045345_001_schema.sql` |
| 2 | `20260820045437` | 002_seed | 10568 | RECOVERED | `20260820045437_002_seed.sql` |
| 3 | `20260820045529` | 003_ciclo | 6844 | RECOVERED | `20260820045529_003_ciclo.sql` |
| 4 | `20260820045632` | 004_seed_ciclo | 12536 | RECOVERED | `20260820045632_004_seed_ciclo.sql` |
| 5 | `20260820045731` | 005_privacidade | 13051 | RECOVERED | `20260820045731_005_privacidade.sql` |
| 6 | `20260820045829` | 006_jornada | 13779 | RECOVERED | `20260820045829_006_jornada.sql` |
| 7 | `20260820045929` | 007_contexto_conteudo_dossie | 14409 | RECOVERED | `20260820045929_007_contexto_conteudo_dossie.sql` |
| 8 | `20260820045950` | 008_regras_do_evento | 3654 | RECOVERED | `20260820045950_008_regras_do_evento.sql` |
| 9 | `20260820050014` | 009_camada_llm | 5297 | RECOVERED | `20260820050014_009_camada_llm.sql` |
| 10 | `20260820050459` | 010_quem_agenda | 2315 | RECOVERED | `20260820050459_010_quem_agenda.sql` |
| 11 | `20260820050550` | 011_travas | 1517 | RECOVERED | `20260820050550_011_travas.sql` |
| 12 | `20260820053612` | 012_mind_intelligence | 13410 | RECOVERED | `20260820053612_012_mind_intelligence.sql` |
| 13 | `20260820054023` | 013_recuperacao | 5985 | RECOVERED | `20260820054023_013_recuperacao.sql` |
| 14 | `20260820054047` | 013b_derruba_sobrecarga_knowledge | 285 | RECOVERED | `20260820054047_013b_derruba_sobrecarga_knowledge.sql` |
| 15 | `20260820054604` | 014_so_sobre_mim | 10446 | RECOVERED | `20260820054604_014_so_sobre_mim.sql` |
| 16 | `20260820054646` | 014b_papel_utilizavel | 795 | RECOVERED | `20260820054646_014b_papel_utilizavel.sql` |
| 17 | `20260820141253` | 015_event_navigation_offers_agent_api | 13700 | RECOVERED | `20260820141253_015_event_navigation_offers_agent_api.sql` |
| 18 | `20260820152550` | 016_rollback_015_event_navigation_offers_agent_api | 948 | RECOVERED | `20260820152550_016_rollback_015_event_navigation_offers_agent_api.sql` |
| 19 | `20260820182353` | 017_treble_read_layer | 12737 | RECOVERED | `20260820182353_017_treble_read_layer.sql` |
| 20 | `20260820205324` | 018_mindagent_bootstrap_contract | 20068 | RECOVERED | `20260820205324_018_mindagent_bootstrap_contract.sql` |
| 21 | `20260820205629` | 019_grant_api_usage_for_read_contracts | 63 | RECOVERED | `20260820205629_019_grant_api_usage_for_read_contracts.sql` |
| 22 | `20260820210615` | improve_treble_location_natural_language | 3294 | RECOVERED | `20260820210615_improve_treble_location_natural_language.sql` |
| 23 | `20260820210645` | expose_treble_location_read_contract | 439 | RECOVERED | `20260820210645_expose_treble_location_read_contract.sql` |
| 24 | `20260820220647` | create_mind_admin_access_control | 4020 | RECOVERED | `20260820220647_create_mind_admin_access_control.sql` |
| 25 | `20260820220747` | refine_mind_admin_dashboard_counts | 2232 | RECOVERED | `20260820220747_refine_mind_admin_dashboard_counts.sql` |
| 26 | `20260820220826` | seed_official_event_map_locations | 13885 | RECOVERED | `20260820220826_seed_official_event_map_locations.sql` |
| 27 | `20260820220909` | expand_event_map_location_aliases | 910 | RECOVERED | `20260820220909_expand_event_map_location_aliases.sql` |
| 28 | `20260820233351` | admin_content_read_models | 10699 | RECOVERED | `20260820233351_admin_content_read_models.sql` |
| 29 | `20260820233600` | admin_content_write_operations | 15259 | RECOVERED | `20260820233600_admin_content_write_operations.sql` |
| 30 | `20260820234001` | admin_content_write_active_event | 15278 | RECOVERED | `20260820234001_admin_content_write_active_event.sql` |
| 31 | `20260821141059` | mindagent_chat_backend_v1 | 19156 | RECOVERED | `20260821141059_mindagent_chat_backend_v1.sql` |
| 32 | `20260821141457` | mindagent_chat_require_auth_v1 | 10458 | RECOVERED | `20260821141457_mindagent_chat_require_auth_v1.sql` |
| 33 | `20260821142420` | mindagent_chat_interest_evidence_index | 120 | RECOVERED | `20260821142420_mindagent_chat_interest_evidence_index.sql` |
| 34 | `20260821211140` | mindagent_bind_session_profile_by_email | 6182 | RECOVERED | `20260821211140_mindagent_bind_session_profile_by_email.sql` |
| 35 | `20260821213017` | persist_confirmed_chat_interests | 5124 | RECOVERED | `20260821213017_persist_confirmed_chat_interests.sql` |
| 36 | `20260821214334` | limit_and_curate_chat_interests | 6818 | RECOVERED | `20260821214334_limit_and_curate_chat_interests.sql` |
| 37 | `20260821221708` | add_treble_agent_backend | 15498 | RECOVERED | `20260821221708_add_treble_agent_backend.sql` |
| 38 | `20260821221946` | add_treble_agent_handoff | 842 | RECOVERED | `20260821221946_add_treble_agent_handoff.sql` |
| 39 | `20260822044546` | treble_expediente_comercial | 2103 | RECOVERED | `20260822044546_treble_expediente_comercial.sql` |
| 40 | `20260822044818` | treble_momento_em_vez_de_expediente | 1542 | RECOVERED | `20260822044818_treble_momento_em_vez_de_expediente.sql` |
| 41 | `20260822044901` | mind_materiais | 1897 | RECOVERED | `20260822044901_mind_materiais.sql` |
| 42 | `20260822045127` | mind_materiais_enriquecido | 3695 | RECOVERED | `20260822045127_mind_materiais_enriquecido.sql` |
| 43 | `20260822045439` | mind_origens_de_entrada | 3323 | RECOVERED | `20260822045439_mind_origens_de_entrada.sql` |
| 44 | `20260822052311` | virada_no_contexto | 6819 | RECOVERED | `20260822052311_virada_no_contexto.sql` |
| 45 | `20260822052437` | utm_na_conversa_e_no_checkout | 4652 | RECOVERED | `20260822052437_utm_na_conversa_e_no_checkout.sql` |
| 46 | `20260822052857` | origens_do_site_e_materiais_pendentes | 6075 | RECOVERED | `20260822052857_origens_do_site_e_materiais_pendentes.sql` |
| 47 | `20260822052925` | materiais_pendentes_de_preenchimento | 4296 | RECOVERED | `20260822052925_materiais_pendentes_de_preenchimento.sql` |
| 48 | `20260822052951` | utm_token_sem_pgcrypto | 1568 | RECOVERED | `20260822052951_utm_token_sem_pgcrypto.sql` |
| 49 | `20260822053042` | urlencode_nos_links | 3653 | RECOVERED | `20260822053042_urlencode_nos_links.sql` |
| 50 | `20260822055230` | produtos_como_primeira_classe | 4186 | RECOVERED | `20260822055230_produtos_como_primeira_classe.sql` |
| 51 | `20260822055312` | calendario_do_produto | 5889 | RECOVERED | `20260822055312_calendario_do_produto.sql` |
| 52 | `20260822055639` | knowledge_documents_event_scope | 853 | RECOVERED | `20260822055639_knowledge_documents_event_scope.sql` |
| 53 | `20260822055719` | chat_search_reads_common_knowledge | 8530 | RECOVERED | `20260822055719_chat_search_reads_common_knowledge.sql` |
| 54 | `20260822060130` | knowledge_documents_validity_window | 738 | RECOVERED | `20260822060130_knowledge_documents_validity_window.sql` |
| 55 | `20260822060226` | readers_respect_validity_window | 12269 | RECOVERED | `20260822060226_readers_respect_validity_window.sql` |
| 56 | `20260822061722` | knowledge_documents_clusters | 1020 | RECOVERED | `20260822061722_knowledge_documents_clusters.sql` |
| 57 | `20260822061813` | knowledge_cluster_clientes | 1187 | RECOVERED | `20260822061813_knowledge_cluster_clientes.sql` |
| 58 | `20260822175407` | crm_pessoas | 7131 | RECOVERED | `20260822175407_crm_pessoas.sql` |
| 59 | `20260822175435` | crm_buscar_pessoa | 4434 | RECOVERED | `20260822175435_crm_buscar_pessoa.sql` |
| 60 | `20260822175522` | crm_acessos_auditoria | 2803 | RECOVERED | `20260822175522_crm_acessos_auditoria.sql` |
| 61 | `20260822180119` | crm_pessoa_produtos_usa_catalogo | 3875 | RECOVERED | `20260822180119_crm_pessoa_produtos_usa_catalogo.sql` |
| 62 | `20260822180356` | catalogo_produtos_faltantes | 1244 | RECOVERED | `20260822180356_catalogo_produtos_faltantes.sql` |
| 63 | `20260822180427` | journey_pertence_ao_institute | 431 | RECOVERED | `20260822180427_journey_pertence_ao_institute.sql` |
| 64 | `20260822180924` | catalogo_institute_formacoes | 2405 | RECOVERED | `20260822180924_catalogo_institute_formacoes.sql` |
| 65 | `20260822181052` | institute_2025_como_edicao_historica | 2512 | RECOVERED | `20260822181052_institute_2025_como_edicao_historica.sql` |
| 66 | `20260822181149` | linha_eventos_e_oxford_no_conselho | 722 | RECOVERED | `20260822181149_linha_eventos_e_oxford_no_conselho.sql` |
| 67 | `20260822181302` | crm_sync_estado | 1298 | RECOVERED | `20260822181302_crm_sync_estado.sql` |
| 68 | `20260822181433` | crm_mapa_produtos | 1712 | RECOVERED | `20260822181433_crm_mapa_produtos.sql` |
| 69 | `20260822181515` | catalogo_na_raiz | 3244 | RECOVERED | `20260822181515_catalogo_na_raiz.sql` |
| 70 | `20260822182017` | crm_pessoas_interno | 4039 | RECOVERED | `20260822182017_crm_pessoas_interno.sql` |
| 71 | `20260822182034` | crm_contexto_comercial | 2508 | RECOVERED | `20260822182034_crm_contexto_comercial.sql` |

## Não recuperadas

Nenhuma. Todas as 71 migrations aplicadas sem arquivo correspondente tiveram o
statement recuperado e conferido por hash.

## O que continua fora do Git

O histórico de migrations está completo, mas estes itens ainda vivem só no Supabase:

- **`database-schema.sql`** — o dump do schema atual. Bloqueado: o sandbox não
  alcança `supabase.co` (`curl: (56) CONNECT tunnel failed, response 403`), e
  `supabase db dump` precisa de conexão direta ao banco. Ver
  `archive/pre-architecture/README.md` para o comando de desbloqueio.
- **Configuração curada fora de migration** — `treble.prompts`, `treble.config`,
  `summit.commercial_rules`, `summit.offers`, `engagement.origens`,
  `crm.mapa_produtos`. São conteúdo, não estrutura, e foram inseridos por
  operação manual.
- **Bucket `mind-assets`** — as fotos dos palestrantes.
- **Secrets das Edge Functions** — não são legíveis por nenhuma API.
