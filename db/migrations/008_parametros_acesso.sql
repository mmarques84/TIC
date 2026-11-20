-- 008 · Parâmetros de login e sessão (spec seguranca-acesso, valores propostos; mudar aqui, não no código).

INSERT INTO controle.parametro (chave, valor, unidade, descricao, motivo) VALUES
  ('acesso.tentativas_max',   '5',   'tentativas', 'Senhas erradas seguidas antes de bloquear', 'Spec seguranca-acesso R5'),
  ('acesso.bloqueio',         '15',  'min',        'Duração do bloqueio depois das tentativas', 'Spec seguranca-acesso R5'),
  ('acesso.sessao_inatividade','720', 'min',        'Sessão cai depois deste tempo sem uso (12 h)', 'Spec seguranca-acesso R8'),
  ('acesso.sessao_maxima',    '168', 'h',          'Duração máxima de uma sessão (7 dias)', 'Spec seguranca-acesso R8');
