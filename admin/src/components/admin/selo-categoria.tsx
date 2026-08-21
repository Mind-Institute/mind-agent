import { HelpCircle } from 'lucide-react';
import type { Rotulo } from '@/lib/rotulos';
import { Badge } from '@/components/ui/badge';

/**
 * Selo de categoria vinda da API.
 *
 * Valor que o painel conhece aparece traduzido. Valor que ele não
 * conhece aparece com o código cru, em âmbar e com um ponto de
 * interrogação — dá para ver na listagem que o backend passou a usar
 * uma categoria nova, em vez de ela se disfarçar de outra.
 */
export function SeloCategoria({
  rotulo,
  variante = 'outline',
}: {
  rotulo: Rotulo;
  variante?: 'outline' | 'secondary' | 'neutro';
}) {
  if (rotulo.conhecido) return <Badge variant={variante}>{rotulo.texto}</Badge>;

  return (
    <Badge
      variant="atencao"
      title={`Categoria não reconhecida pelo painel: "${rotulo.texto}". O valor é mostrado como veio da API, sem tradução.`}
      data-categoria-desconhecida="true"
    >
      <HelpCircle className="size-3" />
      {rotulo.texto}
    </Badge>
  );
}
