# Inventário de conhecimento — Mind Institute

**Rascunho de 20/10/2026. Nada escrito no banco.** Para validarmos, item a item, o
que o agente poderá afirmar — antes de atualizar a fixture.

## Como ler

| nível | significa |
|---|---|
| ✅ **confirmado** | está em fonte validada: `institute_catalogo` ou `product_intelligence`, lidos do banco |
| ⏳ **aguardando** | descrito em material antigo (`vendas_institute`, retrato de 17/09). Pode estar certo; não foi conferido |
| ❓ **não documentado** | não aparece em nenhuma fonte consultada |

> **❓ não significa inexistente.** Significa que não encontrei. Pode existir e não
> estar escrito em lugar nenhum que o agente leia — que é, aliás, o caso mais
> provável para boa parte da seção de instrumentos.

> **Recurso disponível não é ferramenta para um assunto.** Acervo, credencial e
> prazo de acesso são recursos da contratação. Nenhum deles responde "o que eu uso
> para conduzir uma conversa difícil", e não devem ser oferecidos como se
> respondessem.

## Prioridade de validação, por jornada

A ordem depende do que a pessoa veio fazer:

| jornada | o que precisa estar validado |
|---|---|
| **responder sobre recursos** ("o que vocês têm para X") | capacidades e instrumentos |
| **vender** | capacidades e instrumentos **+** preço, condições, disponibilidade e destino de compra |
| **explicar como a formação funciona** | o método |

Hoje só a primeira coluna tem base parcial, e é por isso que a jornada de recursos
é a que trava primeiro.

---

# Parte I — Por programa

## 1. Certificação Avançada em Liderança Positiva

| afirmação proposta | fonte | nível | dúvida a resolver |
|---|---|---|---|
| "Desenvolve as três competências em um percurso completo" | KIT `subtitulo` | ✅ | — |
| Inclui Liderança Consciente, Engajamento e Significado, e Segurança Psicológica | KIT `ofertas[].inclui` | ✅ | — |
| 80 horas, 16 semanas, online ao vivo | KIT | ✅ | — |
| 16/02/2027 a 01/06/2027 | KIT | ✅ | — |
| Formadoras: Adriana Drulla, Tamara Myles, Elaine Lizeo | KIT | ✅ | — |
| R$ 4.997 à vista ou 12x de R$ 416, preço regular sem prazo | KIT | ✅ | é o preço de balcão ou o da condição que ficou? (ver Parte III) |
| Não precisa ocupar cargo de liderança; serve também a RH, consultores e facilitadores | KIT FAQ | ✅ | — |
| Conteúdos acessíveis até 60 dias após a última live | KIT FAQ | ✅ | — |
| Credencial digital emitida via Accredible, após requisitos de conclusão | KIT FAQ | ✅ | quais são os requisitos? O FAQ remete à "apresentação do programa", que o agente não tem |
| Empresa pode inscrever profissionais | KIT FAQ | ✅ | o FAQ manda falar com a equipe — não há condição corporativa documentada |
| Quem já estudou no Mind deve falar com a equipe antes de contratar | KIT FAQ | ✅ | — |
| **Calendário de encontros** | — | ❓ | **o Kit traz zero encontros para a Certificação**, enquanto as três avulsas têm os seus. Ela herda os encontros das três? Se sim, dá para montar a agenda somando |
| Página: `/certificacao-avancada` | KIT | ✅ | sem âncora hoje; a migration de âncora não foi aplicada |
| Conteúdo programático | — | ❓ | as avulsas têm URL própria; a Certificação não tem |
| Na condição Summit, entregava ingresso 2027 + 12 meses de Journey | VI | ⏳ | **a condição expirou em 01/10.** Volta? |

## 2. Liderança Consciente (formação avulsa)

| afirmação proposta | fonte | nível | dúvida a resolver |
|---|---|---|---|
| "Autorregulação, bem-estar e performance para liderar sob pressão" | KIT `subtitulo` | ✅ | — |
| 30 horas, 6 semanas, online ao vivo | KIT | ✅ | — |
| 16/02/2027 a 23/03/2027 | KIT | ✅ | — |
| Formadora: Adriana Drulla | KIT | ✅ | — |
| **Seis encontros, com tema e data:** A mente do líder · Do piloto automático à consciência · Autorregulação e liderança de si · O cérebro social: pertencimento, status e poder · Liderança compassiva · Liderança intencional | KIT `encontros_ao_vivo` | ✅ | **é o conteúdo mais concreto que o Kit tem.** Pode ser citado como "o que é trabalhado"? |
| R$ 2.497 à vista ou 12x de R$ 208 | KIT | ✅ | ver Parte III |
| Conteúdo programático: `/conteudo-programatico/lideranca-consciente` | KIT | ✅ | é URL; o agente não lê o conteúdo |
| Página de compra: `/certificacao-avancada` | KIT | ✅ | a avulsa não tem página própria. Confirmar se a pessoa precisa escolher dentro da página |
| Trabalha "o que acontece dentro do líder" | VI | ⏳ | é a distinção que evita reembolso. Confirmar a formulação |
| Não inclui as outras duas formações nem a Certificação | KIT `condicoes` | ✅ | — |

## 3. Engajamento e Significado no Trabalho (formação avulsa)

| afirmação proposta | fonte | nível | dúvida a resolver |
|---|---|---|---|
| "Compreenda o que conecta as pessoas ao trabalho" | KIT `subtitulo` | ✅ | — |
| 25 horas, 5 semanas, online ao vivo | KIT | ✅ | — |
| 30/03/2027 a 27/04/2027 | KIT | ✅ | — |
| Formadora: Tamara Myles. **Zach Mercurio como convidado** | KIT | ✅ | **o Kit confirma a regra do VI**: convidado, não docente |
| **Cinco encontros:** Fundamentos do Trabalho com Significado · Comunidade · Contribuição · Crescimento · Integração dos 3Cs + aplicação prática | KIT | ✅ | "os 3Cs" aparece só aqui — é vocabulário público? |
| R$ 2.497 à vista ou 12x de R$ 208 | KIT | ✅ | ver Parte III |
| Conteúdo programático: URL própria | KIT | ✅ | — |

## 4. Segurança Psicológica Aplicada a Resultados e Inovação (formação avulsa)

| afirmação proposta | fonte | nível | dúvida a resolver |
|---|---|---|---|
| "Crie condições para que ideias, dúvidas e dificuldades entrem em conversa" | KIT `subtitulo` | ✅ | — |
| 25 horas, 5 semanas, online ao vivo | KIT | ✅ | — |
| 04/05/2027 a 01/06/2027 | KIT | ✅ | — |
| Formadora: Elaine Lizeo | KIT | ✅ | — |
| **Cinco encontros:** Fundamentos · Dinâmicas de equipes de alto desempenho · Liderança, cultura e mudança · Do diagnóstico à ação sustentável · Integração e plano de ação | KIT | ✅ | **é o que o B1 usa.** Pode ser citado como resposta a "o que vocês têm sobre conversas difíceis"? |
| R$ 2.497 à vista ou 12x de R$ 208 | KIT | ✅ | ver Parte III |
| Trabalha "o que o líder produz no time" | VI | ⏳ | — |
| Desenvolve voz ativa e conversas difíceis | PI `capacidades` | ✅ | é capacidade do Institute como um todo; confirmar que é desta formação |
| **Instrumento para usar numa conversa real** | — | ❓ | **a lacuna central.** Existe algo assim e não está documentado? |

## 5. Especialização em Gestão Estratégica de Bem-Estar no Trabalho

| afirmação proposta | fonte | nível | dúvida a resolver |
|---|---|---|---|
| "Uma jornada completa para desenhar, priorizar e avaliar programas" | KIT `subtitulo` | ✅ | — |
| 12 semanas, online ao vivo | KIT | ✅ | — |
| Início **previsto** para 03/03/2027, não confirmado; fim 26/05/2027 | KIT | ✅ | o Kit já marca como prevista |
| Formadora: Adriana Drulla | KIT | ✅ | — |
| **Carga horária** | — | ❓ | **vazia no banco.** É a única. Qual é? |
| R$ 4.997 à vista ou 12x de R$ 416 | KIT | ✅ | ver Parte III |
| Não precisa ser psicólogo nem trabalhar em RH | KIT FAQ | ✅ | — |
| Há orientação no FAQ sobre adequação para líderes de equipe | KIT FAQ | ✅ | **o VI diz que o FAQ manda redirecionar para a Certificação.** Confirmar a redação |
| Dedicação esperada por semana | KIT FAQ | ✅ | a resposta está no FAQ; conferir se traz número |
| O que acontece se perder um encontro | KIT FAQ | ✅ | — |
| **Calendário de encontros** | — | ❓ | zero no Kit, como a outra certificação |
| Não é para desenvolver a própria liderança | VI | ⏳ | é o corte mais importante do funil |

## 6. Mind Journey

| afirmação proposta | fonte | nível | dúvida a resolver |
|---|---|---|---|
| "A experiência anual de continuidade do Mind" | KIT `subtitulo` | ✅ | — |
| 24 horas, 12 meses, online ao vivo | KIT | ✅ | — |
| 01/10/2026 a 30/09/2027 | KIT | ✅ | já em curso |
| Curadoria: Adriana Drulla | KIT | ✅ | — |
| **Doze encontros mensais**, o primeiro "Unpack the Mind Summit" | KIT | ✅ | os demais aparecem como "Encontro de <mês>", sem tema |
| R$ 1.997 à vista ou 12x de R$ 166 | KIT | ✅ | ver Parte III |
| **Contratação anual**; o parcelamento não é plano interrompível | KIT `condicoes` | ✅ | — |
| **Não inclui** matrícula nas formações, na Certificação nem na Especialização | KIT `condicoes` | ✅ | — |
| **MIA Journey**: IA que consulta o acervo do Mind a partir de uma pergunta ou desafio real, identifica conteúdos relacionados, conecta perspectivas e mostra em quais fontes se apoia | KIT FAQ | ✅ | **o recurso mais próximo de ferramenta que existe documentado.** Está disponível durante os 12 meses? |
| **Seleção do mês**: indicação curta e opcional da curadoria — palestra, vídeo, paper ou artigo | KIT FAQ | ✅ | — |
| Do Summit 2026, só as plenárias Sextante, Mind e LinkedIn entram no acervo | KIT `condicoes` | ✅ | — |

---

# Parte II — Transversal

## Método — como os programas ensinam

| afirmação proposta | fonte | nível | dúvida a resolver |
|---|---|---|---|
| Online ao vivo, com encontros semanais às 19h | KIT (datas e horas por encontro) | ✅ | o VI diz "terças, 19h–20h30, 90 min". A hora confere; **dia e duração não estão no Kit** |
| Learn · Apply · Reflect | VI | ⏳ | vale para todos os programas? Continua sendo o método oficial? |
| Aprendizagem ativa: quizzes, estudos de caso, role-plays, feedback de pares | VI | ⏳ | **em quais programas existem de fato?** São atividades na plataforma, nas lives, ou ambos? |
| Ritmo próprio com prazos definidos | VI | ⏳ | — |
| MIA Liderança (Certificação) e MIA Estratégia (Especialização) | VI | ⏳ | **não estão no Kit**, só a MIA Journey está |
| Ressalvas da MIA: não é analytics, não analisa bases, não produz diagnóstico a partir de pesquisa, não estabelece causalidade, não substitui faculty nem a decisão da organização | VI | ⏳ | são obrigatórias e precisam acompanhar qualquer menção à MIA |

> **Nada desta seção responde "o que eu uso no trabalho".** É pedagogia: como o curso
> ensina. Role-play dentro de uma aula não é ferramenta de trabalho.

## Capacidades

| afirmação proposta | fonte | nível | dúvida |
|---|---|---|---|
| Institute: compreender bem-estar como sistema de gestão · identificar riscos e ativos psicossociais · transformar diagnóstico em plano de ação · construir business case e indicadores · desenvolver segurança psicológica, voz ativa e conversas difíceis · fortalecer pertencimento, contribuição, autonomia e significado · aplicar aprendizagem a problemas reais | PI | ✅ | são do Institute **como um todo**. Mapear qual pertence a qual programa |
| Limites: não executa a transformação pela organização · não é diagnóstico organizacional completo · não é intervenção clínica · não é pós-graduação regulamentada · não garante resultado | PI | ✅ | — |
| Adequado quando "a pessoa **ou a organização** precisa desenvolver competência" | PI | ✅ | — |
| Eixos canônicos: Bem-Estar · Segurança Psicológica e Voz Ativa · Engajamento e Significado · integração dos três | PB | ⏳ | conferem com os nomes do Kit |

## Regras comerciais a preservar

Conduta e limite. **Nada aqui depende de preço, e por isso nada aqui vence.**

| regra | fonte | nível | dúvida |
|---|---|---|---|
| Pergunte pela dor, não pelo cargo | VI | ⏳ | — |
| Árvore de adequação por dor | VI | ⏳ | tratar como hipótese, não regra |
| Liderança Consciente = dentro do líder · Segurança Psicológica = o que o líder produz no time | VI | ⏳ | — |
| Corte da Especialização | VI + KIT FAQ | ✅ | o FAQ confirma a orientação |
| Três perfis: líderes/gestores · RH · consultores | VI + KIT FAQ | ✅ | o FAQ da Certificação cita os três |
| Sempre dizer o escopo da avulsa | VI + KIT `condicoes` | ✅ | — |
| "Já sou aluno": não vender por cima, escalar | VI + KIT FAQ | ✅ | — |
| Descartar oferta com `elegibilidade.tipo = "order_bump"` | VI | ✅ | **já implementado**: o Kit filtra |
| Não cotar preço corporativo | VI + KIT | ✅ | não existe como dado |
| Zach Mercurio é convidado, não docente | VI + KIT | ✅ | o Kit o traz como `convidado` |
| Jan-Emmanuel De Neve é parceiro, não professor | VI | ⏳ | **não aparece no Kit** |
| Não prometer cupom | VI | ⏳ | quem controla desconto hoje? |
| Não prometer acesso imediato; entrega manual | VI | ⏳ | ainda vale? |
| Marcador cru no FAQ → não responder | VI | ⏳ | ainda há marcador no FAQ do banco? |
| Não gerar depoimento; existem dois, nominais | VI | ❓ | **quais são?** Não estão em fonte nenhuma |
| Não prometer resultado | VI | ⏳ | — |
| "+7 mil líderes", "86%", "+60 multinacionais" são do **Summit** | VI | ⏳ | — |
| Duas políticas de cancelamento no site, incompatíveis → responder só "garantia de 7 dias" e escalar | VI + KIT `condicoes` | ✅ | o Kit traz a garantia; **a contradição do site segue aberta** |
| Dados da empresa: MindDash Ltda., CNPJ, endereço | VI | ⏳ | conferir |

---

# Parte III — O trecho desatualizado, com valores e regras separados

**A seção não foi removida.** Em quase todo item há um **valor vencido** e uma
**regra que continua válida** — e é a regra que precisa sobreviver à limpeza.

| trecho do `vendas_institute` | valor vencido | regra que pode continuar |
|---|---|---|
| Tabela de duas faixas: condição e balcão, com seis linhas de preço | todos os números. A condição expirou em **01/10/2026**; o Kit traz uma faixa só | **"Cada produto pode ter mais de uma oferta; quando houver prazo, diga até quando vale"** — continua válido e é lido do Kit |
| "Certificação e Especialização: balcão R$ 5.997" | 5.997 não existe no catálogo | — |
| Parcelas 417 · 209 · 167 · 500 | o catálogo tem 416 · 208 · 166; **o guardrail barra as do prompt** | — |
| "12 × R$ 417 = R$ 5.004, contra R$ 4.997" | a conta mudou: 416,42 × 12 ≈ 4.997 | **"Nunca multiplique a parcela para provar o total; cite os dois números como o banco os traz"** — continua válido |
| "condição Summit: três avulsas R$ 5.991 · Certificação R$ 4.997 · economiza R$ 994 / balcão 7.491 · 5.997 · economiza 1.494" | todos os números | **"Comparar com a soma das avulsas é o argumento mais forte"** — continua válido, **com a conta feita na hora** |
| "A condição entrega ingresso Mind para o Summit 2027 + 12 meses de Journey. Ref.: ingresso R$ 1.697 · Journey R$ 1.997" | o Kit não traz bônus nenhum | **"Certificação e Especialização recebem bônus; avulsa só o ingresso; balcão nenhum"** — a *estrutura* pode voltar se a condição voltar. **Decidir** |
| "O checkout vai para a Eduzz. Mudou de destino duas vezes em 17/09" | `api.ofertas` tem 0 `checkout_url` | **"Se houver link em cache, ele pode estar errado"** vira: **nunca reutilizar link de conversa anterior; sempre o do Kit** |
| "o checkout aceita CNPJ" | depende do anterior | **"não prometa nota fiscal nem condição corporativa"** — continua válido |
| "URLs curtas: /certificacao, /especializacao, /minddash, /Mindjourney" | não conferidas | **"mande a página do Kit, não uma URL de memória"** — continua válido |
| "/para-empresas e /dash" como destinos | não estão no Kit | — |
| "As três formações saíram em 15/09 e não têm página própria; aparecem dentro da Certificação" | a data | **o Kit confirma**: as três apontam para `/certificacao-avancada`. Vira fato ✅ |
| "Três bumps vigentes que ninguém executa: journey-bump-em-certificacao R$ 497, journey-bump-em-formacao R$ 697, lideranca-bump-em-journey R$ 1.497" | os três códigos e valores saem do texto | **"descarte toda linha com `elegibilidade.tipo = order_bump`"** — continua válido e **já implementado no Kit** |
| "Encontros às terças, 19h–20h30 (90 min)" | o dia e a duração não estão no Kit | **a hora (19h) confere com todos os encontros do Kit** |

---

# O que eu gostaria de validar com você primeiro

1. **Os encontros com tema podem ser citados** como "o que é trabalhado"? São o
   conteúdo mais concreto que o Kit tem, e é o que sustenta o B1.
2. **A MIA Journey pode ser apresentada como recurso de trabalho?** É a única coisa
   documentada que se parece com ferramenta — mas é do Journey, não das formações.
3. **As duas certificações não têm encontros no Kit.** A Certificação herda os das
   três formações? Se sim, o agente pode montar a agenda somando.
4. **A carga horária da Especialização** está vazia no banco.
5. **Os dois depoimentos nominais** não existem em fonte nenhuma.
6. Na Parte III, **a estrutura de bônus da condição deve ser preservada** para quando
   uma condição voltar, ou sai de vez?
