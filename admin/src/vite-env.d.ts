/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Raiz das Edge Functions administrativas. Vazio = modo demonstração. */
  readonly VITE_ADMIN_API_BASE_URL?: string;
  /** `mock`, `hybrid` (padrão com API) ou `http`. Ver provider-context. */
  readonly VITE_ADMIN_DATA_MODE?: string;
  /** Projeto Supabase — usado apenas por Supabase Auth, no futuro. */
  readonly VITE_SUPABASE_URL?: string;
  /** Chave publicável (anon). Nunca `service_role`, nunca secret key. */
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string;
  /** Raiz da Edge Function do catálogo (`mindagent-catalogo`). Vazia =
   *  sai de `VITE_SUPABASE_URL`, ver `enderecoDoCatalogo()`. */
  readonly VITE_CATALOGO_API_BASE_URL?: string;
  /** Raiz da Edge Function `mindagent-acesso` (primeiro login com Google). Sem ela, o endereço
   *  sai de `VITE_SUPABASE_URL`, ver `enderecoDoAcesso()`. */
  readonly VITE_ACESSO_API_BASE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

declare module '*.png' {
  const src: string;
  export default src;
}
