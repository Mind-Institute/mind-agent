# Mind — regras para o agente de código

## Antes de trabalhar

1. Leia **`PROJECT_STATE.md`** — é o checkpoint operacional versionado: arquitetura congelada, ordem do projeto, passo atual e decisões que não devem ser reabertas.
2. Leia **`BACKLOG.md`** — investigações, fragilidades e trabalho deliberadamente deferido que não deve ser redescoberto do zero.
3. Leia **`docs/CORE_UNIVERSAL.md`** — é o documento canônico do sistema real e dos contratos já implementados.
4. **Investigue o sistema real** relacionado ao passo que você vai executar.
5. Documentação **descreve** o sistema; ela **não substitui** verificar o sistema.

Uma IA que entra no projeto sem contexto deve conseguir reconstruir o ponto de trabalho lendo, nessa ordem, `PROJECT_STATE.md` + `BACKLOG.md` + `docs/CORE_UNIVERSAL.md` e só depois verificando o sistema real.

## Ordem de autoridade

1. Decisões explicitamente fechadas com a Adriana **e registradas na documentação versionada**.
2. Infraestrutura real: Supabase, código, migrations aplicadas.
3. Documentação canônica atual (`PROJECT_STATE.md` para arquitetura/ordem/checkpoint; `BACKLOG.md` para deferimentos; `docs/CORE_UNIVERSAL.md` para estado e contratos implementados).

**Documentação antiga não é requirement.** Se um documento contradiz o sistema vigente, o sistema vence e o documento precisa ser corrigido. Mas uma decisão congelada nova **não pode ficar só na conversa**: deve ser registrada antes de o passo ser considerado fechado.

### Regra de versão das decisões congeladas

- `CONGELADO` significa: decisão aprovada e registrada no Git.
- Se uma decisão congelada mudar materialmente o funcionamento ou a ordem do sistema, **não sobrescreva silenciosamente**. Atualize a versão do checkpoint em `PROJECT_STATE.md` (`vN → vN+1`), registre o que foi substituído e por quê, e ajuste somente as seções afetadas do `CORE_UNIVERSAL.md` quando a mudança também alterar o estado/contrato canônico.
- Git preserva o histórico; a documentação corrente deve preservar **a decisão vigente**, com referência clara ao que ela substituiu.

## Ritual de trabalho

```
INVESTIGAR
→ ENTENDER O QUE JÁ EXISTE
→ DECIDIR A MENOR MUDANÇA
→ IMPLEMENTAR
→ TESTAR SÓ O AFETADO
→ ATUALIZAR A DOCUMENTAÇÃO DO ESTADO FINAL
→ FECHAR O PASSO
```

Se algo relevante for descoberto mas deliberadamente deixado para depois, **não abra a frente agora**. Registre no fim do `BACKLOG.md` com: evidência já levantada, estado atual, por que foi deferido, o gatilho para retomar e dependências. Assim ninguém precisa repetir a investigação.

## Regras

- **Menor mudança correta.** Não redesenhe o que já foi aprovado.
- **Não invente requisitos.** Não crie arquitetura, entidade ou regra de um sistema que não existe. Se falta informação de negócio, pergunte.
- **Não reabra decisões fechadas.**
- **Não faça limpeza lateral.** Achou algo quebrado fora do escopo? Registre no `BACKLOG.md` e siga.
- **Não perca investigação deferida.** Antes de adiar uma frente investigada, registre o checkpoint suficiente para retomá-la sem redescoberta.
- **Não expanda legado.** O que a §13 do CORE_UNIVERSAL marca como legado não se replica em tabela ou código novo.
- **Teste só o afetado** e as regressões diretamente atingidas. Não rode suíte completa.
- **Agente novo consome o Core Universal.** Não reimplementa identidade, contexto, memória nem histórico.

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

- **Codex supervisiona a execução técnica:** decide a menor mudança e delega dentro das constraints canônicas.
- **Claude Code investiga e implementa o escopo delegado:** edge functions, SQL, RPCs, estrutura de tabela, wiring, retrieval, fluxo de dado — trazendo leitura independente. Não decide produto, não mergeia e não amplia escopo.
- **Adriana é dona do conteúdo, da verdade de negócio e dos gates sensíveis:** prompts, playbooks, preço, lote, produto, mapeamentos, posicionamento.

**Não invente prompt, playbook ou conteúdo de negócio.** Quando o conteúdo tiver sido fornecido ou explicitamente aprovado, implemente-o fielmente. Se depender de conteúdo ainda não definido, não invente para preencher o espaço — deixe-o pronto e vazio.

**Antes de criar qualquer tabela, investigue o que já existe.** Se a criação não estiver explicitamente autorizada ou depender de uma decisão material ainda aberta, pergunte. Se a tarefa já autorizou a mudança e a investigação confirmou a necessidade, implemente a menor estrutura correta.

Conversa já tem casa (`engagement`), coisa aprendida sobre a pessoa já tem casa (`intelligence`), identidade já tem casa (`pessoas` + `engagement.identidades`). Só a **config** de uma plataforma nova ganha lugar novo.

**Não popule dado de negócio sem autorização.** Isso não impede seed, backfill ou carga que a própria tarefa tenha mandado fazer — nesses casos, execute e relate. Dado de teste pode, avisando.

## Como responder

Objetivo, um passo por vez. Explique o essencial em poucas linhas. A Adriana precisa entender a engenharia do próprio sistema — nada opaco.

**Autonomia operacional.** Relate conclusões e checkpoints de forma objetiva, mas **continue automaticamente** quando não houver gate da Adriana (§2B do `PROJECT_STATE.md`). Parar é para gate sensível ou decisão de negócio não congelada — não para espera técnica, revisão ou verificação.

**Agilidade > cerimônia.** Quase tudo ainda é teste: deletar costuma ser mais rápido que migrar. Nada de governança pesada sem necessidade real.
