import { useMemo } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Star } from 'lucide-react';
import {
  ROTULO_STATUS_EDITORIAL,
  STATUS_EDITORIAL,
  type Palestrante,
} from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { camposFaltantesDoPalestrante } from '@/lib/pendencias';
import { urlDaFoto } from '@/lib/fotos';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { SeloEditorial, SeloFaltando } from '@/components/admin/selos';
import { EstadoVazio } from '@/components/admin/estados';
import { DrawerPalestrante } from '@/features/palestrantes/drawer-palestrante';
import { Badge } from '@/components/ui/badge';

export function PaginaPalestrantes() {
  const { id } = useParams();
  const navegar = useNavigate();
  const temas = useLista('themes');
  const sessoes = useLista('sessions', {});

  const contagemSessoes = useMemo(() => {
    const mapa = new Map<string, number>();
    for (const sessao of sessoes.data?.itens ?? []) {
      for (const palestranteId of sessao.palestranteIds) {
        mapa.set(palestranteId, (mapa.get(palestranteId) ?? 0) + 1);
      }
    }
    return mapa;
  }, [sessoes.data]);

  const rotuloTema = useMemo(() => {
    const mapa = new Map((temas.data?.itens ?? []).map((t) => [t.codigo, t.rotulo]));
    return (codigo: string) => mapa.get(codigo) ?? codigo;
  }, [temas.data]);

  const colunas: Coluna<Palestrante>[] = [
    {
      chave: 'nome',
      cabecalho: 'Palestrante',
      celula: (p) => {
        const foto = urlDaFoto(p.foto);
        return (
          <div className="flex min-w-56 items-center gap-3">
            {foto ? (
              <img src={foto} alt="" className="size-9 rounded-full object-cover" loading="lazy" />
            ) : (
              <div className="size-9 rounded-full border border-dashed" aria-hidden />
            )}
            <div className="min-w-0">
              <p className="flex items-center gap-1 font-semibold">
                {p.nome}
                {p.destaque ? <Star className="size-3.5 fill-coral-400 text-coral-400" /> : null}
              </p>
              <p className="truncate text-xs text-muted-foreground">
                {[p.organizacao, p.cargo].filter(Boolean).join(' · ') || 'sem credencial'}
              </p>
            </div>
          </div>
        );
      },
    },
    {
      chave: 'temas',
      cabecalho: 'Temas',
      celula: (p) =>
        p.temas.length === 0 ? (
          <span className="text-xs text-muted-foreground">—</span>
        ) : (
          <div className="flex max-w-64 flex-wrap gap-1">
            {p.temas.slice(0, 3).map((t) => (
              <Badge key={t} variant="secondary">
                {rotuloTema(t)}
              </Badge>
            ))}
            {p.temas.length > 3 ? (
              <Badge variant="neutro">+{p.temas.length - 3}</Badge>
            ) : null}
          </div>
        ),
    },
    {
      chave: 'sessoes',
      cabecalho: 'Sessões',
      className: 'tabular',
      celula: (p) => contagemSessoes.get(p.id) ?? 0,
    },
    {
      chave: 'pendencias',
      cabecalho: 'Pendências',
      celula: (p) => {
        const faltando = camposFaltantesDoPalestrante(p);
        return faltando.length === 0 ? (
          <span className="text-xs text-muted-foreground">completo</span>
        ) : (
          <SeloFaltando campos={faltando} />
        );
      },
    },
    { chave: 'status', cabecalho: 'Status', celula: (p) => <SeloEditorial status={p.status} /> },
  ];

  return (
    <>
      <PaginaListagem
        recurso="speakers"
        titulo="Palestrantes"
        descricao="Quem fala no Summit. Abrir uma pessoa mostra também a prévia do cartão como ele aparece no chat."
        colunas={colunas}
        ordenar="nome"
        placeholderBusca="Buscar por nome, organização ou biografia…"
        destinoItem={(p) => `/palestrantes/${p.id}`}
        definicoesFiltro={[
          {
            chave: 'tema',
            rotulo: 'Tema',
            opcoes: (temas.data?.itens ?? []).map((t) => ({ valor: t.codigo, rotulo: t.rotulo })),
          },
          {
            chave: 'destaque',
            rotulo: 'Destaque',
            opcoes: [
              { valor: 'true', rotulo: 'Em destaque' },
              { valor: 'false', rotulo: 'Sem destaque' },
            ],
          },
          {
            chave: 'status',
            rotulo: 'Status',
            opcoes: STATUS_EDITORIAL.map((s) => ({ valor: s, rotulo: ROTULO_STATUS_EDITORIAL[s] })),
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhum palestrante encontrado"
            descricao="Nenhuma pessoa bate com a busca e os filtros atuais."
          />
        }
      />

      <DrawerPalestrante id={id} aoFechar={() => navegar('/palestrantes')} />
    </>
  );
}
