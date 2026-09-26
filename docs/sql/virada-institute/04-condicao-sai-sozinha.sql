-- A CONDIÇÃO SUMMIT SAI SOZINHA ÀS 23H59 DE 30/09: OS 4 TEXTOS E AS 4 PERGUNTAS DO FAQ QUE FALAM DELA.
--
-- É a pergunta (a) da virada: só roda com o OK da Adriana. RASCUNHO, como os outros desta pasta. Não depende da
-- virada: funciona antes e depois dela.
--
-- As 5 ofertas da condição saem sozinhas da porta de preços às 23h59 de 30/09 (depois da virada, api.ofertas só
-- entrega o que está valendo). Os textos (institute.condicoes) e o FAQ (institute.faq) não têm prazo, só liga e
-- desliga. Sem isto, depois das 23h59 o site e o agente continuam falando da condição, e duas respostas do FAQ
-- mostram "—" no lugar do preço e do prazo.
--
-- institute.condicao_summit_sai(p_agora) desliga os 4 textos e as 4 perguntas quando nenhuma das 5 ofertas da
-- condição vale mais. Se alguma foi prorrogada no painel, ela não mexe em nada.
-- Um agendamento chama a função de minuto em minuto, de 02h00 a 03h59 UTC de 01/10 (23h00 às 00h59 de Brasília),
-- e se apaga sozinho:
--   · depois de agir, às 23h59 de Brasília, quando a condição termina;
--   · ou às 03h59 UTC sem agir, se a condição foi prorrogada; aí os textos ficam, e a prorrogação decide de novo.
-- O relógio do agendador é UTC. Ele também não tem ano: por isso se apaga, senão rodaria de novo em 01/10/2027.
-- Se este arquivo entrar depois da hora, age na hora.
--
-- Das 4 perguntas, as 3 primeiras continuam boas perguntas. Quando ela mandar o texto novo, elas entram aqui como
-- linhas novas, desligadas, e a função as liga no mesmo minuto.

create function institute.condicao_summit_sai(p_agora timestamptz default now())
returns boolean
language plpgsql
set search_path to 'pg_catalog', 'public'
as $fn$
begin
  -- Alguma oferta da condição ainda vale? Então nada muda.
  if exists (
    select 1 from api.ofertas o
     where o.codigo in ('cert-gestao-estrategica', 'cert-lideranca-positiva-summit', 'lideranca-consciente-avulsa',
                        'seguranca-psicologica-avulsa', 'significado-proposito-avulsa')
       and p_agora >= coalesce(o.inicia_em, '-infinity'::timestamptz)
       and p_agora <= coalesce(o.encerra_em, 'infinity'::timestamptz)
  ) then
    return false;
  end if;

  update institute.condicoes
     set ativo = false, atualizado_em = p_agora
   where chave in ('oferta.condicao-summit', 'oferta.duas-faixas', 'oferta.journey-e-bonus', 'oferta.prazo')
     and ativo;
  update institute.faq
     set ativo = false
   where escopo = 'certificacao-lideranca-positiva'
     and pergunta in ('Posso fazer somente uma formação?', 'O Journey está incluído na formação avulsa?',
                      'O Unpacking é uma aula da Certificação?', 'Qual ingresso recebo?')
     and ativo;
  return true;
end;
$fn$;
revoke all on function institute.condicao_summit_sai(timestamptz) from public, anon, authenticated, service_role;

-- O que ela desliga existe, e está ligado agora.
do $$
begin
  if (select count(*) from institute.condicoes
       where chave in ('oferta.condicao-summit', 'oferta.duas-faixas', 'oferta.journey-e-bonus', 'oferta.prazo')) <> 4
     or (select count(*) from institute.faq
          where escopo = 'certificacao-lideranca-positiva'
            and pergunta in ('Posso fazer somente uma formação?', 'O Journey está incluído na formação avulsa?',
                             'O Unpacking é uma aula da Certificação?', 'Qual ingresso recebo?')) <> 4 then
    raise exception 'condição: esperava 4 textos e 4 perguntas do FAQ';
  end if;
end $$;

select cron.schedule(
  'condicao-summit-2026-sai',
  '* 2-3 1 10 *',
  $cron$
    select case
             when institute.condicao_summit_sai() then cron.unschedule('condicao-summit-2026-sai')
             when now() >= '2026-10-01 03:59:00+00'::timestamptz then cron.unschedule('condicao-summit-2026-sai')
           end;
  $cron$
);

-- Entrou depois da hora? Age agora e apaga o agendamento.
select case when institute.condicao_summit_sai() then cron.unschedule('condicao-summit-2026-sai') end;
