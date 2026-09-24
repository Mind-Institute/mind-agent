-- Contrato: intelligence.icp_por_cargo tolera erro de digitação só em nomes de cargo (24/09/2026).
-- Rodar no SQL Editor; qualquer linha com ok = false é quebra.
select caso, esperado, obtido, obtido is not distinct from esperado as ok
from (values
  ('dirrtor de departamento',                          'diretor_vp_nao_rh'),
  ('Diretorna de Inteligência de Mercado',             'diretor_vp_nao_rh'),
  ('direção',                                          'diretor_vp_nao_rh'),
  ('emoresaria',                                       'fundador_socio'),
  ('funder',                                           'fundador_socio'),
  ('coodenador',                                       'gestor_nao_rh'),
  ('Pscióloga',                                        'psicologo_saude'),
  -- profissões fora do vocabulário continuam "outros" (Adriana, 24/09)
  ('advogada',                                         'outros'),
  ('jornalista',                                       'outros'),
  -- falsos positivos que a primeira versão tinha
  ('Mediação',                                         'outros'),
  ('Arquiteta de marcas pessoais',                     'outros'),
  -- o que a regra já acertava não muda
  ('Gerente de RH',                                    'gestor_rh'),
  ('CEO',                                              'ceo_csuite')
) t(caso, esperado)
cross join lateral (select intelligence.icp_por_cargo(caso) obtido) r;
