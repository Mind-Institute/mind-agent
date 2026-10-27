# Livro → Global Knowledge (pipeline do piloto)

Pipeline usado no piloto do Henrich (30/09/2026). Não contém texto de nenhum livro; o texto é extraído localmente do PDF.
Relatório do piloto: `docs/KNOWLEDGE_PILOTO_LIVRO.md`.

| passo | script | saída |
|---|---|---|
| 1. extrair páginas com fonte e posição | `swiftc -O pagedump2.swift -o pagedump2 && ./pagedump2 livro.pdf master2.jsonl` | uma linha JSON por página, com runs de tamanho de fonte |
| 2. conferir o sumário embutido | `swiftc -O outline.swift -o outline && ./outline livro.pdf` | capítulos e páginas do PDF |
| 3. mapear arquivos de capítulo | `./pagedump2 part-N.pdf parts/part-N.jsonl` e `node map-parts.cjs master2.jsonl parts/` | intervalo de páginas do mestre coberto por cada arquivo |
| 4. texto canônico + estrutura | `node build.cjs master2.jsonl outline.json out/` | `canon.txt`, `canon.json` (blocos, páginas exatas, capítulos/seções/subseções, notas) |
| 5. chunks por unidade estrutural | `node chunk.cjs out/canon.json files.json out/` | `sections.json`, `chunks.json`, `chunk-report.json` |
| 6. validar páginas de todos os chunks | `node validate-pages.cjs` | `out/page-validation.json` |
| 7. conferir páginas renderizadas | `swiftc -O render.swift -o render && ./render livro.pdf img/ 66 142` | PNG das páginas para inspeção visual |

`outline.json` é específico do livro (páginas de início do prefácio, dos capítulos e da parte pós-textual, e o deslocamento página do livro = página do PDF − N).
As regras de tipografia em `build.cjs` (13pt capítulo, 18pt título, 11pt seção, 10pt subseção, 10,5pt corpo, 8pt legenda) foram medidas neste livro e precisam ser medidas de novo em outro.

A carga no Supabase ficou incompleta no piloto; ver a seção F do relatório.
