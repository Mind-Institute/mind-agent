import { useEffect, useState } from 'react';
import {
  useForm,
  type DefaultValues,
  type FieldValues,
  type Resolver,
  type UseFormReturn,
} from 'react-hook-form';
import { codigoDoErro, type MapaRecursos, type NomeRecurso } from '@/contracts';
import { useArquivar, useAtualizar, useItem, usePublicar } from '@/hooks/use-recurso';

/* ============================================================
   EDIÇÃO DE UM REGISTRO
   ============================================================
   O mesmo ciclo em oito módulos: carregar, preencher o formulário,
   salvar com controle de concorrência, publicar, arquivar. Escrito uma
   vez para que "conflito de atualização" e "alterações não salvas"
   funcionem igual em todos — e não só naquele que alguém lembrou. */

export interface EdicaoRecurso<K extends NomeRecurso, TForm extends FieldValues> {
  registro: MapaRecursos[K] | undefined;
  carregando: boolean;
  erro: unknown;
  formulario: UseFormReturn<TForm>;
  sujo: boolean;
  salvando: boolean;
  salvo: boolean;
  conflito: boolean;
  fecharConflito: () => void;
  recarregar: () => void;
  salvar: (valores: TForm) => Promise<void>;
  publicar: () => Promise<void>;
  arquivar: () => Promise<void>;
}

export function useEdicaoRecurso<K extends NomeRecurso, TForm extends FieldValues>({
  recurso,
  id,
  resolver,
  padrao,
  paraFormulario,
  paraPayload,
  aoSalvar,
}: {
  recurso: K;
  id: string | undefined;
  resolver: Resolver<TForm>;
  padrao: DefaultValues<TForm>;
  paraFormulario: (registro: MapaRecursos[K]) => TForm;
  /** Converte os valores do formulário no formato do registro, quando
   *  os dois diferem (campo vazio que precisa virar `null`, por exemplo). */
  paraPayload?: (valores: TForm) => Partial<MapaRecursos[K]>;
  aoSalvar?: () => void;
}): EdicaoRecurso<K, TForm> {
  const consulta = useItem(recurso, id);
  const atualizar = useAtualizar(recurso);
  const publicarMut = usePublicar(recurso);
  const arquivarMut = useArquivar(recurso);

  const [conflito, setConflito] = useState(false);
  const [salvo, setSalvo] = useState(false);

  const formulario = useForm<TForm>({ resolver, defaultValues: padrao });
  const registro = consulta.data;

  useEffect(() => {
    if (registro) formulario.reset(paraFormulario(registro));
    else formulario.reset(padrao);
    setSalvo(false);
    // `formulario` e `padrao` são estáveis o bastante; reagir ao registro basta.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [registro]);

  /** Toda escrita manda o `atualizadoEm` que a tela viu.
   *  Nem todo recurso tem o campo (tema e auditoria não têm) — sem ele
   *  a escrita segue sem controle de concorrência, que é o correto
   *  para tabela que ninguém edita. */
  function opcoes() {
    const versionado = registro as { atualizadoEm?: string } | undefined;
    return { atualizadoEmEsperado: versionado?.atualizadoEm ?? null };
  }

  async function comConflito(acao: () => Promise<unknown>) {
    try {
      await acao();
      setSalvo(true);
      aoSalvar?.();
    } catch (erro) {
      if (codigoDoErro(erro) === 'conflito') setConflito(true);
      else throw erro;
    }
  }

  return {
    registro,
    carregando: consulta.isPending && Boolean(id),
    erro: consulta.error,
    formulario,
    sujo: formulario.formState.isDirty,
    salvando: atualizar.isPending || publicarMut.isPending || arquivarMut.isPending,
    salvo,
    conflito,
    fecharConflito: () => setConflito(false),
    recarregar: () => {
      setConflito(false);
      void consulta.refetch();
    },
    salvar: async (valores: TForm) => {
      if (!id) return;
      setSalvo(false);
      await comConflito(async () => {
        await atualizar.mutateAsync({
          id,
          payload: paraPayload
            ? paraPayload(valores)
            : (valores as unknown as Partial<MapaRecursos[K]>),
          opcoes: opcoes(),
        });
        formulario.reset(valores);
      });
    },
    publicar: async () => {
      if (!id) return;
      await comConflito(() => publicarMut.mutateAsync({ id, opcoes: opcoes() }));
    },
    arquivar: async () => {
      if (!id) return;
      await comConflito(() => arquivarMut.mutateAsync({ id, opcoes: opcoes() }));
    },
  };
}
