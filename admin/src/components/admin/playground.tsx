import { useRef, useState } from 'react';
import { FlaskConical, RotateCcw, Send } from 'lucide-react';
import { useSessao } from '@/hooks/use-sessao';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

/* ============================================================
   PLAYGROUND — conversar com um agente para testar
   ============================================================
   O mesmo motor do chat real (`mindagent-chat`), numa conversa DE TESTE:
   o banco só a abre para administrador e a marca de um jeito que a deixa
   fora da análise pós-conversa, da memória e do HubSpot. A rota pedida
   vale mesmo com o canal desligado; playbook e dados oficiais continuam
   obrigatórios. Aprovado pela Adriana em 22/10/2026. */

type Sessao = { id: string; conversation_id: string; token: string };

type Fala = {
  papel: 'voce' | 'agente' | 'sistema';
  texto: string;
  rota?: string | null;
  modelo?: string | null;
  ferramentas?: { nome: string; ok: boolean }[];
};

type RespostaDoChat = {
  ok?: boolean;
  answer?: string;
  session?: Sessao & { expires_at?: string | null };
  device_id?: string;
  rota?: string;
  rota_origem?: string;
  teste?: boolean;
  modelo?: string;
  ferramentas?: { nome: string; ok: boolean }[];
  error?: { code?: string; message?: string };
};

/** Onde o motor do chat está: o mesmo projeto do painel. */
export function enderecoDoChat(supabaseUrl = import.meta.env.VITE_SUPABASE_URL): string | null {
  const base = supabaseUrl?.trim().replace(/\/+$/, '');
  return base ? `${base}/functions/v1/mindagent-chat` : null;
}

function explicacaoDoErro(codigo: string | undefined, mensagem: string | undefined) {
  switch (codigo) {
    case 'rota_indisponivel':
    case 'official_data_unavailable':
      return 'O agente não tem o que precisa para responder: confira na aba Instruções se o playbook está ligado e, em Dados oficiais, se há bloco obrigatório ligado.';
    case 'unauthorized':
      return 'Sua sessão do painel expirou. Entre de novo.';
    default:
      return mensagem ?? 'Não foi possível conversar com o agente agora.';
  }
}

export function Playground({ agente, rotulo }: { agente: string; rotulo: string }) {
  const sessao = useSessao();
  const podeTestar = sessao.pode('configurar');
  const [falas, setFalas] = useState<Fala[]>([]);
  const [texto, setTexto] = useState('');
  const [enviando, setEnviando] = useState(false);
  const conversa = useRef<{ sessao: Sessao | null; deviceId: string | null }>({ sessao: null, deviceId: null });

  function novaConversa() {
    conversa.current = { sessao: null, deviceId: null };
    setFalas([]);
    setTexto('');
  }

  async function enviar() {
    const mensagem = texto.trim();
    if (!mensagem || enviando) return;
    setEnviando(true);
    setTexto('');
    setFalas((atual) => [...atual, { papel: 'voce', texto: mensagem }]);
    try {
      const endereco = enderecoDoChat();
      if (!endereco) throw new Error('Supabase não configurado.');
      const token = await sessao.obterToken();
      if (!token) throw new Error('Sessão ausente.');
      const chave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
      const atual = conversa.current;
      const resposta = await fetch(endereco, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          ...(chave ? { apikey: chave } : {}),
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: mensagem,
          client_message_id: crypto.randomUUID(),
          /* Na abertura, pede a conversa de teste com este agente; depois, a sessão basta. */
          ...(atual.sessao ? { session: atual.sessao } : { playground: { rota: agente } }),
          ...(atual.deviceId ? { device_id: atual.deviceId } : {}),
        }),
      });
      const corpo = await resposta.json().catch(() => ({})) as RespostaDoChat;
      if (!resposta.ok || corpo.ok !== true) {
        setFalas((atual) => [...atual, { papel: 'sistema', texto: explicacaoDoErro(corpo.error?.code, corpo.error?.message) }]);
        return;
      }
      if (corpo.session) {
        conversa.current = {
          sessao: { id: corpo.session.id, conversation_id: corpo.session.conversation_id, token: corpo.session.token },
          deviceId: corpo.device_id ?? atual.deviceId,
        };
      }
      if (corpo.teste !== true) {
        /* Nunca deve acontecer: a conversa não foi marcada como teste. Para na hora. */
        conversa.current = { sessao: null, deviceId: null };
        setFalas((atual) => [...atual, { papel: 'sistema', texto: 'Esta conversa não foi marcada como teste pelo motor. O Playground parou para não gravar nada de verdade.' }]);
        return;
      }
      setFalas((atual) => [...atual, { papel: 'agente', texto: corpo.answer ?? '', rota: corpo.rota ?? null, modelo: corpo.modelo ?? null, ferramentas: corpo.ferramentas ?? [] }]);
    } catch (e) {
      setFalas((atual) => [...atual, { papel: 'sistema', texto: e instanceof Error ? e.message : 'Não foi possível conversar com o agente agora.' }]);
    } finally {
      setEnviando(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <FlaskConical className="size-4" /> Testar {rotulo}
        </CardTitle>
        <CardDescription>
          O mesmo motor do chat real, numa conversa de teste: fica fora da análise, da memória e do HubSpot, e funciona
          mesmo com o canal desligado para este agente. O que você vê aqui é o que o público receberia com os textos,
          o conhecimento e as skills ligados agora.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {!podeTestar ? <div className="text-sm text-muted-foreground">Só administrador testa os agentes.</div> : null}
        {/* Vazio, o histórico não ganha caixa com borda: parecia um campo de digitação e a pessoa
            escrevia nele em vez de em "Sua mensagem" (Adriana, 23/10/2026). */}
        <div
          className={`max-h-[28rem] space-y-3 overflow-auto ${falas.length === 0 ? '' : 'rounded-md border p-3'}`}
          aria-label="Conversa de teste"
          role="log"
        >
          {falas.length === 0 ? (
            <div className="text-sm text-muted-foreground">Nenhuma mensagem ainda. Escreva abaixo, em "Sua mensagem", e aperte Enter ou Enviar.</div>
          ) : (
            falas.map((f, i) => (
              <div key={i} className={`text-sm ${f.papel === 'voce' ? 'text-right' : ''}`}>
                <div
                  className={`inline-block max-w-[85%] whitespace-pre-wrap rounded-md px-3 py-2 text-left ${
                    f.papel === 'voce' ? 'bg-foreground text-background' : f.papel === 'agente' ? 'bg-muted' : 'border border-amber-200 bg-amber-50 text-amber-900'
                  }`}
                >
                  {f.texto}
                </div>
                {f.papel === 'agente' ? (
                  <div className="mt-1 flex flex-wrap items-center gap-1 text-xs text-muted-foreground">
                    {f.rota ? <Badge variant="outline">respondeu: {f.rota}</Badge> : null}
                    {f.modelo ? <Badge variant="outline">modelo: {f.modelo}</Badge> : null}
                    {(f.ferramentas ?? []).map((t, j) => (
                      <Badge key={j} variant={t.ok ? 'outline' : 'neutro'}>
                        skill: {t.nome}
                        {t.ok ? '' : ' (falhou)'}
                      </Badge>
                    ))}
                  </div>
                ) : null}
              </div>
            ))
          )}
        </div>
        <div className="space-y-1">
          <Label htmlFor={`playground-${agente}`}>Sua mensagem</Label>
          <Textarea
            id={`playground-${agente}`}
            value={texto}
            autoFocus
            disabled={!podeTestar || enviando}
            onChange={(e) => setTexto(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                void enviar();
              }
            }}
            className="min-h-20"
            placeholder="Ex.: O que a palestra sobre burnout disse sobre liderança?"
          />
        </div>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => void enviar()} disabled={!podeTestar || enviando || texto.trim() === ''}>
            <Send className="mr-2 size-4" />
            {enviando ? 'Enviando…' : 'Enviar'}
          </Button>
          <Button variant="outline" onClick={novaConversa} disabled={enviando || falas.length === 0}>
            <RotateCcw className="mr-2 size-4" /> Nova conversa de teste
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
