import {
  ROTULO_STATUS_EDITORIAL,
  ROTULO_STATUS_INDEXACAO,
  type StatusEditorial,
  type StatusIndexacao,
} from '@/contracts';
import { Badge } from '@/components/ui/badge';

/* Selos de estado. Cor é significado, não decoração:
   verde = no ar; âmbar = esperando gente; coral = quebrado. */

const VARIANTE_EDITORIAL: Record<StatusEditorial, 'sucesso' | 'atencao' | 'neutro' | 'outline'> = {
  publicado: 'sucesso',
  em_revisao: 'atencao',
  rascunho: 'outline',
  arquivado: 'neutro',
};

export function SeloEditorial({ status }: { status: StatusEditorial }) {
  return <Badge variant={VARIANTE_EDITORIAL[status]}>{ROTULO_STATUS_EDITORIAL[status]}</Badge>;
}

const VARIANTE_INDEXACAO: Record<
  StatusIndexacao,
  'sucesso' | 'atencao' | 'neutro' | 'destructive' | 'outline'
> = {
  indexado: 'sucesso',
  na_fila: 'atencao',
  indexando: 'atencao',
  nao_indexado: 'outline',
  desatualizado: 'atencao',
  erro: 'destructive',
};

export function SeloIndexacao({ status }: { status: StatusIndexacao }) {
  return <Badge variant={VARIANTE_INDEXACAO[status]}>{ROTULO_STATUS_INDEXACAO[status]}</Badge>;
}

export function SeloAtivo({ ativo }: { ativo: boolean }) {
  return <Badge variant={ativo ? 'sucesso' : 'neutro'}>{ativo ? 'Ativo' : 'Inativo'}</Badge>;
}

/** Lista curta de campos faltantes, do jeito que a listagem mostra. */
export function SeloFaltando({ campos }: { campos: string[] }) {
  if (campos.length === 0) return null;
  return (
    <Badge variant="atencao" title={`Faltando: ${campos.join(', ')}`}>
      falta {campos.join(', ')}
    </Badge>
  );
}
