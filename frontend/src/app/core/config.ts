// Cada porta de dados escolhe entre a API real (n8n → sp_*) e a camada fictícia.
// Ligue a real assim que o workflow correspondente estiver publicado. Nenhuma tela muda.
export const DADOS_FICTICIOS = {
  auth: false,   // /api/auth/login, /me, /logout: publicados (esqueci e definir senha ainda não)
  inicio: true,  // /api/inicio: ainda não existe
} as const;
