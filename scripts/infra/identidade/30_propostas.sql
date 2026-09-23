-- 30 — fase B: a fila de duplicatas que a fase A propôs. Só leitura.

-- 30.1 — quantas por padrão e confiança. "alta" pode ser aprovada em bloco no 40;
--        "media" e "baixa" só linha a linha.
select padrao, proposta->>'confianca' as confianca, count(*) as propostas
  from engagement.identidade_fusoes
 where status = 'pendente' and proposta is not null
 group by 1, 2
 order by 1, 2;

-- 30.2 — o detalhe de um padrão (troque o nome). Quem sobrevive, quem é absorvida,
--        e o que cada lado tem, para decidir com os olhos.
select f.id as pendencia, f.padrao, f.proposta->>'confianca' as confianca, f.proposta->>'motivo' as motivo,
       s.primeiro_nome || ' ' || coalesce(s.sobrenome, '') as sobrevive_nome, s.email as sobrevive_email, s.whatsapp as sobrevive_whatsapp, s.canais as sobrevive_canais,
       a.primeiro_nome || ' ' || coalesce(a.sobrenome, '') as absorvida_nome, a.email as absorvida_email, a.whatsapp as absorvida_whatsapp, a.canais as absorvida_canais
  from engagement.identidade_fusoes f
  join pessoas.v_pessoa_360 s on s.pessoa_id = (f.proposta->>'sobrevive')::uuid
  join pessoas.v_pessoa_360 a on a.pessoa_id = (f.proposta->>'absorvida')::uuid
 where f.status = 'pendente' and f.padrao = 'mesmo_telefone_emails_diferentes'   -- <- troque aqui
 order by f.criado_em
 limit 200;

-- 30.3 — pendências antigas (anteriores a D5) que ainda não têm proposta: a fase A
--        dá proposta às que reencontrar; as que sobrarem aqui pedem olhar humano.
select tipo, count(*) from engagement.identidade_fusoes where status = 'pendente' and proposta is null group by 1;
