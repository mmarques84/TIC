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
// ---- fim senha.js ----
