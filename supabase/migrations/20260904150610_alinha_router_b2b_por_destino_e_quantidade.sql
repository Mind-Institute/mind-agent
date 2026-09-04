-- Alinha o Router à decisão de produto: B2B de ingressos exige simultaneamente
-- destino corporativo e mais de um participante. O replace é exato e reversível
-- para provar que nenhuma outra parte do prompt foi alterada.

do $migration$
declare
  v_router text;
  v_antes text;
  v_bloco_antigo text := $antigo$
==================================================
SUMMIT_B2B
==================================================

Use `summit_b2b` quando o objeto atual é Mind Summit
e existe uma oportunidade corporativa real:

- empresa pagando;
- grupo/delegação;
- múltiplos participantes;
- negociação corporativa;
- patrocínio.

Empresa ou cargo da pessoa, sozinhos, NÃO tornam a oportunidade B2B.

O objeto comercial atual determina.

Exemplo:

"Quero levar minha equipe ao Summit."
→ summit_b2b


==================================================
SUMMIT_B2C
==================================================

Use `summit_b2c` quando o objeto atual é Mind Summit
e a pessoa está decidindo principalmente a própria participação.
$antigo$;
  v_bloco_novo text := $novo$
==================================================
SUMMIT_B2B
==================================================

Use `summit_b2b` para venda de ingressos do Mind Summit somente quando a
compra atual reúne AO MESMO TEMPO:

1. destino corporativo: os ingressos são para empresa, equipe ou delegação;
2. pluralidade: a compra envolve mais de uma pessoa.

Os dois sinais são obrigatórios. Não classifique como B2B usando isoladamente:

- cargo, senioridade, profissão ou empresa em que a pessoa trabalha;
- empresa pagando o único ingresso da própria pessoa;
- quantidade de dois ou mais ingressos sem destino corporativo;
- potencial de uma compra corporativa futura.

Compra de dois ou mais ingressos para casal, família ou amigos continua B2C.

Se existe destino corporativo, mas a quantidade ainda não está clara, não
presuma B2B. Devolva `rota=null`, `precisa_esclarecer=true` e candidatas
`summit_b2c` e `summit_b2b`, para perguntar quantas pessoas participarão.

Patrocínio é uma demanda corporativa própria e segue para `summit_b2b`
independentemente da quantidade de ingressos.

Exemplos:

"Sou gestora e quero um ingresso para mim."
→ summit_b2c

"Minha empresa vai pagar meu ingresso."
→ summit_b2c

"Quero dois ingressos para mim e meu marido."
→ summit_b2c

"Quero cinco ingressos para minha empresa."
→ summit_b2b

"Quero levar minha empresa ao Summit."
→ esclarecer a quantidade


==================================================
SUMMIT_B2C
==================================================

Use `summit_b2c` quando o objeto atual é Mind Summit e a compra não reúne
simultaneamente destino corporativo e mais de um participante. A pessoa pode
trabalhar em uma empresa, ocupar cargo de liderança ou ter o ingresso pago pela
empresa; se compra somente para si, continua B2C. Compras para casal, família
ou amigos também continuam B2C.
$novo$;
begin
  select conteudo
    into v_router
    from agentes.prompts
   where chave = 'router_universal'
     and ativo
   for update;

  if v_router is null then
    raise exception 'router_universal ativo ausente';
  end if;

  if (
    length(v_router) - length(replace(v_router, v_bloco_antigo, ''))
  ) / length(v_bloco_antigo) <> 1 then
    raise exception 'bloco B2B/B2C esperado não aparece exatamente uma vez';
  end if;

  v_antes := v_router;
  v_router := replace(v_router, v_bloco_antigo, v_bloco_novo);

  if replace(v_router, v_bloco_novo, v_bloco_antigo) is distinct from v_antes then
    raise exception 'a alteração extrapolou o bloco B2B/B2C';
  end if;

  if position('destino corporativo e mais de um participante' in v_router) = 0
     or position('empresa pagando o único ingresso' in v_router) = 0
     or position('quantidade de dois ou mais ingressos sem destino corporativo' in v_router) = 0
     or position('- empresa pagando;' in v_router) > 0 then
    raise exception 'regra B2B/B2C não foi reconciliada';
  end if;

  update agentes.prompts
     set conteudo = v_router,
         versao = versao + 1,
         atualizado_em = now()
   where chave = 'router_universal'
     and ativo;
end
$migration$;
