# Checkpoint de backlog — palestrantes após rebuild da programação

Este arquivo preserva o delta factual de 30/08/2026 que deve substituir os números antigos da seção 12.6 de `BACKLOG.md` quando o backlog canônico for consolidado.

## Estado atual verificado

- `ecossistema.palestrantes_especialistas`: 31 registros.
- Cobertura dos 31 registros:
  - `quem_e`: 31/31;
  - `formacao_e_posicao`: 31/31;
  - `principais_contribuicoes`: 31/31;
  - `conceitos_chave_explicados`: 31/31;
  - `fontes_gerais`: 30/31;
  - `relevancia_para_os_icps_do_mind`: 29/31.
- `summit_2026.session_speakers`: 12 vínculos após o rebuild da programação.
- Os 12 vínculos têm `speaker_id` canônico preenchido.
- Eles correspondem aos 4 Legends: Sonja Lyubomirsky, Jan-Emmanuel De Neve, Christina Maslach e Amy Edmondson, em 3 sessões cada.
- Os 49 vínculos antigos restantes não foram reconstruídos no wipe porque não possuíam `speaker_id` canônico seguro a preservar.

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

- 69 sessions atuais e IDs agora estáveis;
- 12 relações canônicas preservadas;
- 31 especialistas já curados no Ecossistema;
- completar relações deve ser refeito contra a programação atual e somente com identidade inequívoca;
- não usar fuzzy matching;
- não recriar UUID legado;
- não criar dossiê vazio apenas para fechar vínculo.

## Consumidor vivo já alinhado

`public.mindagent_chat_search` já usa `session_speakers.speaker_id` e `ecossistema.palestrantes_especialistas.id` para busca e retorno de speakers.

## Trabalho deferido do Passo 12A

Quando retomar:

1. comparar os nomes atuais da programação com os 31 especialistas já curados;
2. criar apenas vínculos determinísticos para quem já existe no Ecossistema;
3. separar pessoas ainda sem dossiê como `CURADORIA_ECOSSISTEMA_PENDENTE`;
4. manter casos ambíguos sem vínculo até resolução humana;
5. depois migrar os consumidores legados que ainda leem `palestrante_id` e só então remover esse identificador.

Isto continua deferido para não bloquear o caminho crítico do vendedor.
