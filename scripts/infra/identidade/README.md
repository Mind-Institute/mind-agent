# A passada D5 — scripts da passada de identidade

Regra #1 em `READ_ME_FIRST.md`. Migrations, na ordem em que estão no ledger de produção:

| ledger | arquivo | o que é |
|---|---|---|
| `20260923024555` | `d5_identidade_universal.sql` | a porta única em toda fonte, fases A/B/C, fusão só por decisão, `v_pessoa_360` |
| `20260923033919` | `d5_2_email_nome_vencem.sql` | a regra da Adriana: e-mail + nome vencem, telefone/CPF de linha comprada por terceiro ficam de fora, bater com `pessoas.pessoas` antes de criar |
| `20260923040915` | `d5_3_enriquecer_indexado.sql` | índices de expressão sem predicado parcial; fase A por índice (12 s → 50 ms por pessoa) |
| `20260923043442` | `d5_4_proposta_guarda_a_evidencia_mais_forte.sql` | a proposta de fusão classifica pela evidência mais forte que o par compartilha |
| `20260923050355` | `d5_5_tabelas_da_adriana_na_regra.sql` | Reservas_Agenda_APP e Check Ins Summit sob a Regra #1 |
| `20260923071424` | `d6_mind_id.sql` | **D6**: a coluna do ID universal chama-se `mind_id` em 53 tabelas (companheiras `mind_id_criterio`/`mind_id_resolvido_em`); 63 funções recriadas só com o rename; `v_pessoa_360` expõe `mind_id`. Aplicada via `execute_sql` (texto carregado em large object e executado numa transação), ledger carimbado à mão |

**A passada foi executada em produção pelo Claude em 23/09/2026 (madrugada), a pedido da Adriana**
("nada deve ficar comigo, execute"). Os scripts ficam como registro e como modelo para rodadas
futuras (uma fonte nova, uma rodada nova da fase A depois de fusões). O `20_desfazer_janela_2309.sql`
é o registro de como o intervalo 02:50 UTC (colagem pela regra antiga) foi desfeito.

Cada script imprime o que fez. Os que **simulam** fazem o trabalho inteiro e desfazem no fim: o
resumo aparece como **mensagem de erro que começa com `SIMULACAO — nada gravado`**. Isso é o
esperado, não uma falha.

| # | arquivo | fase | o que faz |
|---|---|---|---|
| 05 | `05_previa_sem_migration.sql` | — | só leitura, roda **antes** da migration: quanto a fase A acrescentaria e quantas duplicatas revelaria, por padrão |
| 00 | `00_antes.sql` | — | fotografia dos números antes da passada (guarde o resultado) |
| 10 | `10_enriquecer_simular.sql` | A | simula o enriquecimento de todas as pessoas; nada gravado |
| 11 | `11_enriquecer_aplicar.sql` | A | enriquece em lotes de até 1.000 (cada pessoa segura seus advisory locks até o fim da transação; 2.500 estourou a tabela de locks em 23/09); **repita até `restantes_nesta_rodada = 0`**. Não rodar durante o sync da Eduzz (:20 e :50): as duas transações disputam os mesmos locks |
| 20 | `20_desfazer_janela_2309.sql` | — | registro de como o intervalo 02:50 UTC de 23/09 foi desfeito (13.205 identificadores colados pela regra antiga); modelo para um caso parecido |
| 30 | `30_propostas.sql` | B | a fila de duplicatas por padrão e confiança, e o detalhe de um padrão |
| 40 | `40_decidir.sql` | B | modelos de decisão: aprovar um padrão (só confiança alta entra), aprovar ou rejeitar uma linha |
| 50 | `50_criar_simular.sql` | C | simula a criação por fonte, uma fonte por vez, na ordem HubSpot → Eduzz → Blinket → Treble → credenciamento → Yazo |
| 51 | `51_criar_aplicar.sql` | C | cria/liga por fonte, em lotes; **repita cada fonte até `restantes_nesta_fonte = 0`** |
| 60 | `60_varredura_mind_id.sql` | D6 | varredura das 164 tabelas (23/09): as 5 tabelas com cliente que faltavam entram na Regra #1 e foram preenchidas sem criar pessoa (resultado no próprio arquivo); o que ficou de fora e por quê |
| 90 | `90_depois.sql` | — | fotografia final e verificações |

Ordem: `05` (hoje) → migration → `00` → `10` → `11` (até zerar) → `30` → `40` → `11` de novo se
houve fusão (a fusão libera identificadores) → `50` → `51` fonte a fonte → `90`.

O que **nunca** acontece sem você: fundir duas pessoas. `mind_fusao_decidir` é o único caminho,
e aprovar um padrão inteiro só alcança as propostas de confiança alta.
