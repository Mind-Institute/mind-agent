# A passada D5 — scripts para a Adriana rodar no SQL Editor

Regra #1 em `READ_ME_FIRST.md`. Migration: `supabase/migrations/20260923013000_d5_identidade_universal.sql`
(aplicar antes de qualquer script a partir do `00`; o `05` roda antes dela).

Cada script imprime o que fez. Os que **simulam** fazem o trabalho inteiro e desfazem no fim: o
resumo aparece como **mensagem de erro que começa com `SIMULACAO — nada gravado`**. Isso é o
esperado, não uma falha.

| # | arquivo | fase | o que faz |
|---|---|---|---|
| 05 | `05_previa_sem_migration.sql` | — | só leitura, roda **antes** da migration: quanto a fase A acrescentaria e quantas duplicatas revelaria, por padrão |
| 00 | `00_antes.sql` | — | fotografia dos números antes da passada (guarde o resultado) |
| 10 | `10_enriquecer_simular.sql` | A | simula o enriquecimento de todas as pessoas; nada gravado |
| 11 | `11_enriquecer_aplicar.sql` | A | enriquece em lotes de 1.500; **repita até `restantes_nesta_rodada = 0`** |
| 30 | `30_propostas.sql` | B | a fila de duplicatas por padrão e confiança, e o detalhe de um padrão |
| 40 | `40_decidir.sql` | B | modelos de decisão: aprovar um padrão (só confiança alta entra), aprovar ou rejeitar uma linha |
| 50 | `50_criar_simular.sql` | C | simula a criação por fonte, uma fonte por vez, na ordem HubSpot → Eduzz → Blinket → Treble → credenciamento → Yazo |
| 51 | `51_criar_aplicar.sql` | C | cria/liga por fonte, em lotes; **repita cada fonte até `restantes_nesta_fonte = 0`** |
| 90 | `90_depois.sql` | — | fotografia final e verificações |

Ordem: `05` (hoje) → migration → `00` → `10` → `11` (até zerar) → `30` → `40` → `11` de novo se
houve fusão (a fusão libera identificadores) → `50` → `51` fonte a fonte → `90`.

O que **nunca** acontece sem você: fundir duas pessoas. `mind_fusao_decidir` é o único caminho,
e aprovar um padrão inteiro só alcança as propostas de confiança alta.
