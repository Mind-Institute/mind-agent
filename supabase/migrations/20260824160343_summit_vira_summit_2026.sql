-- Cada edição do Summit é uma casa própria. "summit" na verdade só guarda o
-- Mind Summit 2026 (um único evento em summit.events). Passa a se chamar pelo
-- que é. ALTER SCHEMA RENAME é troca de catálogo: instantâneo, preserva dados;
-- tabelas, FKs e views internas seguem por OID. Só o corpo das funções que citam
-- "summit." (texto) precisa ser reescrito depois — as edge functions chamam RPC
-- em public e serão ajustadas na sequência.
alter schema summit rename to summit_2026;

-- O ponteiro que a busca usa para resolver a casa do produto acompanha o nome.
-- linha continua 'summit' (a linha de produto); schema_dados é a casa por edição.
update catalogo.produtos set schema_dados = 'summit_2026' where codigo = 'mind-summit-2026';
-- 2025 é edição passada, sem dados carregados. Aponta para a casa futura dela
-- (summit_2025 nasce quando o histórico entrar), não para a do 2026.
update catalogo.produtos set schema_dados = 'summit_2025' where codigo = 'mind-summit-2025';
