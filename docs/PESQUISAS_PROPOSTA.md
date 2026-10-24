# Pesquisas 2024, 2025 e pré-2025 — proposta de onde guardar (passo 9)

Status: **proposta para aprovação da Adriana. Nada foi gravado no banco.**

## O que são os 4 arquivos

| Arquivo | O que é | Respostas | Identifica a pessoa |
|---|---|---|---|
| "Construa o Mind Summit conosco" (Google Forms) | Avaliação do **Mind Summit 2024** (expectativa, organização, conteúdo, palestras 0–5) | 64 | e-mail |
| "Sua voz importa — Mind Summit 2025" (Google Forms) | Avaliação do **Mind Summit 2025**: NPS 0–10, 6 notas de aspecto 1–5, 11 palestras/painéis 1–5, textos abertos, interesse em cursos, aceite de contato | 373 (out/2025–fev/2026) | e-mail (todas) |
| "MindSummit2025_October…" (Qualtrics) | **Pesquisa de interesse pré-Summit 2025** para lançamento de produto: função, empresa, demanda B2B/B2C, trilhas, formato, critérios de compra, prioridades, dor | 212 (ago–out/2025), 187 completas | não (anônima), exceto os 149 abaixo |
| "Respostas_Individuais" (Qualtrics) | **Mesma pesquisa**, subconjunto de 149 respostas enviadas por e-mail | 149 (todas dentro das 212) | e-mail |

As duas do Qualtrics viram uma só: 212 respostas, das quais 149 ganham o e-mail pelo ResponseId.

## Proposta

### A. Avaliações do evento (2024 e 2025) → casas que já existem em `engagement`

- `engagement.avaliacao_do_evento`: uma linha por pessoa por edição (experiência, profissão, expectativas quando houver, mais gostou, melhorar, comentário, `formulario_versao` = 2024/2025, `origem` = importação).
- `engagement.avaliacao_do_evento_atividade`: a nota de cada palestra/painel (1–5 cabe na escala 0–5).
- `engagement.nps`: a nota 0–10 de 2025.
- Perguntas sem coluna própria (temas aplicáveis, temas sugeridos, convidados sugeridos, impacto na prática, interesse em cursos, aceite de contato, notas de aspecto como organização/conforto/comunicação) → `engagement.feedbacks` (chave e valor, `contexto` com edição, pergunta e id da resposta).
- Pessoa: e-mail → `mind_identidade_resolver` (acha ou cria o Mind ID, Regra #1).

Ajustes necessários nas casas (mudança estrutural — **precisa do seu OK**, D2):
1. `summit_2026.events`: criar as linhas **Mind Summit 2024** e **Mind Summit 2025** (inativas).
2. `summit_2026.sessions`: cadastrar as palestras/painéis avaliados de 2024 (≈13) e 2025 (11), ligadas ao evento de cada ano, para receberem nota. Ficam fora da agenda do app (evento inativo).
3. `engagement.nps`: hoje aceita **uma nota por pessoa para sempre** (único em `mind_id`). Trocar para único em `(mind_id, event_id)` — sem isso o NPS de 2025 bloquearia o de 2026.
4. `engagement.avaliacao_do_evento`: aceitar `origem = 'importacao'`, `experiencia = 'camarote'` (14 respostas de 2025) e `expectativas` vazia quando importada (o formulário de 2025 não perguntou).

### B. Pesquisa de interesse (Qualtrics) → `engagement.feedbacks`

É pesquisa de mercado, não avaliação de evento. Uma linha por resposta a cada pergunta (`tipo = 'pesquisa_interesse_2025'`), com `mind_id` nas 149 identificadas e sem `mind_id` nas 63 anônimas (a coluna aceita). Nenhuma tabela nova.

Alternativa, se preferir uma casa própria para pesquisas futuras: uma tabela `engagement.pesquisa_respostas` (pesquisa, resposta, pessoa, pergunta, valor). Recomendo começar por `feedbacks` e só criar a tabela se as pesquisas virarem rotina.

### O que NÃO muda sem novo gate

- "Podemos entrar em contato?" (187 "sim" em 2025) e "interesse em continuar aprendendo" (163 sim, 171 talvez) ficam guardados, mas **não disparam nenhum contato** (outbound tem gate próprio).
- Nada disso vai para a memória do agente (o contrato de sensibilidade vem antes).

## Para aprovar

- [ ] A: avaliações 2024/2025 nas casas de `engagement`, com os 4 ajustes acima.
- [ ] B: pesquisa de interesse em `engagement.feedbacks` (ou tabela própria).
