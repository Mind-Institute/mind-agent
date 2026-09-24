# Regra do ICP por cargo

> Como o Mind encaixa o cargo que a pessoa escreveu numa das 13 opções da propriedade **ICP** do
> HubSpot. Decisões da Adriana em 23 e 24/09/2026. Detalhe técnico e o resto do perfil (JTBD, resumo,
> write-back) em `docs/PERFIL_ICP_JTBD.md`.

## As 13 opções (o que vai para o HubSpot)

O rótulo é o que a pessoa vê no HubSpot. O valor interno de algumas opções antigas foi reaproveitado
com significado novo, por isso ele não bate com o rótulo. Fonte da verdade: `intelligence.icp`.

| código no banco | rótulo no HubSpot | quem entra |
|---|---|---|
| `chro_vp_diretor_rh` | CHRO / VP / Diretor(a) de RH ou Pessoas | RH com nível de diretoria ou C-level (diretora de RH, VP de pessoas, CHRO, CPO) |
| `gestor_rh` | Gestor(a) de RH (gerente / coordenador) | RH com gestão: gerente, coordenador, supervisor, head de área de RH, saúde corporativa com nível |
| `analista_bp_rh` | Analista / BP / Especialista de RH | RH sem gestão: analista, BP, especialista, assistente, estagiário de RH |
| `consultor_rh` | Consultor(a) de RH e cultura | consultor ou mentor cujo tema é RH, cultura, bem-estar corporativo |
| `ceo_csuite` | CEO / C-Suite | CEO, C-level fora de RH, presidente, VP, conselheiro, diretor geral/executivo, cargo executivo público (prefeito, secretário de estado) |
| `fundador_socio` | Fundador / Sócio / Empreendedor | fundador, sócio, proprietário, empresário, empreendedor, owner |
| `diretor_vp_nao_rh` | Diretor(a) / VP / Executivo(a) sênior (não RH) | diretor, head, superintendente fora de RH |
| `gestor_nao_rh` | Gestor(a) / Middle Management (não RH) | gerente, coordenador, supervisor, líder fora de RH |
| `analista_nao_rh` | Analista / Especialista / Contribuidor individual (não RH) | quem trabalha sem cargo de gestão e fora de RH, **inclusive profissões** (ver abaixo) |
| `consultor_coach` | Consultor / Coach / Psicólogo | consultor, coach, mentor, palestrante, facilitador, autor, autônomo |
| `psicologo_saude` | Psicólogo(a) / Profissional de saúde e bem-estar | psicólogo, psicanalista, médico, terapeuta, enfermeiro, nutricionista, psicopedagogo, educação física |
| `professor_pesquisador_estudante` | Professor(a) / Pesquisador(a) / Estudante | professor, docente, pesquisador, estudante |
| `outros` | Outros | **só** quem está fora do mercado ou não escreveu um cargo (ver abaixo) |
| `concorrente` | (não vai para o HubSpot) | quem trabalha numa empresa concorrente (hoje: Vittude), seja qual for o cargo |

## Profissões (decisão de 24/09)

Profissões e áreas de atuação sem nível de gestão entram em **Analista / Especialista / Contribuidor
individual (não RH)**. Exemplos reais do credenciamento: advogado(a), jornalista, colunista, editor(a),
redator(a), arquiteto(a), economista, engenheiro(a), designer, marketing, comunicação, comercial,
compliance, PMO, customer success, auditor(a) fiscal, juiz(a), delegado(a), policial, administrativo,
comprador(a), projetos, ESG.

Exceções que vão para **Psicólogo(a) / Profissional de saúde e bem-estar**: psicopedagogo(a),
profissional de educação física, psicodinamista, aplicador(a) ABA.

Se a profissão vier com nível ("Diretora jurídica", "Gerente de marketing"), o nível decide: diretora
jurídica é Diretor(a) não RH, gerente de marketing é Gestor(a) não RH.

## O que fica em "Outros"

- quem está fora do mercado de trabalho: aposentado(a), dona de casa, do lar;
- texto que não diz um cargo: "suplente", "Mediação", "GOP - SP", "Desenvolvimento de lideranças",
  "Mental Health".

Texto vazio ou recusa ("nenhum", "n/a", "x", "outros") não recebe ICP.

## Como a regra decide (a ordem é a decisão)

1. **Concorrente** pela empresa, antes de olhar o cargo.
2. **Fora do mercado** (aposentado, dona de casa) → Outros.
3. **"Executive" que não é executivo** (executive assistant, account executive, product owner) →
   Analista (de RH ou não RH).
4. **RH com nível** → CHRO/Diretor(a) de RH ou Gestor(a) de RH. RH decide antes de saúde: "Gerente
   Médica de Saúde Corporativa" compra para a empresa.
5. **Saúde** → Psicólogo(a) / saúde.
6. **RH sem nível** → Consultor(a) de RH, Analista/BP de RH, e assim por diante.
7. Consultor/coach → academia → fundador/sócio → C-suite → diretor → gestor → analista.
8. **Profissões** → Analista / Especialista (ou saúde, nas exceções).
9. **Erro de digitação**: se nada casou, cada palavra é comparada com um vocabulário fechado de nomes
   de cargo e a regra roda de novo ("dirrtor", "Diretorna", "emoresaria", "funder", "coodenador",
   "Pscióloga"). As profissões são checadas antes disso porque "engenheiro" está a 2 letras de
   "enfermeiro".
10. Nada disso → Outros.

Aceita siglas e abreviações (coord, ger, dir, supte, HRD, NR-1, SST) e cargos em inglês. Cargo que é
só um nível ("Gerente", "Diretora") entra com confiança 0,55 em vez de 0,70.

## De onde vem o cargo

Por prioridade: o que a pessoa escreveu no **credenciamento** (relatório consolidado da Yazo,
`credenciamento_summit_2026."Relatorio Yazzo Consolidado"`) → o que ela disse em **conversa** →
o cargo do **HubSpot** → `pessoas.pessoas`. ICP marcado à mão no HubSpot por alguém do time vence
sempre.

## Quem não recebe ICP

Staff, palestrantes, professores e parceiros de venda não são leads e não têm ICP nem JTBD
(`pessoas.pessoas.relacionamento_mind`).

## Onde mudar

- a regra: `intelligence.icp_por_cargo(cargo, empresa)` (migrations
  `20260924010000_icp_por_cargo_tolera_digitacao.sql` e `20260924020000_icp_por_cargo_profissoes.sql`);
- o vocabulário da correção de digitação: `intelligence.cargo_corrigir_digitacao`;
- rótulos e opções: `intelligence.icp` (editar o catálogo alinha o HubSpot sozinho);
- contrato que prova a regra: `tests/icp_por_cargo_digitacao_contract.sql`.

A reclassificação roda sozinha de hora em hora (`perfil_projetar_horario`, hh:36) e o HubSpot é
atualizado logo depois (`hubspot_perfil_writeback_horario`, hh:41).
