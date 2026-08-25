-- comum -> ecossistema. O schema guarda o que é comum a todos os produtos da
-- Mind (palestrantes, especialistas, taxonomia, materiais). RENAME é troca de
-- catálogo: instantâneo, preserva dados; a table e a sequence seguem junto por
-- OID. As 12 funções que citavam comum.speakers/materiais/taxonomy já estavam
-- quebradas (essas tabelas foram apagadas antes) e serão reescritas na
-- reconstrução do ecossistema, apontando para os nomes finais.
alter schema comum rename to ecossistema;
