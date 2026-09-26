import { useRef, useState, type ReactNode } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { AlertTriangle, CheckCircle2, UserPlus } from 'lucide-react';
import {
  DESCRICAO_PAPEL,
  adminSistemaFormSchema,
  darAcessoFormSchema,
  type AdminSistema,
  type AdminSistemaForm,
  type DarAcessoForm,
  type Papel,
} from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { useCriar } from '@/hooks/use-recurso';
import { useOrigemRecurso } from '@/services/provider-context';
import { useEdicaoRecurso } from '@/features/comum/use-edicao-recurso';
import { OPCOES_PAPEL, paraFormularioAdmin, payloadDaEdicaoAdmin, rotuloDoPapel } from '@/lib/admins';
import { opcoesComAtual } from '@/lib/rotulos';
import { formatarDataHora } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { DrawerEdicao } from '@/components/admin/drawer-edicao';
import { Campo } from '@/components/admin/campo';
import { DialogoConflito } from '@/components/admin/dialogos';
import { AvisoErroEscrita } from '@/components/admin/aviso-escrita';
import { EstadoCarregando, EstadoErro, EstadoVazio, Salvando } from '@/components/admin/estados';
import { SeloAtivo } from '@/components/admin/selos';
import { SeloCategoria } from '@/components/admin/selo-categoria';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

/* ============================================================
   ADMINS DO SISTEMA — quem entra no Mind Intelligence Admin
   ============================================================
   Pedido da Adriana (26/09/2026): ver e cadastrar quem entra. A casa é
   `public.mind_admin_users`, por Mind ID; a porta é a `mindagent-acesso`.

   - Dar acesso: e-mail @joinmind.com.br e papel. O banco acha a pessoa
     no Mind ID pelo e-mail — tem que existir, não fundida e marcada como
     equipe. A lista nunca cria pessoa.
   - Na linha: papel e situação. Tirar o acesso é desligar a situação; a
     linha fica, para a auditoria e para religar depois.
   - Só administrador vê e mexe. O banco confere de novo, e não deixa
     ninguém tirar o próprio acesso nem o painel ficar sem administrador. */

const ID_FORM_ACESSO = 'form-dar-acesso';
const ID_FORM_ADMIN = 'form-admin';

function descricaoDoPapel(papel: string | undefined): string | undefined {
  return papel ? DESCRICAO_PAPEL[papel as Papel] : undefined;
}

function DialogoDarAcesso({
  aberto,
  aoFechar,
  aoConcedido,
}: {
  aberto: boolean;
  aoFechar: () => void;
  aoConcedido: (admin: AdminSistema, email: string) => void;
}) {
  const criar = useCriar('admins');
  const formulario = useForm<DarAcessoForm>({
    resolver: zodResolver(darAcessoFormSchema),
    defaultValues: { email: '' },
  });
  const { errors } = formulario.formState;
  const papel = formulario.watch('papel') as Papel | undefined;

  function fechar() {
    formulario.reset({ email: '' });
    criar.reset();
    aoFechar();
  }

  async function enviar(valores: DarAcessoForm) {
    try {
      const novo = await criar.mutateAsync(valores);
      aoConcedido(novo, valores.email);
      fechar();
    } catch {
      /* A recusa fica em `criar.error` e aparece aqui mesmo, com o que
         foi digitado — o banco diz o motivo (não é equipe, não existe no
         Mind ID, já tem acesso). */
    }
  }

  return (
    <Dialog open={aberto} onOpenChange={(estado) => (!estado ? fechar() : undefined)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Dar acesso ao painel</DialogTitle>
          <DialogDescription>
            A pessoa precisa já existir no Mind ID com este e-mail, marcada como equipe. A lista não
            cria pessoa.
          </DialogDescription>
        </DialogHeader>

        <form
          id={ID_FORM_ACESSO}
          onSubmit={formulario.handleSubmit((v) => void enviar(v))}
          className="space-y-4"
          noValidate
        >
          <AvisoErroEscrita erro={criar.error} />

          <Campo
            rotulo="E-mail da Mind"
            obrigatorio
            erro={errors.email?.message}
            dica="É com ele que a pessoa entra, pelo botão Entrar com Google."
          >
            {(p) => (
              <Input
                type="email"
                autoComplete="off"
                placeholder="nome@joinmind.com.br"
                {...p}
                {...formulario.register('email')}
              />
            )}
          </Campo>

          <Campo rotulo="Papel" obrigatorio erro={errors.papel?.message} dica={descricaoDoPapel(papel)}>
            {(p) => (
              <Select
                value={papel ?? ''}
                onValueChange={(v) =>
                  formulario.setValue('papel', v as Papel, {
                    shouldDirty: true,
                    shouldValidate: formulario.formState.isSubmitted,
                  })
                }
              >
                <SelectTrigger id={p.id} aria-invalid={p['aria-invalid']}>
                  <SelectValue placeholder="Escolha o papel" />
                </SelectTrigger>
                <SelectContent>
                  {OPCOES_PAPEL.map((o) => (
                    <SelectItem key={o.valor} value={o.valor}>
                      {o.rotulo}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
          </Campo>
        </form>

        <DialogFooter>
          <Button variant="outline" type="button" onClick={fechar} disabled={criar.isPending}>
            Cancelar
          </Button>
          <Button type="submit" form={ID_FORM_ACESSO} disabled={criar.isPending}>
            {criar.isPending ? <Salvando /> : <UserPlus />}
            Dar acesso
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Dado({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return (
    <div className="space-y-0.5">
      <dt className="text-xs font-semibold text-muted-foreground">{rotulo}</dt>
      <dd>{children}</dd>
    </div>
  );
}

function DrawerAdmin({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const origem = useOrigemRecurso('admins');
  /* A linha que a tela abriu, para o payload levar só o que mudou. */
  const aberto = useRef<AdminSistema | undefined>(undefined);

  const edicao = useEdicaoRecurso<'admins', AdminSistemaForm>({
    recurso: 'admins',
    id,
    resolver: zodResolver(adminSistemaFormSchema),
    padrao: { papel: '', ativo: true },
    paraFormulario: paraFormularioAdmin,
    paraPayload: (valores) => payloadDaEdicaoAdmin(valores, aberto.current),
  });
  aberto.current = edicao.registro;

  const { formulario, registro } = edicao;
  const { errors } = formulario.formState;
  const papel = formulario.watch('papel');

  return (
    <>
      <DrawerEdicao
        aberto={Boolean(id)}
        titulo={registro?.nome || registro?.email || 'Admin'}
        descricao={registro?.nome && registro.email ? registro.email : undefined}
        sujo={edicao.sujo}
        salvando={edicao.salvando}
        idFormulario={ID_FORM_ADMIN}
        aoFechar={aoFechar}
        informacao={registro ? `Atualizado em ${formatarDataHora(registro.atualizadoEm)}` : undefined}
      >
        {edicao.carregando ? (
          <EstadoCarregando linhas={5} />
        ) : edicao.erro ? (
          <EstadoErro erro={edicao.erro} aoTentarNovamente={edicao.recarregar} />
        ) : (
          <form
            id={ID_FORM_ADMIN}
            onSubmit={formulario.handleSubmit((v) => void edicao.salvar(v))}
            className="space-y-4"
            noValidate
          >
            {edicao.salvo && !edicao.sujo ? (
              <Alert variant="info">
                <CheckCircle2 />
                <AlertTitle>Salvo</AlertTitle>
                <AlertDescription>
                  {origem === 'http'
                    ? 'Está no banco e já vale. A pessoa vê a mudança ao recarregar o painel.'
                    : 'Modo demonstração: a alteração ficou só nesta aba e some ao recarregar.'}
                </AlertDescription>
              </Alert>
            ) : null}

            <AvisoErroEscrita erro={edicao.erroEscrita} />

            {edicao.sujo ? (
              <Alert variant="atencao">
                <AlertTriangle />
                <AlertTitle>Alterações não salvas</AlertTitle>
                <AlertDescription>
                  Salvar manda para o banco só o que você mudou. Fechar sem salvar descarta.
                </AlertDescription>
              </Alert>
            ) : null}

            <dl className="grid gap-3 rounded-lg border bg-muted/30 p-4 text-sm sm:grid-cols-2">
              <Dado rotulo="E-mail">{registro?.email ?? '—'}</Dado>
              <Dado rotulo="Mind ID">
                {registro?.mindId ? (
                  <span className="font-mono text-xs">{registro.mindId}</span>
                ) : (
                  <Badge variant="atencao">sem Mind ID</Badge>
                )}
              </Dado>
              <Dado rotulo="Login">
                {registro?.loginLigado ? 'ligado' : 'aguarda o primeiro login com o Google'}
              </Dado>
              <Dado rotulo="Último login">
                {registro?.ultimoLoginEm ? formatarDataHora(registro.ultimoLoginEm) : 'nunca'}
              </Dado>
              <Dado rotulo="Com acesso desde">{formatarDataHora(registro?.criadoEm)}</Dado>
            </dl>

            <Campo rotulo="Papel" obrigatorio erro={errors.papel?.message} dica={descricaoDoPapel(papel)}>
              {(p) => (
                <Select
                  value={papel}
                  onValueChange={(v) => formulario.setValue('papel', v, { shouldDirty: true })}
                >
                  <SelectTrigger id={p.id} aria-invalid={p['aria-invalid']}>
                    <SelectValue placeholder="Escolha o papel" />
                  </SelectTrigger>
                  <SelectContent>
                    {opcoesComAtual(OPCOES_PAPEL, papel).map((o) => (
                      <SelectItem key={o.valor} value={o.valor}>
                        {o.rotulo}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </Campo>

            <div className="space-y-1">
              <div className="flex items-center gap-3">
                <Switch
                  id="admin-ativo"
                  checked={formulario.watch('ativo')}
                  onCheckedChange={(v) => formulario.setValue('ativo', v, { shouldDirty: true })}
                />
                <Label htmlFor="admin-ativo">Pode entrar no painel</Label>
              </div>
              <p className="text-xs text-muted-foreground">
                Desligado, a pessoa não entra mais. A linha fica, para a auditoria e para religar
                depois.
              </p>
            </div>
          </form>
        )}
      </DrawerEdicao>

      <DialogoConflito
        aberto={edicao.conflito}
        aoRecarregar={edicao.recarregar}
        aoFechar={edicao.fecharConflito}
      />
    </>
  );
}

export function PaginaAdmins() {
  const { id } = useParams();
  const navegar = useNavigate();
  /* Fechar o drawer volta à lista como estava: busca, filtros, página e ordem. */
  const { search } = useLocation();
  const sessao = useSessao();
  const origem = useOrigemRecurso('admins');
  const podeGerir = sessao.pode('gerir_usuarios');
  const [dandoAcesso, setDandoAcesso] = useState(false);
  const [concedido, setConcedido] = useState<{ nome: string; email: string } | null>(null);

  const colunas: Coluna<AdminSistema>[] = [
    {
      chave: 'pessoa',
      cabecalho: 'Pessoa',
      celula: (a) => (
        <div className="min-w-56">
          <p className="font-semibold">{a.nome || a.email || '—'}</p>
          {a.nome && a.email ? <p className="text-xs text-muted-foreground">{a.email}</p> : null}
          {a.mindId ? null : (
            <Badge variant="atencao" className="mt-1">
              sem Mind ID
            </Badge>
          )}
        </div>
      ),
    },
    { chave: 'papel', cabecalho: 'Papel', celula: (a) => <SeloCategoria rotulo={rotuloDoPapel(a.papel)} /> },
    { chave: 'ativo', cabecalho: 'Situação', celula: (a) => <SeloAtivo ativo={a.ativo} /> },
    {
      chave: 'login',
      cabecalho: 'Login',
      celula: (a) =>
        a.loginLigado ? (
          <Badge variant="sucesso">ligado</Badge>
        ) : (
          <Badge variant="neutro">aguarda o 1º login</Badge>
        ),
    },
    {
      chave: 'ultimoLogin',
      cabecalho: 'Último login',
      className: 'whitespace-nowrap tabular',
      celula: (a) => (
        <span className="text-xs text-muted-foreground">
          {a.ultimoLoginEm ? formatarDataHora(a.ultimoLoginEm) : 'nunca'}
        </span>
      ),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso="admins"
        titulo="Admins do sistema"
        descricao="Quem entra no Mind Intelligence Admin. A pessoa precisa existir no Mind ID, marcada como equipe, e entra com o Google da Mind (@joinmind.com.br). Abra uma linha para mudar o papel ou tirar o acesso."
        permissaoNecessaria="gerir_usuarios"
        colunas={colunas}
        placeholderBusca="Buscar por nome ou e-mail…"
        destinoItem={(a) => `/admins/${a.id}`}
        acoes={
          podeGerir ? (
            <Button onClick={() => setDandoAcesso(true)}>
              <UserPlus /> Dar acesso
            </Button>
          ) : null
        }
        definicoesFiltro={[
          { chave: 'papel', rotulo: 'Papel', opcoes: OPCOES_PAPEL },
          {
            chave: 'ativo',
            rotulo: 'Situação',
            opcoes: [
              { valor: 'true', rotulo: 'Ativos' },
              { valor: 'false', rotulo: 'Inativos' },
            ],
          },
        ]}
        antesDaTabela={() =>
          concedido ? (
            <Alert variant="info" data-testid="acesso-concedido">
              <CheckCircle2 />
              <AlertTitle>Acesso dado</AlertTitle>
              <AlertDescription>
                {origem === 'http'
                  ? `${concedido.nome} já pode entrar: é só usar "Entrar com Google" com ${concedido.email}.`
                  : 'Modo demonstração: o acesso ficou só nesta aba e some ao recarregar.'}
              </AlertDescription>
            </Alert>
          ) : null
        }
        estadoVazio={
          <EstadoVazio
            titulo="Ninguém no recorte"
            descricao="Ninguém bate com a busca e os filtros atuais."
          />
        }
      />

      {podeGerir ? (
        <>
          <DialogoDarAcesso
            aberto={dandoAcesso}
            aoFechar={() => setDandoAcesso(false)}
            aoConcedido={(admin, email) => setConcedido({ nome: admin.nome || email, email })}
          />
          <DrawerAdmin id={id} aoFechar={() => navegar({ pathname: '/admins', search })} />
        </>
      ) : null}
    </>
  );
}
