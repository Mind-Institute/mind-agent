-- O AVISO DA RHINO GANHA ÍCONE DE CARRO (pedido da Adriana, 03/09).
--
-- O conjunto de ícones dos avisos é fechado dos dois lados: o banco só aceita nomes da lista
-- (`avisos_icone_valido`) e o App/painel desenham cada nome em SVG (`ICO_POR_NOME` em
-- home/estado.js; `ICONES_AVISO` no painel). Aqui entra o nome `carro`; o glifo entra no App e
-- no painel no mesmo commit. A troca do ícone do aviso vem por último, para o App já saber
-- desenhá-lo quando o banco passar a pedi-lo — nome desconhecido cai no megafone.
alter table concierge.avisos drop constraint if exists avisos_icone_valido;
alter table concierge.avisos add constraint avisos_icone_valido
  check (icone = any (array['megafone','lugar','relogio','sino','ingresso','fone','agenda','alerta','estrela','carro']));

update concierge.avisos set icone = 'carro', atualizado_em = now()
where chave = 'rhino' and icone <> 'carro';
