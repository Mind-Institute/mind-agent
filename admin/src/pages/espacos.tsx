import { useNavigate, useParams } from 'react-router-dom';
import { MessageSquareQuote } from 'lucide-react';
import { ROTULO_TIPO_ESPACO, TIPOS_ESPACO, type Espaco } from '@/contracts';
import { camposFaltantesDoEspaco, ehPalco } from '@/lib/pendencias';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { SeloAtivo, SeloFaltando } from '@/components/admin/selos';
import { EstadoVazio } from '@/components/admin/estados';
import { DrawerEspaco } from '@/features/espacos/drawer-espaco';
import { Badge } from '@/components/ui/badge';

export function PaginaEspacos() {
  const { id } = useParams();
  const navegar = useNavigate();

  const colunas: Coluna<Espaco>[] = [
    {
      chave: 'nome',
      cabecalho: 'Espaço',
      celula: (e) => (
        <div className="min-w-48">
          <p className="font-semibold">{e.nome}</p>
          <p className="font-mono text-xs text-muted-foreground">{e.slug}</p>
        </div>
      ),
    },
    {
      chave: 'tipo',
      cabecalho: 'Tipo',
      celula: (e) => <Badge variant="outline">{ROTULO_TIPO_ESPACO[e.tipo]}</Badge>,
    },
    {
      /* Aliases têm coluna própria: é por eles que o agente encontra o
         lugar quando alguém usa o apelido em vez do nome oficial. */
      chave: 'aliases',
      cabecalho: 'Aliases',
      celula: (e) =>
        e.aliases.length === 0 ? (
          <Badge variant={ehPalco(e) ? 'destructive' : 'neutro'}>
            {ehPalco(e) ? 'palco sem alias' : 'nenhum'}
          </Badge>
        ) : (
          <ul className="flex max-w-72 flex-wrap gap-1">
            {e.aliases.map((alias) => (
              <li key={alias}>
                <Badge variant="secondary" className="gap-1">
                  <MessageSquareQuote className="size-3" />
                  {alias}
                </Badge>
              </li>
            ))}
          </ul>
        ),
    },
    {
      chave: 'comoChegar',
      cabecalho: 'Como chegar',
      celula: (e) =>
        e.comoChegar ? (
          <p className="line-clamp-2 max-w-72 text-xs text-muted-foreground">{e.comoChegar}</p>
        ) : (
          <Badge variant="destructive">sem instrução</Badge>
        ),
    },
    {
      chave: 'pendencias',
      cabecalho: 'Pendências',
      celula: (e) => {
        const faltando = camposFaltantesDoEspaco(e);
        return faltando.length === 0 ? (
          <span className="text-xs text-muted-foreground">completo</span>
        ) : (
          <SeloFaltando campos={faltando} />
        );
      },
    },
    { chave: 'ativo', cabecalho: 'Situação', celula: (e) => <SeloAtivo ativo={e.ativo} /> },
  ];

  return (
    <>
      <PaginaListagem
        recurso="spaces"
        titulo="Espaços"
        descricao="Palcos, salas e áreas do evento — e, principalmente, como o participante chega em cada um."
        colunas={colunas}
        ordenar="nome"
        placeholderBusca="Buscar por nome, alias ou instrução…"
        destinoItem={(e) => `/espacos/${e.id}`}
        definicoesFiltro={[
          {
            chave: 'tipo',
            rotulo: 'Tipo',
            opcoes: TIPOS_ESPACO.map((t) => ({ valor: t, rotulo: ROTULO_TIPO_ESPACO[t] })),
          },
          {
            chave: 'ativo',
            rotulo: 'Situação',
            opcoes: [
              { valor: 'true', rotulo: 'Ativos' },
              { valor: 'false', rotulo: 'Inativos' },
            ],
          },
          {
            chave: 'acessivel',
            rotulo: 'Acessibilidade',
            opcoes: [
              { valor: 'true', rotulo: 'Acessível' },
              { valor: 'false', rotulo: 'Não acessível' },
            ],
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhum espaço encontrado"
            descricao="Nenhum espaço bate com a busca e os filtros atuais."
          />
        }
      />

      <DrawerEspaco id={id} aoFechar={() => navegar('/espacos')} />
    </>
  );
}
