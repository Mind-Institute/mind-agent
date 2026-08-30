# Mind Summit 2026 — programação e palestrantes

Checkpoint factual e decisões aprovadas em 30/08/2026.

## Programação

A programação atual do Mind Summit 2026 foi reconstruída em produção a partir de `Mind-Institute/mindsummit2026/src/data/programacao.json`.

Estado verificado após o rebuild:

- `summit_2026.sessions`: 69 sessões;
- 35 sessões em 16/09/2026;
- 34 sessões em 17/09/2026;
- os novos `sessions.id` passam a ser estáveis;
- o wipe foi excepcional e só foi permitido porque não havia jornada, feedback, recomendação, interesse ou inscrição operacional dependente das sessões.

A partir deste checkpoint, mudanças futuras de programação devem preservar `sessions.id` por UPDATE/INSERT. Não repetir wipe quando houver dado operacional dependente.

## Semântica canônica de capacidade e reserva

As duas colunas canônicas são:

- `lugares_limitados`: a sessão tem capacidade/lugares limitados;
- `reserva_recomendada`: é recomendável reservar antes.

Estas duas ideias são diferentes e devem continuar diferentes.

**Reserva não é obrigatória.** Não usar `precisa_reserva` como semântica nova do produto. Essa coluna existe hoje apenas por compatibilidade com código antigo e deve sair do caminho canônico conforme os consumidores forem migrados para `lugares_limitados` e `reserva_recomendada`.

Não introduzir novamente a linguagem “precisa de reserva” para representar `reserva_recomendada`.

## Identidade canônica de palestrante

Existe uma única identidade canônica de palestrante/especialista no Core:

`ecossistema.palestrantes_especialistas.id`

A relação de participação em sessão deve apontar para esse ID.

Hoje isso já existe em:

`summit_2026.session_speakers.speaker_id → ecossistema.palestrantes_especialistas.id`

O campo antigo `session_speakers.palestrante_id` é um UUID legado e não representa uma segunda identidade canônica. Não deve ser usado por lógica nova nem propagado para novos componentes.

Objetivo de convergência: `session_speakers` deve terminar com um único identificador de palestrante, referenciando `ecossistema.palestrantes_especialistas.id`. A remoção/renomeação física do campo legado só deve acontecer depois de migrar os consumidores que ainda dependem dele.

## Estado factual dos palestrantes em 30/08/2026

Verificado diretamente em produção:

- `ecossistema.palestrantes_especialistas`: 31 registros;
- os 31 têm `quem_e`, `formacao_e_posicao`, `principais_contribuicoes` e `conceitos_chave_explicados` preenchidos;
- 30/31 têm `fontes_gerais`;
- 29/31 têm `relevancia_para_os_icps_do_mind`;
- `session_speakers`: 12 vínculos após o rebuild;
- os 12 vínculos têm `speaker_id` canônico preenchido;
- os 12 cobrem Amy Edmondson, Christina Maslach, Jan-Emmanuel De Neve e Sonja Lyubomirsky;
- os demais vínculos antigos não foram reconstruídos no rebuild porque não tinham identidade canônica segura.

Completar a curadoria e religar os demais palestrantes continua sendo trabalho do Passo 12A. Não resolver por fuzzy matching nem recriar uma identidade paralela.

## Fonte e mirror

Para a programação corrente deste evento:

- SOURCE: `Mind-Institute/mindsummit2026/src/data/programacao.json`;
- MIRROR operacional consumido pelo Core: `summit_2026.sessions`.

O dossiê perene dos especialistas continua sendo `ecossistema.palestrantes_especialistas` e não deriva automaticamente da programação do site.
