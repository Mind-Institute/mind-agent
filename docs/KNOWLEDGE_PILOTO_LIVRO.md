# Piloto: primeiro livro em texto integral no Global Knowledge

**Data:** 30/09/2026 · **Livro:** Joseph Henrich, *The Secret of Our Success* (Princeton UP, 2016) · **Projeto Supabase:** `mind-agent`

**Estado:** parcial. Fonte canônica, arquivos, inventário, mapa de páginas e estrutura completa estão no banco. O texto canônico parou em 308.000 de 1.140.013 caracteres (Prefácio, capítulos 1–7 e início do 8), porque a camada de segurança da sessão do Claude Code bloqueou a continuação da carga (seção F). Chunks, embeddings e avaliação de retrieval **não** foram executados. A fonte está em `status_ingestao = 'processing'`, com a pendência registrada em `pendencia_decisao`.

---

## A. Livro escolhido e por quê

| critério | Henrich |
|---|---|
| relevância | nº 2 da pasta "0. GPT Mecanismo de Mudança MIND"; aprendizagem cultural, prestígio, normas, conformismo → `learning_science`, `organizational_culture`, `behavior_change`, `leadership` |
| qualidade do texto | PDF tipografado com camada de texto; os 448 números de página impressos batem com a posição calculada (0 divergências) |
| estrutura | Prefácio, 17 capítulos, 66 seções, 33 subseções, notas agrupadas por capítulo (17 grupos), referências, créditos e índice; tabelas, box, figuras e listas |
| integral + capítulos | PDF integral (464 págs.) + 17 arquivos de "capítulo" — que **não** batem com os capítulos (ver E) |
| representativo, não o mais fácil | livro de teoria que cita muita pesquisa (bom para "o autor afirma" × "a evidência mostra"); cópias duplicadas no Drive; arquivos de parte desalinhados |

Descartados: De Neve (arquivo licenciado só para a Adriana, com proibição expressa de uso em sistema de retrieval; já está como `derived_only`), *Languishing* (cópia OceanofPDF; a pasta de "capítulos" tem 175 partes, que não correspondem a capítulos), *Compassion Focused Therapy* (os arquivos separados são partes de um único capítulo, o 2).

**Direitos:** © 2016 Princeton UP, todos os direitos reservados; cópia de procedência não verificada (os arquivos de parte se chamam "pilot-project-ebook-available-to-selected-us-libraries-only"). Entrou como `modo_ingestao = full_text`, `direitos_uso = unknown`, `acesso = mind_only` por decisão da Adriana, que removeu a regra "licença restrita = derived_only".

## B. Mapa da ingestão

```text
fontes_conhecimento  6b61c548-70c9-4d23-ba5e-ec12a6bfa147  (book_popular · theory · full_text · mind_only)
 ├─ source_collections    learning_science★, organizational_culture, behavior_change, leadership
 ├─ knowledge_assets      1 (asset_type book) + asset_collections
 ├─ source_locations      18 = PDF mestre (is_primary) + 17 arquivos de parte
 │                          cada parte: master_pdf_pages, book_pages, covers (capítulos cobertos), sha256
 ├─ ingestion_inventory   22 = mestre + 17 partes (ingested → mesma fonte) + 4 cópias idênticas (excluded, sha256 igual)
 ├─ source_text_versions  v1  8170cfc1-93e2-4be4-81e4-93879ff86506
 │    text_content  PARCIAL: 308.000 / 1.140.013 caracteres
 │    page_map      456 páginas → [página do PDF, página do livro, offset onde a página começa no texto]
 │    metadata      regras de normalização, validações, defeitos conhecidos, parâmetros do chunking
 ├─ secoes_conhecimento   138 = Preface · 17 chapters · 66 sections · 33 subsections · Notes → 17 grupos (anotam o capítulo)
 │                          · References · Illustration Credits · Index
 │                          parent_section_id, ordem de leitura, pagina_inicio/fim (livro); mapa_estruturado: páginas do PDF,
 │                          char_range no texto canônico, arquivo de parte + páginas no arquivo
 └─ chunks_conhecimento   0 no banco (645 prontos): texto = recorte exato do texto canônico; capítulo/seção/subseção;
                           páginas do livro; metadata: section_id, chapter_section_id, char_start/end, pdf_pages, arquivo de parte
      → embeddings: fila existente (mind_knowledge_embedding_pending/save) — depende da migration proposta
      → retrieval: mind_knowledge_buscar_global — depende da migration proposta
      → quem enxerga: só agentes com access_max = mind_only nas collections da fonte (hoje: knowledge_admin)
```

**Nunca indexar o mesmo texto duas vezes:** só existe um texto canônico (o do PDF mestre). Os 17 arquivos de parte e as 4 cópias idênticas viram locais ou inventário, nunca texto ou chunk.

## C. O que já existia e foi reaproveitado

- **Tabelas, todas usadas como estavam:** `fontes_conhecimento`, `source_locations`, `source_text_versions` (texto, `page_map`, `structure_map`, `raw_text_allowed`), `secoes_conhecimento` (hierarquia por `parent_section_id`), `chunks_conhecimento` (capítulo/seção/subseção, páginas, `tsv`, `embedding vector(1536)`, `stale`), `knowledge_assets`, `ingestion_inventory`, `knowledge_collections` + `source_collections`/`asset_collections`.
- **Mecanismos:** indexador `mindagent-index-global-knowledge` com a fila `mind_knowledge_embedding_pending/save`; busca híbrida `mind_knowledge_buscar_global` (RRF lexical + vetor, autorização antes do ranking via `agentes.knowledge_access`); RAG Playground e botão "Gerar embeddings pendentes" no Admin; persona `knowledge_admin`.
- **Não foi preciso criar:** tabela, coluna, schema, Edge Function, vector store, índice, nem FK chunk→seção (a seção vai em `metadata.section_id`; ver G).

## D. Mudanças

1. **Repo:** removida a regra "licença restrita = `derived_only`" (decisão da Adriana).
2. **Dados em produção** (via conector autenticado; lotes conferidos por MD5): as linhas da seção B. Nenhuma estrutura alterada.
3. **Proposta, não aplicada:** `docs/sql/knowledge-livro/proposta_busca_global_com_chunks.sql`. Troca o corpo de três funções que já existem, sem criar nada:
   - `mind_knowledge_embedding_pending`: a fila passa a incluir chunks de fontes `full_text`. O texto enviado ao embedding leva um cabeçalho estrutural (obra — autor (ano) / capítulo › seção › subseção);
   - `mind_knowledge_embedding_save`: grava o vetor no insight ou no chunk;
   - `mind_knowledge_buscar_global`: candidatos passam a ser insights + chunks autorizados, no mesmo RRF. Chunk sai com `kind = chunk`, `insightType = source_text`, `baseNaFonte = author_text`, localizador "Henrich (2016), Chapter N: … › seção, pp. x–y" e `location` (páginas do livro e do PDF, arquivo de parte).
   A migration não foi aplicada porque, sem chunks no banco, não havia o que testar, e mudança de produção deve passar por revisão. A linha de base da busca atual foi registrada para conferir que os insights não regridem: 7 consultas com `knowledge_admin` (por exemplo, "segurança psicológica" = 12 resultados, "psychological safety" = 0); com dash, institute e summit_b2b, as mesmas consultas voltam vazias.
4. **Pipeline reaproveitável:** `scripts/infra/knowledge-livro/` (extração com fonte e posição, estrutura, chunks, validação, mapeamento dos arquivos de parte).

## E. Testes e resultados

**Estrutura e proveniência (executados):**

| verificação | resultado |
|---|---|
| números de página impressos × posição calculada | 448/448 (página do livro = PDF − 18) |
| títulos e páginas iniciais dos capítulos × Sumário | 17/17; Notas 333, Referências 373, Créditos 429 e Índice 431 também batem |
| arquivos de parte × mestre, página a página | 17/17 contíguos. part-1 = pré-textuais + prefácio; part-2 = caps. 1–2; part-9 = caps. 9–10; part-10…16 = caps. 11…17; part-17 = notas, referências e índice. **part-N ≠ capítulo N** |
| cópias do PDF integral | 4 idênticas ao mestre (sha256) |
| páginas declaradas de cada chunk | 642/645 com todo o texto dentro do intervalo; os 3 restantes atravessam uma página de tabela (limite do verificador, conferido à mão) |
| páginas renderizadas | p. 48 (título de duas linhas que tratei como uma seção só) e p. 124 (subseção e chamadas de nota) |
| chunks | 645 (563 de corpo + 82 de notas), a partir de 134 unidades estruturais; tamanho p10 800, p50 1.548, p90 1.992, máx. 2.598 caracteres; 0 caractere não coberto; nenhum chunk atravessa unidade; sobreposição de uma frase só nos 110 chunks que dividem parágrafo longo (16.991 caracteres, 1,5% do texto) |

**Retrieval (não executado):** o texto parou em 27% e os chunks não chegaram ao banco. Deixo abaixo o conjunto de avaliação preparado. A localização esperada vem da estrutura carregada (títulos e páginas em `secoes_conhecimento`); a passagem exata só se confere quando a avaliação rodar. Em cada resposta vale conferir: capítulo, seção e passagem corretos; contexto suficiente; duplicação; citação e proveniência; se dá para subir do chunk para seção ou capítulo; se "o autor afirma" é confundido com "a evidência mostra"; falsos positivos.

| # | tipo | pergunta | esperado |
|---|---|---|---|
| 1 | A localização | Em que capítulo Henrich conta a expedição de Burke e Wills? | cap. 3 › The Burke and Wills Expedition, pp. 27–30 |
| 2 | A | Onde o livro fala do "efeito Tasmânia"? | cap. 12 › The Tasmanian Effect, pp. 218–224 |
| 3 | A | Which chapter discusses menopause and killer whales? | cap. 8 › Prestige and the Wisdom of the Aged › Menopause, Culture, and Killer Whales, pp. 133–137 |
| 4 | A | Onde estão as notas do capítulo 7? | Notes › Chapter 7, pp. 344–346 |
| 5 | B conceito | O que é transmissão conformista? | cap. 4 › Why Care What Others Think? Conformist Transmission, pp. 48–49 |
| 6 | B | Qual a diferença entre prestígio e dominância? | cap. 8 › Key Elements of Prestige and Dominance, pp. 122–128 |
| 7 | B | What does Henrich mean by "collective brain"? | cap. 12 (Our Collective Brains), pp. 211–230 |
| 8 | B | O que é "overimitation"? | cap. 7 › "Overimitation" in the Laboratory, pp. 108–110 |
| 9 | C argumento | Por que, segundo Henrich, não é a inteligência o segredo do sucesso da espécie? | cap. 2, pp. 8–21 |
| 10 | C | Como a cultura explica nossos intestinos e dentes pequenos? | cap. 5 › Food Processing Externalizes Digestion, pp. 65–69 |
| 11 | C | Why do people in hot climates use more spices, according to the book? | cap. 7 › Overcoming Instinct: Why Chili Peppers Taste Good, pp. 110–113 |
| 12 | C | Por que a adivinhação com ossos de caribu ajudaria os caçadores Naskapi? | cap. 7 › Divination and Game Theory, pp. 104–107 |
| 13 | D síntese | Como aprendizagem cultural e seleção genética se reforçam? | cap. 5 (introdução, pp. 54–61) + cap. 6 › Culture-Gene Revolutions, pp. 92–94 + cap. 15 (When We Crossed the Rubicon, pp. 280–295) |
| 14 | D | Que pistas as pessoas usam para escolher de quem aprender? | cap. 4, pp. 38–48 (habilidade e sucesso, prestígio, semelhança, idade) |
| 15 | D | What does the book say about norms and self-domestication? | cap. 11 (Self-Domestication), pp. 185–210 |
| 16 | E evidência | Que estudo mostrou chimpanzés vencendo humanos no Matching Pennies? | cap. 2 › The True Machiavellians, pp. 17–21; resposta como "Henrich relata"; o estudo primário é `reference_lead` (notas do cap. 2) |
| 17 | E | Qual a evidência de que os tabus alimentares em Fiji reduzem a intoxicação por ciguatera? | cap. 7 › Taboos during Breast-Feeding and Pregnancy?, pp. 100–102 (estudo do próprio autor) |
| 18 | E | Que fontes Henrich cita para a hipótese da inteligência cultural? | Notes › Chapter 2, pp. 333–335 |
| 19 | E premissa falsa | Segundo Henrich, o sucesso humano vem de sermos individualmente mais inteligentes, certo? | o cap. 2 (It's Not Our Intelligence, pp. 8–21, com Showdown: Apes versus Humans, pp. 13–15) diz o contrário; a resposta deve corrigir a premissa |
| 20 | F multi-chunk | Explique passo a passo como os Tukano desintoxicam a mandioca e por que isso não é intuitivo | cap. 7, pp. 97–100 |
| 21 | F | Resuma o capítulo 3 (exploradores perdidos) | cap. 3, pp. 22–33 |
| 22 | F | Como o livro liga recipientes de água, rastreamento e corrida de resistência? | cap. 5 › How Water Containers and Tracking Made Us Endurance Runners, pp. 71–78 |
| 23 | falso positivo | Qual a prevalência de burnout em trabalhadores brasileiros? | Henrich não deve aparecer com confiança |
| 24 | falso positivo | Segurança psicológica em equipes | insights de Frazier acima de qualquer chunk de Henrich |
| 25 | falso positivo | Como a NR-1 trata riscos psicossociais? | Henrich ausente |

## F. Problemas encontrados

1. **Carga do texto interrompida.** Nesta máquina, o único caminho de escrita no banco é o conector do Supabase (`execute_sql`); não há CLI nem `psql` autenticados. Para carregar 1,14 milhão de caracteres, o próprio agente teria de transcrever o livro em lotes. A camada de segurança do Claude Code interrompeu a carga duas vezes. Primeiro recusou uma função temporária de carga, por reduzir a segurança do banco. Depois parou a transcrição em 308.000 caracteres, apontando a procedência da fonte ("Sensitive-Source Provenance"): a cópia vem marcada "available to selected US libraries only" e tem direitos desconhecidos. Com uma fonte assim, o pipeline não termina dentro de uma sessão de agente, e a decisão fica com a Adriana (seção H).
2. **Embeddings.** Só saem pelo botão do Admin (sessão de administrador). Um agente não consegue gerar embeddings de chunks nem das perguntas, então a avaliação automática ficaria só com a busca lexical.
3. **Busca lexical.** Configuração `simple` com `websearch_to_tsquery` exige todos os termos. Perguntas em linguagem natural e perguntas em português não encontram o texto em inglês, e os insights derivados existentes estão em português ("psychological safety" = 0 resultados; "segurança psicológica" = 12). Na prática, só a busca semântica atravessa idiomas.
4. **Arquivos de capítulo não são capítulos.** part-N ≠ capítulo N, e há arquivos que juntam dois capítulos. A estrutura precisa vir do mestre, nunca dos arquivos.
5. **Defeitos da camada de texto do PDF:** cerca de 13 palavras partidas por hífen perdido ("econ omist", "tech nologies"); "four-ear-olds" (p. 197); sobrescritos de unidade viraram chamada de nota ("cm[3]"); tabelas linearizadas; itálico perdido; alguns nomes próprios mantêm o hífen de fim de linha ("Arn-hem"). As coordenadas de caractere do PDFKit não servem neste arquivo, então os parágrafos foram detectados por heurística de comprimento de linha. Isso junta alguns parágrafos em blocos longos, e é por isso que 110 chunks dividem um bloco com uma frase de sobreposição.
6. **Procedência da biblioteca.** 22 livros da biblioteca têm marca de site pirata no nome do arquivo (por exemplo, OceanofPDF), e quase todos têm direitos desconhecidos. O Henrich também não tem procedência verificada, e foi isso que motivou a segunda interrupção. Sem uma política de procedência, os próximos livros vão parar no mesmo ponto.

## G. Aprendizados arquiteturais

**Manter:** 1 livro = 1 fonte; arquivos como locais e inventário; um texto canônico com `page_map` por offset; seções hierárquicas com páginas do livro; chunks dentro da unidade estrutural folha, carregando o contexto (capítulo › seção › subseção, páginas, arquivo); `mind_only` como padrão; autorização de chunk pelas collections da fonte.

**Melhorar agora** (para o próximo livro dar certo):
1. procedência antes de tudo: texto integral só de cópia com origem conhecida (comprada, cedida pela editora, de acesso aberto ou material próprio), registrada em `direitos_uso` e `provenance_notes`;
2. um caminho de carga em lote para texto integral, definido pela Adriana e pelo arquiteto. Hoje a única via é o agente transcrever o texto pelo conector, e isso não escala;
3. revisar e aplicar a migration proposta, para que os chunks entrem na fila de embeddings e na busca global;
4. rodar a avaliação da seção E num livro completo antes de escalar.

**Hipóteses para depois** (sem evidência de necessidade ainda): FK `chunks_conhecimento.section_id`, se o join por `metadata` pesar; collections por capítulo; índice HNSW quando o corpus crescer; busca lexical com OU ou por idioma; reranker; ligação de notas a `reference_lead`.

## H. Já temos um processo confiável para ingerir o próximo livro?

**Ainda não.** Extração, estrutura, proveniência e chunking estão prontos e validados, e o pipeline é reaproveitável, com a tipografia recalibrada por livro. Faltam:

1. uma política de procedência (que cópia pode entrar em texto integral) e um livro-piloto que a cumpra;
2. um caminho de escrita aprovado para texto integral;
3. a migration de embeddings e busca aplicada e testada;
4. uma rotina definida para gerar embeddings de chunks (hoje é manual, pelo Admin);
5. a avaliação de retrieval executada, para calibrar o tamanho de chunk e o peso entre insights e chunks.

**Caminho mais curto para validar de ponta a ponta:** repetir o piloto com um livro de acesso aberto (licença Creative Commons) ou com material próprio da Mind, usando o mesmo pipeline. Assim o retrieval é medido sem a questão de direitos. O Henrich fica pendente até existir uma cópia de procedência conhecida.

**Proposta para o `MIND_INTELLIGENCE_DIRECTION_AND_BACKLOG.md`** (não editado): registrar em EXPLORE "ingestão de texto integral no Global Knowledge: política de procedência + caminho de carga em lote", com este piloto como evidência. Ingestão de conhecimento não está no NOW atual (Commercial B2B); este piloto foi uma frente pedida à parte pela Adriana.
