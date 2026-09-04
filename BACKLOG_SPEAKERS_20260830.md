# Checkpoint de backlog — palestrantes após rebuild da programação

> **SUPERADO.** Em 04/09/2026 a produção tem 77 sessões, 81 vínculos
> sessão–palestrante e 64 palestrantes. O conteúdo abaixo preserva o diagnóstico
> anterior ao backfill.

Este arquivo preserva o delta factual de 30/08/2026 que deve substituir os números antigos da seção 12.6 de `BACKLOG.md` quando o backlog canônico for consolidado.

## Estado atual verificado

- `summit_2026.sessions`: **77 sessões** (39 em 16/09, 38 em 17/09), com `site_session_id` preenchido e distinto nas 77.
- `ecossistema.palestrantes_especialistas`: **64 registros**.
  - **31 ricos originais**, preservados intactos — `quem_e` 31/31, `formacao_e_posicao` 31/31, `principais_contribuicoes` 31/31, `conceitos_chave_explicados` 31/31, `fontes_gerais` 30/31, `relevancia_para_os_icps_do_mind` 29/31.
  - **33 mínimos acrescentados** (ids 32–64), com `nome` e `quem_e` vindos de `speakers.json`. `cargo_curto` e `instituicao` NULL porque o site não traz `institution` explícito para nenhuma delas. **Deliberado**: identidade + bio mínima agora, enriquecimento editorial depois.
  - Zero duplicata canônica.
  - `Márcio Atalla` preservado, fora do line-up atual do site.
- `summit_2026.session_speakers`: **12 vínculos** — estado ANTES da reconstrução.
- Os 12 vínculos têm `speaker_id` canônico preenchido.
- Eles correspondem aos 4 Legends: Sonja Lyubomirsky, Jan-Emmanuel De Neve, Christina Maslach e Amy Edmondson, em 3 sessões cada.
- Os vínculos antigos restantes não foram reconstruídos no wipe porque não possuíam `speaker_id` canônico seguro a preservar.

## Decisão canônica de identidade

Existe uma única identidade de palestrante/especialista para lógica nova:

`ecossistema.palestrantes_especialistas.id`

A FK já existente é:

`summit_2026.session_speakers.speaker_id -> ecossistema.palestrantes_especialistas.id`

`session_speakers.palestrante_id` é legado. Não criar nova lógica sobre esse UUID e não tratá-lo como segunda identidade canônica.

Objetivo de convergência: a relação sessão ↔ palestrante deve terminar usando somente o ID do Ecossistema. A remoção física do legado precisa esperar a migração dos consumidores que ainda o leem.

## O que mudou em relação ao checkpoint antigo

O checkpoint antigo de 61 vínculos, 9 resolvidos, 52 pendentes e +22 ligações imediatamente reparáveis deixou de representar o banco depois do rebuild de `sessions`.

Não reutilizar aqueles números para planejar o próximo reparo.

Novo ponto de partida:

- 77 sessions atuais, IDs estáveis, `site_session_id` como chave determinística contra `programacao.json.id`;
- 12 relações canônicas preservadas;
- 64 pessoas no Ecossistema — 31 com dossiê rico, 33 com identidade e bio do site;
- 63 das 63 pessoas de `speakers.json` resolvem para um id canônico (25 match exato, 5 por equivalência comprovada, 33 recém-criadas), zero ambíguo;
- `Sibelle Pedral` e `Virginie Leite` estão fora por decisão: sem registro e sem vínculo;
- 83 ocorrências pessoa×sessão brutas em `programacao.json`, **81 relevantes** após a exclusão;
- completar relações deve ser feito contra a programação atual e somente com identidade inequívoca;
- não usar fuzzy matching;
- não recriar UUID legado;
- não criar dossiê vazio apenas para fechar vínculo.

## Consumidor vivo já alinhado

`public.mindagent_chat_search` já usa `session_speakers.speaker_id` e `ecossistema.palestrantes_especialistas.id` para busca e retorno de speakers.

## Trabalho deferido do Passo 12A

Quando retomar:

1. ~~comparar os nomes atuais da programação com os especialistas curados~~ — **feito**: 63/63 resolvidos, zero ambíguo;
2. criar os vínculos determinísticos por `site_session_id` + `speaker_id` — **pendente**, bloqueado no merge da migration que torna `speaker_id` a identidade obrigatória;
3. as 33 pessoas criadas com bio mínima seguem como `CURADORIA_ECOSSISTEMA_PENDENTE` para enriquecimento editorial — identidade já resolvida, dossiê não;
4. manter casos ambíguos sem vínculo até resolução humana — nenhum caso ambíguo hoje;
5. depois migrar os consumidores legados que ainda leem `palestrante_id` e só então remover esse identificador. Todos os seis consumidores conhecidos leem `summit.session_speakers` e `comum.speakers`, schemas/tabelas que não existem mais: são código morto, não migração pendente.

Isto continua deferido para não bloquear o caminho crítico do vendedor.
