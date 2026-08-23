# Checkpoint pré-arquitetura Mind Intelligence

Ponto de recuperação tirado **antes** de qualquer trabalho arquitetural novo.
Nada foi alterado no Supabase, nenhuma migration foi criada, nenhuma Edge
Function foi publicada. Este diretório é só leitura do que existia.

| | |
|---|---|
| **Data do checkpoint** | 2026-08-22 |
| **Project ref (Supabase)** | `ymnmotgglsrxmjmonwjz` |
| **Branch de origem** | `claude/mind-chatbot-treble-6bbu4a` |
| **Commit de origem** | `316ad6da25e072e8f1f1ea9d9aec4acb11232472` |
| **Branch do checkpoint** | `checkpoint/pre-mind-intelligence-architecture` |

---

## Edge Functions publicadas

Oito ativas no projeto. **Três** já estavam versionadas em `supabase/functions/`;
**cinco** existiam somente em produção e foram recuperadas para cá.

| Função | Versão publicada | verify_jwt | Já estava no repo? | Origem deste arquivo |
|---|---|---|---|---|
| `treble-inbound-agent` | 12 | não | **sim** | `supabase/functions/treble-inbound-agent/` |
| `treble-api` | 1 | não | **sim** | `supabase/functions/treble-api/` |
| `mindagent-sync-precos` | 1 | não | **sim** | `supabase/functions/mindagent-sync-precos/` |
| `mindagent-chat` | 18 | **sim** | não | recuperada da produção |
| `treble-find-location` | 14 | não | não | recuperada da produção |
| `mindagent-admin` | 12 | não | não | recuperada da produção |
| `mindagent-bootstrap` | 12 | não | não | recuperada da produção |
| `treble-agent` | 4 | não | não | recuperada da produção |

### Como foram recuperadas

Pela Management API do Supabase (`get_edge_function`), que devolve o conteúdo
exato do arquivo publicado. O conteúdo **não foi editado**: nem formatação, nem
nomes, nem comentários.

Duas observações de fidelidade, verificadas caractere a caractere:

- `mindagent-chat` e `mindagent-admin` usam a sequência de escape literal
  `̀-ͯ` no `normalize("NFD")`.
- `treble-agent` usa os caracteres combinantes reais no mesmo trecho.

São grafias diferentes para o mesmo comportamento, e cada arquivo foi preservado
como está publicado.

### Nota sobre `treble-agent`

É o **predecessor** do `treble-inbound-agent`. Continua publicada e ativa, mas
parou de ser atualizada (v4, última alteração antes da v12 do sucessor). Difere
em pontos importantes: autentica por header `X-Treble-Token`/`Bearer` em vez de
`?token=`, responde 202 e processa em `EdgeRuntime.waitUntil`, chama
`mindagent_treble_start` (que **vincula a pessoa**, coisa que o sucessor não faz)
e escreve de volta no Treble por `POST /session/{id}/update`. Preservada aqui
justamente porque tem lógica que o sucessor perdeu.

### Nota sobre chave em código

`mindagent-bootstrap` traz uma `PROJECT_PUBLISHABLE_KEY` embutida no fonte. É
chave publicável (a mesma que o navegador usa, pública por construção), não é
segredo — mas está registrada aqui como achado, não como recomendação.

---

## Migrations

| | |
|---|---|
| Aplicadas no banco (`supabase_migrations.schema_migrations`) | **99** |
| Arquivos em `supabase/migrations/` | **33** |
| Batem por nome | **28** |
| **Aplicadas sem arquivo correspondente no repo** | **71** |
| Arquivos no repo sem registro de aplicação | 4 |

Os 4 sem registro (`materiais_pendentes`, `origens_do_site`,
`produtos_e_calendario`, `treble_momento_e_materiais`) foram aplicados sob outro
nome — o conteúdo está no banco, o nome do arquivo é que diverge.

As **71 sem arquivo** são o maior risco de recuperação deste checkpoint. O SQL
delas existe apenas dentro de `supabase_migrations.schema_migrations.statements`
(≈494 kB no total). Não foram trazidas para cá — ver "Limitações" abaixo.

### Ledger completo do que está aplicado

Ordem de aplicação, do mais antigo ao mais novo:

```
001_schema · 002_seed · 003_ciclo · 004_seed_ciclo · 005_privacidade · 006_jornada
007_contexto_conteudo_dossie · 008_regras_do_evento · 009_camada_llm
010_quem_agenda · 011_travas · 012_mind_intelligence · 013_recuperacao
013b_derruba_sobrecarga_knowledge · 014_so_sobre_mim · 014b_papel_utilizavel
015_event_navigation_offers_agent_api
016_rollback_015_event_navigation_offers_agent_api · 017_treble_read_layer
018_mindagent_bootstrap_contract · 019_grant_api_usage_for_read_contracts
improve_treble_location_natural_language · expose_treble_location_read_contract
create_mind_admin_access_control · refine_mind_admin_dashboard_counts
seed_official_event_map_locations · expand_event_map_location_aliases
admin_content_read_models · admin_content_write_operations
admin_content_write_active_event · mindagent_chat_backend_v1
mindagent_chat_require_auth_v1 · mindagent_chat_interest_evidence_index
treble_inbound_mvp · mindagent_bind_session_profile_by_email
persist_confirmed_chat_interests · limit_and_curate_chat_interests
add_treble_agent_backend · add_treble_agent_handoff · sync_precos_lotes
treble_agent_v01 · treble_agent_config_modelo · treble_agent_contexto_visao_geral
treble_conversations_telefone · treble_agent_contexto_experiencias
treble_curadoria_conteudo · treble_agent_dedup · treble_prompts_modulares
treble_expediente_comercial · treble_momento_em_vez_de_expediente
mind_materiais · mind_materiais_enriquecido · mind_origens_de_entrada
origens_e_utm · playbooks_conversas_reais · b2b_municiar_em_vez_de_transferir
precos_por_volume_no_contexto · virada_de_lote_e_procura · virada_no_contexto
utm_sessoes_e_checkout · utm_na_conversa_e_no_checkout
origens_do_site_e_materiais_pendentes · materiais_pendentes_de_preenchimento
utm_token_sem_pgcrypto · urlencode_nos_links · palestrantes_da_planilha
programacao_da_planilha · produtos_como_primeira_classe · calendario_do_produto
knowledge_documents_event_scope · chat_search_reads_common_knowledge
bucket_de_assets · knowledge_documents_validity_window
readers_respect_validity_window · knowledge_documents_clusters
knowledge_cluster_clientes · remove_duplicatas_event_rules
crm_pessoas · crm_buscar_pessoa · crm_acessos_auditoria
empresa_e_produtos_irmaos · crm_pessoa_produtos_usa_catalogo
catalogo_produtos_faltantes · journey_pertence_ao_institute
catalogo_institute_formacoes · institute_2025_como_edicao_historica
linha_eventos_e_oxford_no_conselho · crm_sync_estado · crm_mapa_produtos
catalogo_na_raiz · crm_pessoas_interno · crm_contexto_comercial
crm_recebe_consents
faxina_01_cria_schemas · faxina_02_pessoa_unica · faxina_03_promove_concierge
faxina_04_comum_e_summit · faxina_05_conhecimento_por_linha
faxina_06_derruba_andaime
```

---

## Limitações deste checkpoint

**`database-schema.sql` NÃO foi gerado.** O caminho suportado
(`supabase db dump`, CLI 2.115.0) exige `--linked` ou `--db-url`, e ambos
precisam de rede até o Postgres do projeto. Deste ambiente o proxy recusa a
conexão:

```
curl: (56) CONNECT tunnel failed, response 403
  api.supabase.com                        → bloqueado
  ymnmotgglsrxmjmonwjz.supabase.co        → bloqueado
```

Não há token de management no ambiente, e `supabase login` também depende da
mesma rede.

O caminho alternativo — extrair o DDL por introspecção (`pg_get_functiondef`,
`pg_get_viewdef`, `pg_get_constraintdef`, `pg_indexes`, `pg_policies`) via a
ferramenta de SQL — foi **descartado de propósito**. O volume medido é de
~127 kB só de corpos de função e ~18 kB de views, antes de tabelas, índices,
constraints, triggers e policies. Todo esse texto teria que ser retranscrito à
mão para chegar ao disco, e um erro silencioso de transcrição corromperia
exatamente o artefato que deveria ser a rede de segurança. Um dump que parece
fiel e não é vale menos que dump nenhum.

### Como desbloquear

Qualquer um dos dois resolve, de uma máquina com rede até o Supabase:

```bash
# opção 1 — projeto vinculado
supabase link --project-ref ymnmotgglsrxmjmonwjz
supabase db dump --linked -f archive/pre-architecture/database-schema.sql

# opção 2 — string de conexão direta
supabase db dump \
  --db-url "postgresql://postgres:SENHA@db.ymnmotgglsrxmjmonwjz.supabase.co:5432/postgres" \
  -f archive/pre-architecture/database-schema.sql
```

Vale rodar também `--data-only` para as tabelas de configuração que não são
dado pessoal (`treble.config`, `treble.prompts`, `summit.commercial_rules`,
`summit.offers`, `engagement.origens`, `crm.mapa_produtos`), porque é conteúdo
curado que não está em migration nenhuma.

---

## Inventário do banco no momento do checkpoint

16 schemas. Contagem de tabelas (T) e views (V):

```
catalogo      2T        mind          2T   3V     concierge   16T  7V
comum         7T        summit       17T   2V     treble       6T
crm           9T        institute     2T   2V     platform     5T
engagement   20T  1V    dash          2T   2V     public       4T
intelligence 10T        eventos       2T   2V     quarentena   1T
api           (só funções: 15)
```

64 funções em `sql`/`plpgsql` nos schemas do projeto. 22 views no total.
Um cron job ativo: `mindagent-sync-precos`, a cada 30 minutos.
