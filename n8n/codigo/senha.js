// ---- senha.js (hash PBKDF2; spec seguranca-acesso R2 e R4) ----
// Formato guardado: pbkdf2$sha512$<iteracoes>$<salt base64url>$<hash base64url>
const PBKDF2_ITERACOES = 210000;
const PBKDF2_BYTES = 64;
// Conferido quando o e-mail não existe, para o tempo de resposta ser o mesmo (R3).
const HASH_FICTICIO = 'pbkdf2$sha512$210000$AAAAAAAAAAAAAAAAAAAAAA$' + 'A'.repeat(86);

function gerarHashSenha(senha) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.pbkdf2Sync(senha, salt, PBKDF2_ITERACOES, PBKDF2_BYTES, 'sha512');
  return `pbkdf2$sha512$${PBKDF2_ITERACOES}$${salt.toString('base64url')}$${hash.toString('base64url')}`;
}

function conferirSenha(senha, guardado) {
  let partes = String(guardado || '').split('$');
  const valido = partes.length === 5 && partes[0] === 'pbkdf2' && partes[1] === 'sha512' && /^\d{4,7}$/.test(partes[2]);
  if (!valido) partes = HASH_FICTICIO.split('$');
  const salt = Buffer.from(partes[3], 'base64url');
  const esperado = Buffer.from(partes[4], 'base64url');
  const calculado = crypto.pbkdf2Sync(String(senha), salt, Number(partes[2]), esperado.length || PBKDF2_BYTES, 'sha512');
  return valido && esperado.length === calculado.length && crypto.timingSafeEqual(calculado, esperado);
}
// Lista inicial de senhas comuns (ampliar com lista pública de vazamentos antes da produção).
const SENHAS_COMUNS = new Set([
  '123456789012', '1234567890123', '111111111111', '000000000000', '123123123123', 'qwertyuiopas', 'qwerty123456',
  'abcdefghijkl', 'abc123456789', 'password1234', 'senha1234567', 'senha123456!', 'mudar1234567', 'trocar123456',
  'admin1234567', 'administrador', 'brasil123456', 'tictransportes', 'tic123456789', 'transportes12',
]);

/** Código de recusa (spec seguranca-acesso R4) ou null se a senha serve. */
function recusaSenha(senha, nome, email) {
  if (typeof senha !== 'string' || senha.length < 12) return 'SENHA_FRACA';
  const norm = (t) => String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
  const s = norm(senha);
  const pedacos = [norm(String(email).split('@')[0]), ...norm(nome).split(/\s+/)].filter((p) => p.length >= 3);
  if (pedacos.some((p) => s.includes(p))) return 'SENHA_FRACA';
  if (SENHAS_COMUNS.has(s) || /^(.)\1+$/.test(s)) return 'SENHA_FRACA';
  return null;
}
// ---- fim senha.js ----
