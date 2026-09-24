-- Contrato: intelligence.icp_por_cargo — digitação em nomes de cargo e profissões (24/09/2026).
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
  -- profissões viram contribuidor individual (Adriana, 24/09; REGRA_ICP_POR_CARGO.md)
  ('advogada',                                         'analista_nao_rh'),
  ('jornalista',                                       'analista_nao_rh'),
  ('engenheiro',                                       'analista_nao_rh'),
  ('Compliance Office',                                'analista_nao_rh'),
  ('Psicopedagoga',                                    'psicologo_saude'),
  ('profissional de educação física',                  'psicologo_saude'),
  ('Training Facilitator',                             'consultor_coach'),
  -- profissão com nível: o nível decide
  ('Diretora jurídica',                                'diretor_vp_nao_rh'),
  ('Gerente de marketing',                             'gestor_nao_rh'),
  -- "outros" é só para quem não escreveu um cargo
  ('suplente',                                         'outros'),
  ('aposentada',                                       'outros'),
  -- falsos positivos que a primeira versão tinha
  ('Mediação',                                         'outros'),
  ('Arquiteta de marcas pessoais',                     'analista_nao_rh'),
  -- o que a regra já acertava não muda
  ('Gerente de RH',                                    'gestor_rh'),
  ('CEO',                                              'ceo_csuite')
) t(caso, esperado)
cross join lateral (select intelligence.icp_por_cargo(caso) obtido) r;
