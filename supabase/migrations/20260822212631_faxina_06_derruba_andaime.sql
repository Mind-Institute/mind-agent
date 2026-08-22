-- Faxina passo 6: o andaime cai.
-- As views de compatibilidade existiam para que nenhuma sessao visse a tabela
-- sumida durante a mudanca. Agora que todas as funcoes foram reescritas e
-- testadas, elas saem. Se alguma coisa ainda lesse por elas, o DROP falha --
-- e' de proposito: melhor descobrir aqui do que pelo bot quebrado.

-- Seis funcoes ainda precisam da pessoa no formato antigo (nome inteiro,
-- telefone, idioma). Esse formato vira view de leitura com nome proprio, em
-- engagement, em vez de continuar sendo um resto de mind.
create view engagement.v_pessoa as
select p.id,
       (select i.identificador from engagement.identidades i
         where i.pessoa_id = p.id and i.canal = 'yazo' limit 1)        as yazo_id,
       nullif(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)), '') as nome,
       p.email,
       p.whatsapp                                                     as telefone,
       p.empresa,
       p.cargo,
       f.idioma,
       coalesce(f.anonimo, false)                                     as anonimo,
       p.sincronizado_em,
       p.criado_em,
       p.atualizado_em
from crm.pessoas p
left join engagement.pessoa_perfil f on f.pessoa_id = p.id;

comment on view engagement.v_pessoa is
  'A pessoa achatada para quem precisa de nome inteiro, telefone e idioma numa linha so. A verdade mora em crm.pessoas; idioma e anonimo em engagement.pessoa_perfil; yazo_id em engagement.identidades.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'mind_agent') then
    grant select on engagement.v_pessoa to mind_agent;
  end if;
end $$;

-- as 6 funcoes passam a ler a view nova
do $$
declare r record; v_def text;
begin
  for r in
    select p.oid from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
    where p.prokind='f' and l.lanname in ('sql','plpgsql')
      and n.nspname in ('public','api','concierge','treble','mind','crm')
      and pg_get_functiondef(p.oid) ~ '\mmind\.people\M'
  loop
    v_def := regexp_replace(pg_get_functiondef(r.oid), '\mmind\.people\M', 'engagement.v_pessoa', 'g');
    execute v_def;
  end loop;
end $$;

-- v_funil_valor tambem lia mind.people
drop view concierge.v_funil_valor;
create view concierge.v_funil_valor as
 select (select count(*) from engagement.v_pessoa where not v_pessoa.anonimo) as participantes,
    (select count(distinct o.participante_id) from intelligence.participante_objetivos o
      where o.status = 'ativo') as com_objetivo,
    (select count(distinct r.participante_id) from intelligence.recomendacoes r) as receberam_recomendacao,
    (select count(distinct r.participante_id) from intelligence.recomendacoes r
      where r.estado = any (array['aceita','agendada','compareceu'])) as aceitaram,
    (select count(distinct f.participante_id) from engagement.sessao_feedback f) as avaliaram,
    (select count(distinct s.participante_id) from intelligence.sinais_comerciais s
      where s.forca = any (array['media','alta'])) as com_sinal_comercial;

-- agora sim: todo o andaime cai
do $$
declare r record;
begin
  for r in
    select n.nspname as sch, c.relname as v
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'v'
      and n.nspname in ('mind','concierge')
      and obj_description(c.oid,'pg_class') like 'COMPATIBILIDADE%'
  loop
    execute format('drop view %I.%I', r.sch, r.v);
  end loop;
end $$;

comment on schema mind is
  'A EMPRESA Mind: posicionamento e politicas. O que e de produto mora na casa do produto (ver catalogo.produtos.schema_dados).';
