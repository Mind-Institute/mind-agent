# Incidente Treble — rota, checkout e latência

Data: 04/09/2026

## Sintomas confirmados

- uma pessoa disse “Sou gestora” e foi enviada de B2C para B2B;
- ao pedir o link do VIP, o Agent reteve o checkout e pediu nome completo;
- o turno seguinte sobre o nome foi classificado como suporte e virou handoff;
- o Router consumiu mediana de 6,7 s, p90 de 8,9 s e falhou em 5 de 15 turnos
  observados nas 48 horas anteriores.

## Causa

1. O Router era chamado em todo turno, embora o canal seja predominantemente
   comercial B2C.
2. Prompt e runtime tratavam nome, e-mail, WhatsApp, empresa e cargo como
   pré-condição transacional.
3. O decisioning dizia simultaneamente “proteja o momentum” e “não entregue
   checkout antes do cadastro”.
4. O cargo foi usado pelo modelo como evidência de B2B, contrariando o próprio
   contrato: B2B/B2C classifica a compra atual, não a pessoa.

O lead do caso estava encontrado: pessoa, identidade de WhatsApp, nome da conversa
e contato no espelho do CRM existiam. O defeito foi interpretar sobrenome ausente
como impedimento para vender.

## Correção publicada

- PR #98 mergeada em `main` no commit
  `2581f6632339b4606f887d340b6c00821de9a3c5`;
- `treble-inbound-agent` v41, runtime interno `1.10.2`;
- `router_universal` ativo na v4;
- B2C é o padrão do canal comercial;
- para venda de ingressos, B2B exige ao mesmo tempo destino corporativo e mais
  de uma pessoa;
- cargo, empresa, pagamento corporativo de um único ingresso, quantidade sem
  destino corporativo ou potencial futuro não alteram uma compra individual;
- compras para casal, família ou amigos continuam B2C;
- destino corporativo sem quantidade volta ao Router para esclarecimento;
- patrocínio permanece B2B como demanda própria;
- suporte explícito continua usando o Router universal;
- checkout, preço, recomendação, proposta e calculadora não são mais bloqueados
  por cadastro;
- o estado legado `coleta_cadastro` é neutralizado antes de chegar ao modelo;
- `rota_origem` registra por que o turno foi B2C, B2B ou enviado ao Router.

## Provas da versão final

- 185/185 testes Edge;
- 17/17 casos específicos do classificador comercial;
- 15/15 verificações estáticas do runtime B2B;
- 76/76 contratos do guardrail de preço;
- migration do Router passou em `BEGIN/ROLLBACK` contra o prompt vivo e contém
  uma prova reversível de que somente o bloco B2B/B2C foi substituído;
- health vivo respondeu `{"ok":true,"service":"treble-inbound-agent","version":"1.10.2"}`;
- “Sou gestora e quero comprar um ingresso para mim” → `summit_b2c`,
  `router_ms=0`;
- “Minha empresa vai pagar meu ingresso” → `summit_b2c`;
- “Quero dois ingressos para mim e meu marido” → `summit_b2c`;
- “Quero 5 ingressos” → `summit_b2c`;
- “Quero comprar ingressos para minha empresa” → Router para esclarecer
  quantidade;
- “Quero comprar o VIP. Me manda o link agora” → checkout oficial rastreado,
  sem pergunta cadastral, 4,48 s;
- “Quero levar 5 pessoas da minha equipe” → `summit_b2b`, valores oficiais
  por volume e calculadora.

## Limite da prova

O smoke confirma o retorno HTTP do runtime. A confirmação de que a Treble exibiu a
mensagem no aparelho continua sendo um teste externo necessário antes da abertura.
