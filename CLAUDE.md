# Mind — regras para o agente de código

## Antes de trabalhar

1. Leia **`docs/CORE_UNIVERSAL.md`** — é o documento canônico do sistema.
2. **Investigue o sistema real** relacionado ao passo que você vai executar.
3. Documentação **descreve** o sistema; ela **não substitui** verificar o sistema.

## Ordem de autoridade

1. Decisões explicitamente fechadas com a Adriana.
2. Infraestrutura real: Supabase, código, migrations aplicadas.
3. Documentação canônica atual (`docs/CORE_UNIVERSAL.md`).

**Documentação antiga não é requirement.** Se um documento contradiz o sistema vigente, o
sistema vence e o documento é que está errado. Git preserva a história — não é preciso
preservar a contradição.

## Regras

- **Menor mudança correta.** Não redesenhe o que já foi aprovado.
- **Não invente requisitos.** Não crie arquitetura, entidade ou regra de um sistema que não
  existe. Se falta informação de negócio, pergunte.
- **Não reabra decisões fechadas.**
- **Não faça limpeza lateral.** Achou algo quebrado fora do escopo? Registre no `BACKLOG.md` e
  siga.
- **Não expanda legado.** O que a §13 do CORE_UNIVERSAL marca como legado não se replica em
  tabela ou código novo.
- **Teste só o afetado** e as regressões diretamente atingidas. Não rode suíte completa.
- **Agente novo consome o Core Universal.** Não reimplementa identidade, contexto, memória nem
  histórico.

## As quatro camadas

| camada | papel |
|---|---|
| **Intelligence** | factual — o que é verdade agora |
| **Playbook** | competência — como um excelente profissional pensa |
| **Decisioning** | estratégia — o que faz sentido agora |
| **Agent** | execução — o que se diz ou faz |

> PLAYBOOK DECIDE COMO PENSAR. INTELLIGENCE INFORMA O QUE É VERDADE AGORA.

Coletor factual não decide, não pontua, não recomenda e não escreve.

## Divisão de trabalho

- **Claude faz o encanamento:** edge functions, SQL, RPCs, estrutura de tabela, wiring,
  retrieval, fluxo de dado.
- **Adriana é dona do conteúdo e da verdade de negócio:** prompts, playbooks, preço, lote,
  produto, mapeamentos, posicionamento.

**Não invente prompt, playbook ou conteúdo de negócio.** Quando o conteúdo tiver sido fornecido ou explicitamente aprovado, implemente-o fielmente. Se depender de conteúdo ainda não definido, não invente para preencher o espaço — deixe-o pronto e vazio.

**Antes de criar qualquer tabela, investigue o que já existe.** Se a criação não estiver
explicitamente autorizada ou depender de uma decisão material ainda aberta, pergunte. Se a
tarefa já autorizou a mudança e a investigação confirmou a necessidade, implemente a menor
estrutura correta.

Conversa já tem casa (`engagement`), coisa aprendida sobre a pessoa já tem casa
(`intelligence`), identidade já tem casa (`pessoas` + `engagement.identidades`). Só a **config**
de uma plataforma nova ganha lugar novo.

**Não popule dado de negócio sem autorização.** Isso não impede seed, backfill ou carga que a
própria tarefa tenha mandado fazer — nesses casos, execute e relate. Dado de teste pode, avisando.

## Como responder

Objetivo, um passo por vez. Explique o essencial em poucas linhas e espere a resposta antes do
próximo passo. A Adriana precisa entender a engenharia do próprio sistema — nada opaco.

**Agilidade > cerimônia.** Quase tudo ainda é teste: deletar costuma ser mais rápido que migrar.
Nada de governança pesada sem necessidade real.
