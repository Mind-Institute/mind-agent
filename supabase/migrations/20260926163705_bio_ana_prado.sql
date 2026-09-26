-- Adriana (26/09): bio de Ana Prado, palestrante de "Como incorporar a saúde mental à gestão de
-- equipes" (Arena LinkedIn, 16/09 12:30). Texto dela, sem edição, em quem_e.
update ecossistema.palestrantes_especialistas
   set quem_e = 'Formada em Comunicação Social e em Filosofia pela USP, tem 15 anos de experiência em redações e em empresas de tecnologia. É Community Manager do LinkedIn e lidera a frente de impacto social da empresa no Brasil.',
       atualizado_em = now()
 where slug = 'ana-prado'
   and quem_e is distinct from 'Formada em Comunicação Social e em Filosofia pela USP, tem 15 anos de experiência em redações e em empresas de tecnologia. É Community Manager do LinkedIn e lidera a frente de impacto social da empresa no Brasil.';
