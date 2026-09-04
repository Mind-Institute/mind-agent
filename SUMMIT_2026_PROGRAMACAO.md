# Mind Summit 2026 — programação e palestrantes

> **SNAPSHOT HISTÓRICO.** A programação viva em 04/09/2026 tem 77 sessões,
> 81 vínculos sessão–palestrante e 64 palestrantes. Use o banco como fonte
> operacional; o restante deste documento preserva o contexto da consolidação.

Checkpoint factual e decisões aprovadas em 30/08/2026.

## Programação

A programação atual do Mind Summit 2026 foi reconstruída em produção a partir de `Mind-Institute/mindsummit2026/src/data/programacao.json`.

Estado verificado em produção em 30/08/2026, já incluindo os Alumni Talks acrescentados ao site depois do rebuild:

- `summit_2026.sessions`: 77 sessões;
- 39 sessões em 16/09/2026;
- 38 sessões em 17/09/2026;
- `sessions.site_session_id` preenchido e distinto nas 77 — é a chave determinística que corresponde a `programacao.json.id`;
- os `sessions.id` permanecem estáveis;
- o wipe original foi excepcional e só foi permitido porque não havia jornada, feedback, recomendação, interesse ou inscrição operacional dependente das sessões.

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

- `ecossistema.palestrantes_especialistas`: **64 registros**;
- **31 registros ricos originais**, preservados intactos: têm `quem_e`, `formacao_e_posicao`, `principais_contribuicoes` e `conceitos_chave_explicados`; 30/31 têm `fontes_gerais`; 29/31 têm `relevancia_para_os_icps_do_mind`;
- **33 registros mínimos acrescentados** (ids 32–64) a partir de `speakers.json`: `nome` ← `name` e `quem_e` ← `bio` do site, com `cargo_curto` e `instituicao` NULL porque o site não traz `institution` explícito para nenhuma delas. Isso é **deliberado**, não lacuna de qualidade: o objetivo desta etapa foi identidade + bio mínima. O enriquecimento editorial dessas 33 fica para depois;
- zero duplicata canônica: os índices únicos por `lower(btrim(nome))` e por `slug` seguem sem violação;
- `Márcio Atalla` permanece no Ecossistema e não faz parte do line-up atual do site — preservado;
- `session_speakers`: **12 vínculos**, o estado ANTES da reconstrução;
- os 12 têm `speaker_id` canônico preenchido e cobrem Amy Edmondson, Christina Maslach, Jan-Emmanuel De Neve e Sonja Lyubomirsky;
- os demais vínculos antigos não foram reconstruídos no rebuild porque não tinham identidade canônica segura.

### Fora do escopo por decisão

`Sibelle Pedral` e `Virginie Leite` aparecem em `programacao.json` como mediação, mas não existem em `speakers.json`. Decisão de 30/08: **não entram**. Não criar registro no Ecossistema, não criar vínculo em `session_speakers`, não pesquisar bio e não tratar como pendência.

Com essa exclusão, `programacao.json` tem 83 ocorrências pessoa×sessão brutas e **81 relevantes**.

Reconstruir os vínculos continua sendo trabalho do Passo 12A. Não resolver por fuzzy matching nem recriar identidade paralela.

## Fonte e mirror

Para a programação corrente deste evento:

- SOURCE: `Mind-Institute/mindsummit2026/src/data/programacao.json`;
- MIRROR operacional consumido pelo Core: `summit_2026.sessions`.

O dossiê perene dos especialistas continua sendo `ecossistema.palestrantes_especialistas` e não deriva automaticamente da programação do site.
