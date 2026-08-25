# LEIA PRIMEIRO — como se trabalha neste repositório

Qualquer IA ou pessoa que chegar aqui tem que saber disto **antes** de tocar em código,
banco, prompt ou schema. Isto vale mais que qualquer outro documento.

## Contrato: quem faz o quê

- **A IA (Claude etc.) executa e aconselha a parte TECNOLÓGICA.** O "como": edge functions,
  n8n, código, SQL, RPCs, estrutura de tabela, wiring, e o aconselhamento de engenharia
  (como alimentar o LLM pra dar a melhor resposta, o que entra no contexto vs. o que se
  busca sob demanda, como a inteligência é persistida e recuperada, retrieval, fluxo de dado).
- **Adriana é dona do "QUÊ".** Conteúdo, prompts, inteligência de negócio e de produto.
  **Toda verdade de negócio mora numa tabela e é SEMPRE dela** (preço, lote, produto, o que
  cada vertical vende, mapeamentos, posicionamento).

## Regras invioláveis

1. **Nunca crie prompt ou conteúdo.** Onde entra prompt/conteúdo, deixe o espaço pronto e
   **vazio** pra Adriana preencher.
2. **Antes de criar QUALQUER tabela: (a) cheque o que já existe, (b) pergunte à Adriana.**
   E **nunca preencha/popule uma linha sem autorização explícita dela.** (Foi exatamente
   "sair criando/preenchendo sem checar" que encheu este sistema de tabela duplicada e inútil
   que ninguém entende — isso atrapalha, não ajuda. Ex.: já existiam playbooks e uma IA criou
   uma tabela `agentes.playbooks` duplicada.)
   **Exceção:** preenchimento de **teste** pode — desde que você **avise** a Adriana (ex.: uma pessoa/linha de teste).
3. **Explique tudo que fizer**, de um jeito que ela entenda o próprio sistema. Nada opaco:
   ela tem que entender a engenharia do sistema dela.
4. **A fonte da verdade é o banco real** (Supabase `mind-agent`, ref `ymnmotgglsrxmjmonwjz`),
   não documentação. Doc é anotação, nunca portão.
5. **Agilidade > cerimônia.** Quase tudo hoje é teste: **deletar é mais rápido que migrar**.
   Nada de migração/governança pesada sem necessidade real.

## Ordem do trabalho (agora)

1. **Vendas Summit ponta-a-ponta PRIMEIRO** — um agente só, completo, antes de qualquer outro.
   Não é clonagem: os agentes diferem por plataforma/função (ex.: o concierge nem passa por
   WhatsApp/Treble). O que se reaproveita é o **núcleo** (identidade, reconhecimento, contexto,
   inteligência), não o agente inteiro.
2. **Playbook de vendas = princípios universais** (Adriana escreve) **+ contexto do produto
   injetado na hora** (Claude constrói a busca — fininha e guiada pelo dado: Summit real hoje,
   Dash quando tiver dado). O vendedor é um só e sabe vender qualquer vertical buscando o
   contexto do produto que está na mesa.
3. **Reconhecimento na chegada** (já existe): identifica a pessoa (`pessoas.pessoas`), deriva a
   vertical, e puxa histórico (`crm.contato_espelho` + `crm.negocios_historicos`) e pipeline
   aberto (`crm.pipeline_summit_leads_captados`).
4. **Faxina** de `engagement`/`intelligence` **DEPOIS** de construir (mantém o que os agentes
   de fato usarem), nunca antes.
5. **HubSpot write-back por ÚLTIMO** (idempotente, com trava).

### Divisão concreta de amanhã
- **Claude:** função que traz o contexto do produto Summit + encaixe do reconhecimento no
  turno de vendas + esqueleto do agente/edge function + n8n se precisar.
- **Adriana:** prompt base, prompt de plataforma, e o playbook de vendas (conteúdo).

## Onde as coisas já moram (NÃO recriar)
- **Playbooks + prompt base + tom de voz** = linhas em **`agentes.prompts`** (por `chave`):
  `playbook_router` (base/identidade), `playbook_summit_b2b`, `playbook_summit_b2c`,
  `playbook_cliente_suporte`, `tom_de_voz`. **Não existe (nem crie) tabela `playbooks`.**
- Config dos agentes por plataforma: `concierge.*` (app) e `treble.config` (WhatsApp).
- **Origem do lead na chegada** → salva em `engagement.origens` (provisório; a confirmar se fica aqui ou vai pra outro lugar).

## Mapa do que existe hoje
Ver `docs/ARQUITETURA.md` (o que é real × teste × placeholder por schema).
