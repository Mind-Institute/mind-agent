# Relatório de valor para o patrocinador — dados do Supabase (Mind Summit 2026)

> Extraído em 24/09/2026 da base `intelligence.v_relatorio_patrocinador_audiencia`: uma linha por
> pessoa da audiência. **Palestrantes e staff estão fora.** Os números de audiência contam
> **presentes**. Cada % traz o denominador; onde a cobertura é parcial, isso está dito.
> Plano e lacunas: `docs/PLANO_RELATORIO_PATROCINADORES.md`.


> **Recalculado (24/09, 03:25 UTC):** a página inteira foi refeita com uma regra única, em
> `docs/sql/relatorio_patrocinadores_base.sql` + `docs/sql/relatorio_patrocinadores_numeros.sql`: empresa agrupada
> por domínio/sigla/unidade em todas as seções; porte e setor da pessoa = do grupo; "sem patrocinadores" = sem as
> pessoas das empresas patrocinadoras. Resultado: 1.716 presentes com empresa (90%), **1.084 empresas**, 585 com
> porte; **39%** dos presentes com porte conhecido (959, sem patrocinadores) em empresas com +1.000 funcionários e
> 27% com +5.000; 29 empresas com 5+ pessoas.

> **Atualização (24/09, 03:30 UTC), pedidos da Adriana na página:**
> - **Área:** "Outras áreas de negócio" (382) foi quebrada (`intelligence.area_por_cargo`, migration
>   `20260924030426`). Cargos de áreas existentes voltaram para a área certa; áreas novas: SMS/segurança/ESG,
>   Serviço público, Administrativo/Secretariado, Relações institucionais; "Liderança sem área informada" (151)
>   para cargos só com nível ("Diretora", "Gerente"); sobram 46 em "Outras funções".
> - **Delegações e empresas:** empresas agrupadas pelo domínio de e-mail corporativo + regras de
>   unidade/sigla (Senac, Sefaz SP, Beiersdorf, Sebrae, USP, PMSP). Resultado: **1.091 empresas** (antes
>   1.138); Sefaz SP 13, Lubrin 12, Sebrae 7, Motiva 6 passaram a aparecer somadas. Empresas com porte: 590
>   (+10.000: 83; 5.001–10.000: 22).
> - **Dimensão, visão 2:** sem as 251 cortesias que não vieram em nenhum dia → 2.110 inscritos, **90%** de
>   comparecimento (visão 1: 2.361, 80%).
> - **Satisfação:** NPS adaptado retirado da página; fica a nota média 9/10 (64 avaliações).
> - **Conteúdo:** 57 sessões (lançamentos fora; abertura e entrevista contadas como palestras), 56,7 h.

> **Atualização (24/09, 02:40 UTC):** porte e setor completados pela Lusha e setores traduzidos para 19
> setores em português (`intelligence.setor_macro`). Porte agora cobre **62%** dos presentes (HubSpot 790 +
> Lusha 387); **40%** dos presentes com porte conhecido (sem patrocinadores) estão em empresas com +1.000
> funcionários e **27%** em +5.000 (o 47% abaixo era só HubSpot, enviesado para empresas grandes).
> Beiersdorf conta como delegação (BDF Nivea + Beiersdorf = 19). NPS adaptado (nota 0–5 × 2): **61**, média
> 8,9 de 10, 64 respondentes. Versão visual e atualizada: página "Audiência Mind Summit 2026".

## 1. Dimensão do Mind Summit

| | |
|---|---|
| Inscritos válidos (audiência, sem palestrantes/staff) | **2.361 pessoas** |
| Presentes (pelo menos 1 dia) | **1.897** → comparecimento **80%** |
| Dia 16/09 · Dia 17/09 | **1.704 · 1.497** |
| Presentes nos dois dias | **1.304** → **77%** de quem veio no Dia 1 voltou no Dia 2 |
| Presentes por ingresso | Mind 805 · VIP 706 · Prime 287 · Camarote 99 |
| Empresas únicas representadas (presentes) | **1.147** (1.115 sem contar patrocinadores e o Mind) |
| Palestrantes | **65** |
| Sessões de conteúdo | **59** (16 palestras, 13 painéis, 12 workshops, 4 masterclasses, 8 alumni talks, 2 experiências, 1 entrevista, 2 lançamentos, abertura) |
| Horas de conteúdo | **57,7 h** |

## 2. Quem estava na sala (1.897 presentes)

Cobertura: 1.780 presentes (94%) têm cargo e 1.771 têm ICP.

**Senioridade**

| | pessoas | % dos presentes |
|---|---:|---:|
| C-level / Fundador(a) / Sócio(a) | 382 | 20% |
| VP / Diretor(a) | 292 | 15% |
| Head / Gerente | 290 | 15% |
| Coordenação / Liderança | 184 | 10% |
| Analista / Especialista | 272 | 14% |
| Profissional independente (consultor, coach, psicólogo) | 316 | 17% |
| Academia / Estudante | 34 | 2% |
| Outros · Não informado | 127 | 7% |

- **1.148 pessoas (61%) ocupam posições de liderança** (coordenação para cima). Entre quem tem cargo informado, são 64%.
- **964 (51%) são gerentes ou acima**. **674 (36%) são diretores, VPs ou C-level.**

**Área**

| | pessoas |
|---|---:|
| RH / Pessoas | 451 (24%) |
| Gestão geral / C-level | 317 (17%) |
| Saúde e bem-estar | 285 (15%) |
| Consultoria / Coaching | 116 (6%) |
| Marketing / Comunicação | 53 · Comercial / Vendas 46 · Educação 40 · Estratégia 28 · Operações/Engenharia 28 · Finanças/Jurídico 26 · Tecnologia 8 |
| Outras áreas de negócio (área não explícita no cargo, ex.: "Diretora") | 382 |
| Não informado | 117 |

- Entre os líderes, **227 são de RH/Pessoas** e 317 são C-level/gestão geral.

**ICP do Mind (classificação por regra de 23/09)**

| ICP | pessoas |
|---|---:|
| Psicólogo(a) / Profissional de saúde e bem-estar | 255 |
| Gestor(a) / Middle Management (não RH) | 247 |
| Gestor(a) de RH (gerente / coordenador) | 205 |
| Diretor(a) / VP / Executivo(a) sênior (não RH) | 195 |
| Fundador / Sócio / Empreendedor | 185 |
| Analista / Especialista (não RH) | 138 |
| CEO / C-Suite | 134 |
| Consultor / Coach / Psicólogo | 127 |
| Analista / BP / Especialista de RH | 118 |
| CHRO / VP / Diretor(a) de RH ou Pessoas | 93 |
| Professor(a) / Pesquisador(a) / Estudante | 41 |
| Consultor(a) de RH e cultura | 26 |
| Outros · concorrente · sem ICP | 133 |

- **RH (CHRO + gestores + analistas/BP + consultores de RH): 442 pessoas (23%).**
- **Liderança executiva (CEO/C-Suite + fundadores + diretores/VPs, RH ou não): 607 (32%).**
- **Qual é o "ICP prioritário"?** A base não define. Decida quais códigos contam e o % sai direto.

## 3. As empresas presentes

- **1.725 presentes (91%) com empresa identificada**, em **1.147 empresas**.
- Delegações: **221 empresas com 2+ pessoas**, **29 com 5+** e **8 com 10+**.
- **Porte** (cobertura: 600 presentes de empresas não patrocinadoras têm nº de funcionários no HubSpot):
  - **47% (280 de 600) trabalham em empresas com mais de 1.000 funcionários**;
  - **32% (194 de 600) em empresas com mais de 5.000**.
  - Empresas por porte: +10.000: 69 · 5.001–10.000: 19 · 1.001–5.000: 52 · 501–1.000: 25 · 101–500: 54 · até 100: 125.
- Origem das empresas com país no HubSpot: Brasil 312, EUA 30, Índia 6, Alemanha 5, França 4, Reino Unido 3, Holanda 3, China 2.

**Top 20 maiores delegações, sem patrocinadores** (pessoas presentes)

| Empresa | Presentes | Porte |
|---|---:|---|
| Petrobras | 28 | +10.000 |
| Lubrin (Lubrificação Industrial) | 11 | 101–500 |
| Senac São Paulo* | 10 | — |
| Gerdau | 7 | +10.000 |
| MRS Logística | 7 | 5.001–10.000 |
| Secretaria da Fazenda e Planejamento | 6 | 101–500 |
| Almeida Sapata | 6 | 101–500 |
| Hospital Israelita Albert Einstein | 6 | +10.000 |
| Sebrae | 5 | 5.001–10.000 |
| Escola Internacional de Alphaville | 5 | 101–500 |
| Yara International | 5 | +10.000 |
| HSM | 5 | 501–1.000 |
| ANBIMA | 5 | 501–1.000 |
| Grupo Rascal | 5 | — |
| Comitê Paralímpico Brasileiro | 5 | 501–1.000 |
| BASF | 5 | +10.000 |
| SESI | 5 | 1.001–5.000 |
| TELUS Health | 4 | 5.001–10.000 |
| Banco BV | 4 | 5.001–10.000 |
| Motiva | 4 | 5.001–10.000 |

\*Senac SP aparece com dois nomes na base (5 + 5); somei aqui. Também com 4 presentes:
Instituto People, LBR Engenharia, Matrix Assessoria Contábil e Eduzz.

**Patrocinadores e o Mind entre os presentes** (por empresa da pessoa): Heineken 66 · Vale 47 · BWG
35 · Beiersdorf/BDF Nivea 18 · Faculdade BP/Beneficência Portuguesa 13 · Natura 10 · Wellhub/Wellz
10 · Haleon 9 · Sextante/GMT 8 · Bluma 5 · Mais Diversidade 4 · Mindself 3 · Profera 3.

## 4. Setores

- **72 setores** representados (classificação do HubSpot; cobertura: 780 presentes).
- Top setores por pessoas presentes, patrocinadores incluídos:
  1. Consultoria de gestão: 82
  2. Alimentos e bebidas: 77
  3. Mineração e metais: 54
  4. Petróleo e energia: 44
  5. Serviços ao consumidor: 41
  6. Recursos humanos: 40
  7. Hospitais e saúde: 29
  8. Engenharia mecânica/industrial: 26
  9. Materiais e equipamentos: 24
  10. Software: 23
  11. Treinamento/coaching: 23
  12. TI e serviços: 22
  13. Varejo: 18
  14. Farmacêutico: 18
  15. Bancos: 17
- Alimentos e bebidas e mineração estão puxados por Heineken e Vale. **Para a versão final, recalcular sem patrocinadores** e completar o setor de quem não tem.

## 5. Engajamento no app (dados da Yazo)

| | |
|---|---|
| Presentes que ativaram o app | **1.690 de 1.897 → 89% de adoção** |
| Presentes que reservaram sessões | **1.638 (86%)**; 20.368 reservas; **12,4 por pessoa** que reservou |
| Presentes com check-in em sessão | **1.727 (91%)**; média de **4 sessões** por pessoa |
| Presentes que trocaram contato pelo app | **975 (51% dos presentes; 58% dos que ativaram)** |
| Trocas de contato registradas | 15.806 · mediana de **7 por pessoa** que trocou · 9,3 por usuário ativo |
| Mensagens | 679, trocadas por 143 pessoas |
| Feed | 69 posts, 245 curtidas, 8 comentários |
| Favoritos | 3.150 em palestrantes · 890 em agendas |
| Concierge (Mind Agent no app) | 629 sessões com interesses registrados |

Não está no banco (pedir à Yazo): downloads, usuários ativos por dia, telas vistas, cliques em banners/logos e materiais baixados.

## 6. O que as pessoas queriam

**Sessões mais frequentadas** (pessoas com check-in)

1. Onde foi parar o seu foco (neurociência e trabalho moderno), palestra, 17/09: **467**
2. Cultura emocional: entre o engajamento e o burnout, painel, 17/09: **418**
3. Liderança emocionalmente madura, palestra, 17/09: **272** (vagas: 300)
4. Os três movimentos do líder que destravam aprendizagem coletiva, masterclass, 16/09: **270**
5. Como produzir sem se esgotar, palestra, 16/09: **239**
6. Seu cérebro não foi feito para isso, palestra, 17/09: **237**
7. O seu emprego vai existir daqui a 5 anos? (IA e trabalho), palestra, 16/09: **235**
8. Mensurar, intervir, provar: metodologia Oxford para wellbeing, masterclass, 16/09: **224**
9. Navegar a mudança: liderança em contextos de incerteza, workshop, 17/09: **214**
10. Como a consciência da finitude transforma a forma de viver, palestra, 16/09: **213**

**Muito disputada:** "Conversas Corajosas, Times Fortes: segurança psicológica" teve **385 reservas** (a maior procura antecipada), com 172 check-ins.

**O que cada público buscou mais que a média** (interesse relativo = % do grupo na sessão ÷ % geral; só sessões com 20+ pessoas do grupo):

- **RH (451):**
  - "Bem-estar começa na agenda: como transformar intenção em prioridade organizacional": 1,9×
  - "A virada da diversidade": 1,6×
  - "Os três movimentos do líder…": 1,5× (22% do RH presente)
  - "Conversas difíceis, times que crescem": 1,5×
- **C-level (363):**
  - "Florescendo em tempos de incerteza: otimismo como vantagem competitiva": 1,6×
  - "Quem está no controle? relação saudável com a tecnologia": 1,5×
  - "Navegar a mudança": 1,4×
  - "Como produzir sem se esgotar": 1,4×
- **Gestores (479):**
  - "O líder como arquiteto do trabalho": 1,8×
  - "Conversas difíceis": 1,4×
  - "Inteligência relacional para líderes": 1,3×
  - "Liderança engajadora": 1,3×
- **Saúde e bem-estar (203):**
  - "Quem está no controle? (tecnologia)": 2,2×
  - "Da mensuração ao PGR: riscos psicossociais": 2,0×
  - "A economia da distração": 2,0×

**Interesses declarados no app** (Concierge, 629 sessões), em ordem:
1. Saúde mental: 137
2. Segurança psicológica: 127
3. Estruturar saúde mental e bem-estar na empresa: 122
4. NR-1 e riscos psicossociais: 120
5. Liderança: 114
6. Cultura organizacional: 110
7. Felicidade e propósito: 107
8. Futuro do trabalho: 105
9. Pesquisas e tendências: 99
10. Performance sustentável: 96
11. Dados e ROI do bem-estar: 96

**Avaliação (0 a 5, não é NPS):**
- Evento: 29 respostas; relevância 4,55 e programação 4,48.
- Por dia: 39 respostas; 4,44 e 4,33.
- **A amostra é pequena demais para o relatório.** Precisamos da pesquisa pós-evento.

## 7. Por patrocinador: quem veio pelo ingresso do patrocinador

Ingressos emitidos com a marca do patrocinador (coluna "Empresa Patrocinadora" da Yazo):

| Patrocinador | Ingressos | Presentes | Liderança (coord.+) | RH | Ativaram o app | Trocas de contato |
|---|---:|---:|---:|---:|---:|---:|
| Heineken | 130 | 92 (71%) | 57 | 36 | 78 | 405 |
| BWG | 88 | 65 (74%) | 48 | 17 | 60 | 431 |
| Vale | 43 | 39 (91%) | 33 | 16 | 37 | 286 |
| WellZ | 36 | 27 (75%) | 20 | 8 | 25 | 129 |
| Sextante | 22 | 20 | 11 | 0 | 10 | 115 |
| Beiersdorf | 23 | 20 | 16 | 6 | 19 | 65 |
| Mindself | 20 | 17 | 13 | 2 | 17 | 60 |
| Profera | 16 | 14 | 9 | 3 | 12 | 34 |
| Bluma | 20 | 11 | 2 | 7 | 8 | 26 |
| Haleon | 13 | 9 | 9 | 1 | 9 | 14 |
| Chilli Beans | 7 | 6 | 3 | 0 | 4 | 39 |
| Natura | 7 | 6 | 3 | 3 | 2 | 9 |
| Mais Diversidade | 5 | 5 | 4 | 0 | 4 | 35 |
| BP | 4 | 4 | 3 | 0 | 4 | 46 |

Para as páginas por patrocinador ainda faltam:
- **Contratado × entregue × extras:** contratos e produção.
- **De-para sessão → patrocinador:** com ele, o perfil da audiência do conteúdo patrocinado sai direto da mesma base.
- **Leads e visitas nos estandes:** cada patrocinador.
- **Cliques na marca no app:** Yazo.

## Índice "Mind Audience Quality" (componentes)

| Componente | Valor |
|---|---|
| Senioridade | **51% gerente ou acima**; 61% em liderança |
| Grandes empresas | **47% em empresas com +1.000 funcionários** (entre os com porte conhecido) |
| RH e liderança executiva | 23% RH · 32% liderança executiva |
| Diversidade empresarial | **1.147 empresas · 72 setores** |
| Engajamento | **89% ativaram o app** · 86% montaram agenda · 91% fizeram check-in em sessão |
| Networking | **51% trocaram contato** · mediana de 7 trocas |

## Ressalvas

- Porte e setor vêm do HubSpot e cobrem **~42% dos presentes**. Para afirmar "% em grandes empresas" sobre o total, é preciso enriquecer o restante (Lusha ou HubSpot).
- Senioridade e área saem do cargo declarado e da regra de ICP, sem IA. "Outras áreas de negócio" reúne cargos que não dizem a área (ex.: "Diretora").
- Aliases a decidir antes da versão final: BDF Nivea × Beiersdorf; Sextante × GMT Editores; Faculdade BP × Beneficência Portuguesa; Senac SP (dois nomes).
- Trocas de contato: número informado pela Yazo; pode contar os dois lados de cada troca.

## Seções 9–11: Mind Summit 2025 e comparação (24/09/2026)

- Base 2025 = inscritos com ingresso "Atribuído" em `eduzz.ingressos` (contas `mind_dash` + `ef`), sem
  staff/palestrantes. Não há presença de 2025 na base, então a comparação 2025 × 2026 usa inscritos nos
  dois anos (2026: `credenciamento_summit_2026.controle_de_inscritos_e_presenca`, `valido_no_mind = 'sim'`).
- Empresa, porte e setor pelo mesmo método nos dois anos (pessoas.empresas → HubSpot → Lusha); mesma regra
  de grupo de empresa das seções 3 e 4. SQL: `docs/sql/relatorio_2025_numeros.sql`.
- Versão preliminar: recalcular depois da limpeza (typos de e-mail, empresas-sujeira, duplicatas).
