-- Qual pipeline trata cada produto. Adriana confirmou em 23/08: o Summit vende no
-- "Pipeline de vendas - Summit" (917379159). O pipeline `default` ("Vendas Historicas
-- Mind Summit", 7.092 negocios) e historico e NAO entra aqui de proposito: negocio
-- fechado nao e lugar de procurar negocio aberto.
update catalogo.produtos
   set pipeline_hubspot = '917379159'
 where codigo = 'mind-summit-2026';
