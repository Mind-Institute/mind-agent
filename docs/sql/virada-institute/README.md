# Virada do Institute para o catálogo (Passo 5)

O pacote do Passo 5 de [`docs/PLANO_OFERTAS_PASSO_A_PASSO.md`](../../PLANO_OFERTAS_PASSO_A_PASSO.md). Em 27/09 a Adriana aprovou e ficou com o sinal da hora ("você dá o sinal, eu aplico"): **nada daqui roda antes de ela escrever "pode virar"**. Os arquivos ficam aqui, fora de `supabase/migrations/`, para nenhuma integração os aplicar antes.

| Arquivo | O que é |
|---|---|
| [`01-virada.sql`](01-virada.sql) | A virada, numa transação só. Carrega as 16 ofertas do Institute no catálogo, põe as 3 funções de pedido e as 3 portas do site para ler o catálogo e congela a casa antiga. Confere a paridade antes e depois. Roda no sinal da Adriana. |
| [`02-volta.sql`](02-volta.sql) | A volta, só para emergência. Primeiro copia para a casa antiga o que foi mudado no painel, depois devolve as portas e as funções. |
| [`03-bump-fora-da-lista.sql`](03-bump-fora-da-lista.sql) | Aprovado pela Adriana em 27/09 ("1 - sim"): roda logo depois da virada, no mesmo sinal, antes de 30/09 23h59. Em `api.ofertas`, o bump passa a vir sem programa: ele sai das listas de preço por programa (a "Avulsas" deixa de mostrar R$ 1.497 na Liderança Consciente) e continua funcionando no checkout próprio. |
| ~~`04-condicao-sai-sozinha.sql`~~ **Aplicado em 27/09** (OK da Adriana, "2- sim"): [`supabase/migrations/20260927133341_condicao_summit_sai_sozinha.sql`](../../../supabase/migrations/20260927133341_condicao_summit_sai_sozinha.sql). Os 4 textos e as 4 perguntas do FAQ da Condição Summit saem sozinhos às 23h59 de 30/09, quando a última das 5 condições termina. Se ela prorrogar uma condição no painel, eles ficam. O agendamento se apaga sozinho. |
| [`../../../tests/virada_institute_contract.sql`](../../../tests/virada_institute_contract.sql) | O contrato de depois da virada. Termina em `VIRADA_OK`. |

## No sinal ("pode virar")

A parte que muda o site (passos 1 a 4) leva uns 2 minutos; o site só sente a troca das portas dentro de cada migration, menos de 0,2 s no ensaio F. O resto vem logo depois.

1. Aplicar `01-virada.sql` com `apply_migration`, com o nome `virada_institute_le_o_catalogo` e o conteúdo exato do arquivo. Se qualquer conferência falhar, nada acontece e o site segue como está.
2. Logo depois, aplicar `03-bump-fora-da-lista.sql`, com o nome `bump_fora_da_lista_de_precos`.
3. Rodar no banco real, cada um desfeito no fim:
   - `tests/virada_institute_contract.sql`, que termina em `VIRADA_OK`;
   - `tests/ofertas_edicao_contract.sql`, que termina em `OFERTAS_EDICAO_OK` e vale antes e depois da virada.
4. Conferir pela porta real, fora da transação: `api.ofertas` com as mesmas ofertas de antes e os bumps sem programa; `api.bump_regras` e `api.oferta_inclui` iguais.
5. Mover `01` e `03` para `supabase/migrations/` com a versão do registro de cada um e o md5 igual ao do registro. O `02-volta.sql` fica aqui, para emergência.
6. Trocar o aviso da tela Ofertas do painel (`aviso-virada`, em `admin/src/pages/ofertas.tsx`) e o teste dele, e rodar os testes e o build do painel. O texto novo, já testado em 27/09:
   > As ofertas do Institute moram aqui: desde a virada, o site do Institute lê o `catalogo`, e o que você põe no ar aparece nele no horário da oferta. A casa antiga (`institute.ofertas`) ficou congelada: o /admin do Join não edita mais ofertas nem bumps. Nos outros produtos, "pôr no ar" segue travado até um site ler o `catalogo`. O selo **no site** marca o preço que o site lê agora. Cada oferta guarda o histórico de alterações.
7. PR e merge; registrar no checkpoint e avisar a lane #40, porque o agente do Institute lê essas portas.

Se algo der errado depois da virada: `02-volta.sql`, só com o OK da Adriana.

## Ensaios no banco real (desfeitos no fim, sem rastro)

| Quando | Ensaio | Resultado |
|---|---|---|
| 26/09 | **A.** A virada inteira, com as portas trocadas em cópias temporárias; o site não espera nada. | `ENSAIO_A_OK`: api.ofertas 14 = 14, api.bump_regras 5 = 5, api.oferta_inclui 8 = 8; carga 16 ofertas, 15 preços, 8 bônus, 5 exigências; funções iguais fora a troca do nome; 64 ms |
| 26/09 | **B.** A virada, cinco edições no painel e a volta: preço editado, bônus novo, oferta nova com 2 produtos, bump novo e bump tirado do ar. Um rascunho fica de fora. | `ENSAIO_B_OK`: depois da volta, as portas da casa antiga iguais às do catálogo (16/5/9); a casa antiga com 19 ofertas, 9 bônus e 6 regras; o rascunho não foi |
| 26/09 | Contrato do Passo 4, antes da virada | `OFERTAS_EDICAO_OK` |
| 26/09 | **C.** A troca real das portas, com os 2 contratos e a volta na mesma transação. O site lê a porta de preços num ritmo constante, cerca de 250 vezes por hora, dia e noite; não há horário mais quieto. | `ENSAIO_C_OK`: virada com paridade, `VIRADA_OK`, `OFERTAS_EDICAO_OK` no modo de depois da virada e a volta com paridade, incluindo tudo o que os contratos criaram. As portas ficaram presas 1.053 ms no total: a virada e o contrato dela 476 ms, o contrato do Passo 4 495 ms, a volta o resto. Na virada de verdade só a troca e a conferência seguram as portas: menos de 0,1 s, como no ensaio A. Nenhuma leitura do site falhou. Sem rastro. |
| 26/09 | **D.** A virada, o `03-bump-fora-da-lista.sql` e a volta, com as portas reais. | `ENSAIO_D_OK`: os 3 bumps saíram sem programa de `api.ofertas` (fora das listas por programa, como a "Avulsas"); as outras portas e o bloco do agente iguais; a volta, que agora ignora o programa do bump na comparação, fechou em 14/5/8. Portas presas 250 ms no total. Sem rastro. |
| 26/09 | **E.** O `04-condicao-sai-sozinha.sql`. | `ENSAIO_E_OK`: agendamento de minuto em minuto das 02h00 às 03h59 UTC de 01/10; antes do fim da condição nada muda; às 02h59 UTC (23h59 de Brasília) os 4 textos e as 4 perguntas saem e o bloco do agente para de receber a condição; a função fica fechada para fora. Sem rastro. |
| 27/09 | **F.** O pacote do sinal: a virada e o bump com o texto aprovado, a Condição Summit (já aplicada) e os 2 contratos, com as portas reais, numa transação que não podia gravar. | `ENSAIO_F_OK`: virada e bump em 162 ms; a Condição Summit continua saindo só depois da hora; `VIRADA_OK`, que agora também confere o bump sem programa na porta de preços, e `OFERTAS_EDICAO_OK` no modo de depois da virada. As portas ficaram presas 1.239 ms, por causa dos contratos, que no sinal rodam fora da virada. Sem rastro. |
