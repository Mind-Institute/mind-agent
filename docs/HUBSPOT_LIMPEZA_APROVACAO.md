# HubSpot — limpeza e correções para aprovar (passos 6 e 10)

Status: **aguardando aprovação da Adriana.** O lado do banco (pessoas.pessoas) já foi limpo e auditado
(`mind_admin_audit`, resources `pessoas_email_typo`, `pessoas_empresa_dominio`, `pessoas_empresa_sujeira`,
`pessoas_cargo_hubspot`, `pessoas_icp_hubspot`). A ferramenta do HubSpot pede confirmação a cada escrita, por
isso tudo o que mexe no HubSpot está reunido aqui.

## Já feito no HubSpot (rotinas aprovadas)

- 143 companies sem nome (criadas pelo próprio HubSpot a partir do domínio do e-mail) ganharam nome; 13 delas
  tiveram o domínio corrigido (typo/subdomínio). 4 companies novas criadas. Nenhuma duplicata criada.
- 529 contatos sem company foram associados à company da sua empresa (só aditivo).

## Para aprovar

### 1. Companies com domínio de provedor de e-mail — **o mais urgente**
O HubSpot associa automaticamente todo contato novo daquele provedor à company. Proposta: **apagar o domínio**
(a company fica) e **tirar a associação** dos contatos que não são dela.

| Company | Domínio errado | Contatos | Negócios |
|---|---|---|---|
| Ecossistema do Futuro | gmail.com | 45 | 68 |
| Buyticket | hotmail.com | 22 | 29 |
| CMO Consult | yahoo.com.br | 7 | 8 |
| Alissa joalheria | icloud.com | 3 | 5 |
| Arche Método e Estratégia | outlook.com | 1 | 1 |
| Apple Computer Brasil | mac.com (→ apple.com) | 1 | 1 |
| Pipol | live.com | 1 | 1 |
| university of London in Dubai | uol.com | 1 | 0 |

Nenhum desses contatos tem a empresa confirmada por outra fonte (credenciamento ou campo empresa).
Em pessoas.pessoas a empresa dessas 81 pessoas já foi apagada.

### 2. Companies-sujeira para arquivar (15)
Criadas pelo HubSpot a partir de e-mail pessoal ou com typo: Terra, Uol, Ig, Gmail (gmail.com.br), gmai.com,
Gamil, Outly, e 8 sem nome (msn.com.br, yahoo.ca, gmail.br, hormail.com, gnail.com, icour.com, gmal.com,
icourd.com). Arquivar é reversível por 90 dias.

### 3. Renomear companies (6)
| Hoje | Passa a ser |
|---|---|
| Sp (ima.sp.gov.br) | IMA - Informática de Municípios Associados |
| Vb (vb.com.br) | VB Serviços |
| Zf (zf.com) | ZF Group |
| UOL (moveer.com.br) | Moveer |
| São Paulo (sp.gov.br) | Governo do Estado de São Paulo |
| Curitiba (curitiba.pr.gov.br) | Prefeitura de Curitiba |

### 4. Campo "Empresa" do contato com sujeira (~115 contatos)
Apagar o texto: "Gmail" (67), "Autônoma/Autônomo" (25), "Teste" (7), "." / ".." / "-" (7), "n/a" / "NA",
"Nenhuma", "Sem Empresa", "Particular".

### 5. E-mails com typo (18 contatos)
E-mail corrigido vira o primário; o com typo fica como secundário. Ex.: gmail.com.br → gmail.com,
hormail.com → hotmail.com, boehringr-ingelheim.com → boehringer-ingelheim.com, medic360.com.bt → medic360.com.br.
Lista completa: `mind_admin_audit` resource `pessoas_email_typo`.
Outras 20 pessoas com typo já têm o e-mail certo em outro cadastro: são duplicatas (passo 11/12).

### 6. Criar contatos que faltam (~190)
Pessoas com e-mail em pessoas.pessoas que não existem no HubSpot: ~114 compradores da EF (2023–2025),
~63 do credenciamento 2026, ~10 do bot. Observação: contato novo pode contar como contato de marketing
no plano do HubSpot. Proposta: criar como **não-marketing**.

### 7. Cadastros de teste/sistema (31) — apagar
E-mails @example.com, @teste.com.br, *.invalid, *.test, notificações (Notion, Miro, Wix, Facebook),
dicionario.priberam.org etc. Nenhum tem ingresso. Apagar em pessoas.pessoas e no HubSpot (irreversível no banco).


### 8. Contatos duplicados no HubSpot (passo 12) — 270 pares
São pessoas que já juntei em pessoas.pessoas (passo 11, critérios no relatório de duplicatas) e que ainda
têm dois contatos no HubSpot. Merge no HubSpot **não tem desfazer**; antes de cada um eu guardo todas as
propriedades dos dois contatos no banco, para recriar se for preciso.
- Principal: o contato com **e-mail corporativo** (139 pares têm um corporativo e um pessoal); o e-mail pessoal
  vira secundário. Com dois corporativos (60) ou dois pessoais (48), fica o contato com mais negócios/atividade.
- A ferramenta do HubSpot desta conversa não faz merge; é preciso uma rotina (edge function) que chame a API de
  merge. Da vez anterior o sistema de permissões bloqueou a criação dela; com o seu OK explícito eu tento de novo.
  Alternativa: você faz o merge pela tela do HubSpot a partir da lista.

### 9. Passos 16–18 (por último, depois da limpeza)
Mapeado no HubSpot (contato):
- Passo 16: `Summit – Participação Anual` (2023–2027), `Summit – Tipo de Entrada (2023/2024/2025/2026)`
  (Pago, Cortesia, Bonus, Patrocínio), `Summit – Cortesia (Anos)`, `Summit – Patrocínio (Anos)`,
  `Summit – Instituição Concessora (ano)`, `Summit – Categorias (todos os anos)`. Categoria por ano só existe para
  2026 → **criar `Summit – Categoria do Ingresso (2024)` e `(2025)`** (mesmas opções: Mind, VIP, Prime, Camarote).
- Passo 17: `Institute Formações Cursadas` (F1, F2, F3, Certificação, Mind Journey, Oxford no Conselho),
  `Certificação Liderança Positiva Comprada?`, `Mind Institute – Turmas`, `Journey – Turma (Ano)`.
- Passo 18 (turma 2027): acrescentar opções com o ano na frente, ex. "2027 · Turma 1", em `Mind Institute – Turmas`
  e nos produtos; `Journey – Turma (Ano)` já tem 2027. Criar opção/propriedade é mudança de estrutura no HubSpot.

## Como responder
"Aprovo 1 a 9", ou os números que aprova. Posso também seguir sem pedir confirmação a cada lote do HubSpot
nesta conversa, se preferir.
