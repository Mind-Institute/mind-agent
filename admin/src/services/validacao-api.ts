import { z } from 'zod';
import {
  AdminApiError,
  espacoSchema,
  eventoSchema,
  palestranteSchema,
  sessaoSchema,
  temaSchema,
  type ListResult,
  type MapaRecursos,
  type NomeRecurso,
} from '@/contracts';

/* ============================================================
   VALIDAÇÃO DAS RESPOSTAS REAIS
   ============================================================
   Esta camada substituiu a antiga "normalização", que preenchia campo
   ausente com o vazio do tipo — e, com isso, escondia quebra de
   contrato. Um `id` que virava `''` só aparecia depois, como registro
   que não abre; um `atualizadoEm` que virava `''` derrubava o controle
   de concorrência sem ninguém notar.

   Agora a resposta é conferida contra o schema Zod do recurso:

   - campo OBRIGATÓRIO ausente derruba a leitura com erro de contrato
     (`id`, `atualizadoEm`, `titulo`, `nome`, `dia`, `tipo`…);
   - campo REALMENTE OPCIONAL usa o default declarado no schema, que
     está anotado lá com o motivo;
   - CATEGORIA DESCONHECIDA passa intacta: `tipo` e `formato` são
     `string`, não enum, e a tela mostra o código cru (ver
     `src/lib/rotulos.ts`). O painel prefere exibir `mesa_redonda` a
     traduzir para `palestra`.

   O erro NUNCA carrega o corpo da resposta — só o caminho do campo e o
   tipo do problema. Nada aqui é escrito no console. */

/** Recursos servidos pela API real. Os demais passam sem validação. */
const SCHEMAS = {
  event: eventoSchema,
  sessions: sessaoSchema,
  speakers: palestranteSchema,
  spaces: espacoSchema,
  themes: temaSchema,
} as const satisfies Partial<Record<NomeRecurso, z.ZodTypeAny>>;

type RecursoValidado = keyof typeof SCHEMAS;

function temSchema(resource: NomeRecurso): resource is RecursoValidado {
  return resource in SCHEMAS;
}

/** Envelope de listagem, no formato que a Edge Function devolve. */
const envelopeSchema = z.object({
  itens: z.array(z.unknown()),
  total: z.number(),
  pagina: z.number(),
  porPagina: z.number(),
});

/** Limite de problemas relatados — 67 sessões quebradas dariam 67×N. */
const MAX_PROBLEMAS = 8;

/**
 * Descreve um problema pelo CAMINHO e pelo TIPO, nunca pelo valor.
 *
 * `invalid_type` pode citar `received` porque ali ele é o nome do tipo
 * ('undefined', 'null', 'number'), não o dado. Em enum o `received` é o
 * valor recebido — esse fica de fora.
 */
function descrever(problema: z.ZodIssue): string {
  const caminho = problema.path.length > 0 ? problema.path.join('.') : '(raiz)';
  if (problema.code === 'invalid_type') {
    return `${caminho}: esperado ${problema.expected}, veio ${problema.received}`;
  }
  if (problema.code === 'invalid_enum_value') {
    return `${caminho}: valor fora do conjunto aceito`;
  }
  if (problema.code === 'too_small') {
    return `${caminho}: vazio ou ausente`;
  }
  return `${caminho}: ${problema.code}`;
}

function erroDeContrato(onde: string, erro: z.ZodError): AdminApiError {
  const problemas = erro.issues.map(descrever);
  const mostrados = problemas.slice(0, MAX_PROBLEMAS);
  const restantes = problemas.length - mostrados.length;
  if (restantes > 0) mostrados.push(`… e outros ${restantes} problema(s)`);

  return new AdminApiError(
    'desconhecido',
    `Contrato incompatível em ${onde}: a resposta não tem o formato que o painel espera.`,
    { detalhes: mostrados },
  );
}

function caminhoDe(resource: NomeRecurso, id?: string): string {
  return id ? `GET /admin/${resource}/${id}` : `/admin/${resource}`;
}

/**
 * Valida um registro. Recurso sem schema (modo `http` para os módulos
 * que ainda não têm contrato fechado) passa sem conferência.
 */
export function validarRegistro<K extends NomeRecurso>(
  resource: K,
  bruto: unknown,
  onde = caminhoDe(resource),
): MapaRecursos[K] {
  if (!temSchema(resource)) return bruto as MapaRecursos[K];

  const analise = SCHEMAS[resource].safeParse(bruto);
  if (!analise.success) throw erroDeContrato(onde, analise.error);
  return analise.data as MapaRecursos[K];
}

/** Valida o envelope `ListResult` e cada item dentro dele. */
export function validarLista<K extends NomeRecurso>(
  resource: K,
  resposta: unknown,
  onde = caminhoDe(resource),
): ListResult<MapaRecursos[K]> {
  const envelope = envelopeSchema.safeParse(resposta);
  if (!envelope.success) throw erroDeContrato(onde, envelope.error);

  if (!temSchema(resource)) {
    return {
      ...envelope.data,
      itens: envelope.data.itens as MapaRecursos[K][],
    };
  }

  const schema = SCHEMAS[resource];
  const itens: MapaRecursos[K][] = [];
  const problemas: z.ZodIssue[] = [];

  envelope.data.itens.forEach((item, indice) => {
    const analise = schema.safeParse(item);
    if (analise.success) {
      itens.push(analise.data as MapaRecursos[K]);
      return;
    }
    /* O índice entra no caminho para dizer QUAL registro quebrou —
       sem revelar o conteúdo dele. */
    for (const problema of analise.error.issues) {
      problemas.push({ ...problema, path: ['itens', indice, ...problema.path] });
    }
  });

  if (problemas.length > 0) {
    throw erroDeContrato(onde, new z.ZodError(problemas));
  }

  return { ...envelope.data, itens };
}
