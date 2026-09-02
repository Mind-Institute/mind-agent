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
  /** Raiz da Edge Function do módulo Home V3 (`mindagent-home`). */
  readonly VITE_HOME_API_BASE_URL?: string;
  /** Onde o app do participante é servido, para a prévia das telas.
   *  Vazio em produção = a raiz, que é onde o app vive no mesmo worker. */
  readonly VITE_APP_BASE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

declare module '*.png' {
  const src: string;
  export default src;
}
