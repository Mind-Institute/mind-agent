-- Adriana (26/09): bio de Ricardo Souza, palestrante de "Sobreviver sem destruir o time" (Arena
-- LinkedIn, 17/09 15:00). Texto dela, sem edição, em quem_e — substitui a bio do site gravada em
-- 20260926175901.
update ecossistema.palestrantes_especialistas
   set quem_e = 'Ricardo Souza é empreendedor e um dos fundadores do Grupo Movile, empresa por trás de grandes histórias de sucesso como iFood, Sympla, PlayKids e Leitura. Construiu sua trajetória liderando pessoas e negócios em cenários de crescimento acelerado, decisões complexas e alta pressão — sempre com o fator humano no centro dos resultados. Hoje, é fundador da BÜ, criadora do Maker, um sistema operacional empresarial com inteligência artificial. Para Ricardo, a tecnologia não substitui pessoas: amplia sua capacidade de pensar, decidir e realizar.',
       atualizado_em = now()
 where slug = 'ricardo-souza'
   and quem_e is distinct from 'Ricardo Souza é empreendedor e um dos fundadores do Grupo Movile, empresa por trás de grandes histórias de sucesso como iFood, Sympla, PlayKids e Leitura. Construiu sua trajetória liderando pessoas e negócios em cenários de crescimento acelerado, decisões complexas e alta pressão — sempre com o fator humano no centro dos resultados. Hoje, é fundador da BÜ, criadora do Maker, um sistema operacional empresarial com inteligência artificial. Para Ricardo, a tecnologia não substitui pessoas: amplia sua capacidade de pensar, decidir e realizar.';
