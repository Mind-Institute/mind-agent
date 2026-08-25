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
6. **Responda objetivo, UMA ação por vez.** A Adriana se perde com respostas longas e cheias
   de contexto. Vá com um passo de cada vez, explique o essencial em poucas linhas, e espere
   a resposta antes do próximo passo. Menos contexto, mais direto.

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

## Agente novo numa plataforma nova? A conversa e a inteligência JÁ TÊM CASA (não criar tabela apartada)

O núcleo do Mind é **um só e compartilhado** entre todos os agentes (vendas, atendimento,
concierge, e os que vierem). Só muda a **plataforma** (por onde a pessoa fala) e a **função**
(o que o agente faz). Quando montar um agente numa plataforma nova (site, Instagram, e-mail,
telefone…), siga isto — pra inteligência do Mind não se partir em ilhas:

- **Config da plataforma** → um schema só de config daquela plataforma (como `treble` p/ WhatsApp,
  `concierge` p/ o app): token, modelo, templates, flags. **Só config. Conversa NÃO mora aqui.**
- **A conversa** (as mensagens trocadas) → **SEMPRE** `engagement.conversas` + `engagement.mensagens`,
  com a coluna **`agente`** dizendo quem escreveu (`treble-inbound-agent`, etc.). Uma casa só pra
  conversa de todos os agentes. **Nunca** `treble.messages`, `concierge.mensagens`, `plataformaX.conversas`.
- **O que o agente APRENDE** com essas mensagens (sinal, intenção, objeção, dossiê da pessoa) →
  **SEMPRE** `intelligence.*`, marcando de qual agente veio. **Nunca** uma tabela de inteligência
  separada por plataforma.
- **Quem a pessoa é** → `pessoas.pessoas` (uma identidade só). Os canais dela (WhatsApp, e-mail,
  sessão) → `engagement.identidades`.

**Por quê:** se cada plataforma tiver a sua própria tabela de conversa/inteligência, o vendedor
do WhatsApp não enxerga o que o concierge do app já sabia — a inteligência do Mind vira ilha.
Compartilhado é o **núcleo** (identidade, reconhecimento, engajamento, inteligência); por-plataforma
é só a **config/o encaixe**. (Foi isso que quase aconteceu com o Treble: a conversa ia parar numa
tabela `treble.*` à parte, longe de tudo. Voltou pra `engagement`.)

**Antes de criar tabela, pergunte:** é conversa? já tem casa (`engagement`). É coisa aprendida
sobre a pessoa? já tem casa (`intelligence`). Só a **config** da plataforma nova ganha lugar novo.
Marque a origem com a coluna **`agente`** (e/ou um campo de origem) — **não** com uma tabela nova.

## Mapa do que existe hoje
Ver `docs/ARQUITETURA.md` (o que é real × teste × placeholder por schema).
