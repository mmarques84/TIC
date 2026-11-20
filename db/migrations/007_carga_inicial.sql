-- 007 · Carga inicial: perfis, permissões, formulário OPI FFRO 005 rev5, parâmetros do roteiro, integrações.
-- Operações, usuários, veículos e motoristas NÃO entram aqui (lista oficial pendente com a TIC; ingestão cria veículos e motoristas).
-- Parâmetros: valores do roteiro v1 do Michael, escopo global. Limites por operação entram depois (plano.md, pergunta 2).

INSERT INTO acesso.perfil (codigo, nome, descricao) VALUES
  ('diretoria', 'Diretoria',  'Cockpits, alertas e OPI; só leitura'),
  ('operacao',  'Operação',   'Jornada, torre e alertas da sua operação'),
  ('frota_opi', 'Frota/OPI',  'OPI, validação da IA, alertas e jornada'),
  ('central',   'Central',    'Fila de alertas, mensagem ao terminal e sirene'),
  ('ti',        'TI',         'Integrações, consumo de IA e auditoria'),
  ('admin',     'Admin',      'Tudo, inclusive usuários e parâmetros');

INSERT INTO acesso.permissao (codigo, descricao) VALUES
  ('alerta.ver',         'Ver a central de alertas'),
  ('alerta.tratar',      'Confirmar ou marcar falso positivo'),
  ('alerta.acionar',     'Mandar mensagem ao terminal e acionar a sirene'),
  ('imagem.ver',         'Ver as imagens das câmeras (fica na auditoria)'),
  ('jornada.ver',        'Ver a jornada dos motoristas'),
  ('jornada.tratar',     'Registrar tratativa de jornada'),
  ('torre.ver',          'Ver a torre de chegadas'),
  ('opi.ver',            'Ver as OPIs'),
  ('opi.validar',        'Validar OPI e decidir a ação'),
  ('triagem.validar',    'Concordar ou discordar da triagem da IA'),
  ('cockpit.ver',        'Ver o cockpit gerencial'),
  ('consumo_ia.ver',     'Ver o consumo de IA'),
  ('parametro.ver',      'Ver os parâmetros das regras'),
  ('parametro.editar',   'Alterar os parâmetros das regras'),
  ('usuario.gerir',      'Criar e editar usuários e perfis'),
  ('integracao.ver',     'Ver o status das integrações'),
  ('auditoria.ver',      'Consultar a auditoria');

INSERT INTO acesso.perfil_permissao (perfil, permissao)
SELECT p, unnest(perms) FROM (VALUES
  ('diretoria', ARRAY['alerta.ver','imagem.ver','jornada.ver','torre.ver','opi.ver','cockpit.ver','consumo_ia.ver']),
  ('operacao',  ARRAY['alerta.ver','alerta.tratar','alerta.acionar','imagem.ver','jornada.ver','jornada.tratar','torre.ver','cockpit.ver','parametro.ver']),
  ('frota_opi', ARRAY['alerta.ver','alerta.tratar','imagem.ver','jornada.ver','jornada.tratar','opi.ver','opi.validar','triagem.validar','cockpit.ver','parametro.ver']),
  ('central',   ARRAY['alerta.ver','alerta.tratar','alerta.acionar','imagem.ver','torre.ver']),
  ('ti',        ARRAY['consumo_ia.ver','integracao.ver','auditoria.ver'])
) AS t(p, perms);

INSERT INTO acesso.perfil_permissao (perfil, permissao)
SELECT 'admin', codigo FROM acesso.permissao;

-- ===== OPI: FFRO 005 rev5 (17/08/2026). Não existe item 36 no formulário. =====

INSERT INTO ia.opi_modelo (codigo, nome, revisao, vigente_desde)
VALUES ('FFRO005-R5', 'Observação para Prevenção de Incidente', 'Rev5', '2026-08-17');

INSERT INTO ia.opi_modelo_item (modelo, numero, secao, texto, invertido, so_nao_anunciada, avaliado_por) VALUES
  ('FFRO005-R5',  1, 'antes_viagem', 'O motorista se apresenta descansado / tranquilo', false, false, 'humano'),
  ('FFRO005-R5',  2, 'antes_viagem', 'Realiza a verificação do CT', false, false, 'humano'),
  ('FFRO005-R5',  3, 'antes_viagem', 'Consulta o rotograma', false, false, 'humano'),
  ('FFRO005-R5',  4, 'antes_viagem', 'Verifica em volta do CT antes de iniciar seu movimento', false, false, 'humano'),
  ('FFRO005-R5',  5, 'procedimentos_empresa', 'Utilização de uniforme', false, false, 'video'),
  ('FFRO005-R5',  6, 'procedimentos_empresa', 'Utilização do cinto de segurança', false, false, 'video'),
  ('FFRO005-R5',  7, 'procedimentos_empresa', 'Proibição do telefone celular com o veículo ligado', false, false, 'video'),
  ('FFRO005-R5',  8, 'procedimentos_empresa', 'Proibição de carona', false, false, 'video'),
  ('FFRO005-R5',  9, 'procedimentos_empresa', 'Restrição ao tabagismo ao dirigir', false, false, 'video'),
  ('FFRO005-R5', 10, 'procedimentos_empresa', 'Proibição de álcool e drogas (após paradas para descanso ou almoço, apresenta indícios de direção agressiva)', false, false, 'video'),
  ('FFRO005-R5', 11, 'procedimentos_empresa', 'Mantém a cabine livre de objetos soltos (prancheta, garrafas, EPIs etc.)', false, false, 'video'),
  ('FFRO005-R5', 12, 'procedimentos_empresa', 'Proibição de interação com objetos com o veículo ligado', false, false, 'video'),
  ('FFRO005-R5', 13, 'direcao_segura', 'Respeita os limites de velocidade máxima (75 km/h pista seca e 55 km/h pista molhada)', false, false, 'sistema'),
  ('FFRO005-R5', 14, 'direcao_segura', 'Respeita o limite legal de velocidade para o local (sinalização vertical)', false, false, 'video'),
  ('FFRO005-R5', 15, 'direcao_segura', 'Pratica a velocidade compatível', false, false, 'video'),
  ('FFRO005-R5', 16, 'direcao_segura', 'Em rodovias, trafega pela faixa de rolamento correta (em pista dupla, pela faixa da direita)', false, false, 'video'),
  ('FFRO005-R5', 17, 'direcao_segura', 'Mantém correta distância de seguimento', false, false, 'video'),
  ('FFRO005-R5', 18, 'direcao_segura', 'Ultrapassa de forma segura', false, false, 'video'),
  ('FFRO005-R5', 19, 'direcao_segura', 'Facilita a ultrapassagem de terceiros', false, false, 'video'),
  ('FFRO005-R5', 20, 'direcao_segura', 'Utiliza-se corretamente do freio-motor em descidas longas', false, false, 'sistema'),
  ('FFRO005-R5', 21, 'direcao_segura', 'Sinaliza antecipadamente todas as suas intenções', false, false, 'video'),
  ('FFRO005-R5', 22, 'direcao_segura', 'Dirige com as duas mãos no volante', false, false, 'video'),
  ('FFRO005-R5', 23, 'direcao_segura', 'Freia antecipadamente / suavemente', false, false, 'sistema'),
  ('FFRO005-R5', 24, 'direcao_segura', 'Reduz velocidade ao passar por cruzamentos (incluindo cercas eletrônicas)', false, false, 'video'),
  ('FFRO005-R5', 25, 'direcao_segura', 'É cortês com os demais motoristas', false, false, 'video'),
  ('FFRO005-R5', 26, 'direcao_segura', 'Respeita o semáforo (sem aproveitar-se do amarelo)', false, false, 'video'),
  ('FFRO005-R5', 27, 'direcao_segura', 'Certifica-se de que não existem outros veículos ao lado do CT antes de conversão em esquinas e entrada de clientes', false, false, 'video'),
  ('FFRO005-R5', 28, 'direcao_segura', 'Solicita auxílio para manobra em clientes', false, false, 'video'),
  ('FFRO005-R5', 29, 'direcao_segura', 'Aciona o freio de mão / calça o CT ao estacionar', false, false, 'video'),
  ('FFRO005-R5', 30, 'direcao_segura', 'Estaciona em local seguro', false, false, 'video'),
  ('FFRO005-R5', 31, 'direcao_segura', 'Apresenta sinais de fadiga e sono', true,  false, 'video'),
  ('FFRO005-R5', 32, 'apos_viagem', 'Comunica problemas com o CT', false, false, 'humano'),
  ('FFRO005-R5', 33, 'apos_viagem', 'Comunica práticas inseguras / quase acidentes', false, false, 'humano'),
  ('FFRO005-R5', 34, 'apos_viagem', 'Durante a viagem, parou em local não autorizado?', true,  false, 'sistema'),
  ('FFRO005-R5', 35, 'apos_viagem', 'Respeitou a jornada de trabalho?', false, false, 'sistema'),
  ('FFRO005-R5', 37, 'apos_viagem', 'Cumpriu com os procedimentos de início de viagem e descarga de produtos', false, false, 'humano'),
  ('FFRO005-R5', 38, 'cameras', 'Câmera de fadiga está funcionando e em ângulo adequado para captação das imagens?', false, true, 'video'),
  ('FFRO005-R5', 39, 'cameras', 'Câmera frontal está funcionando e em ângulo adequado para captação das imagens?', false, true, 'video'),
  ('FFRO005-R5', 40, 'cameras', 'Câmera lateral direita está funcionando e em ângulo adequado para captação das imagens?', false, true, 'video'),
  ('FFRO005-R5', 41, 'cameras', 'Câmera lateral esquerda está funcionando e em ângulo adequado para captação das imagens?', false, true, 'video'),
  ('FFRO005-R5', 42, 'cameras', 'Câmera interna da cabine está funcionando e em ângulo adequado para captação das imagens?', false, true, 'video'),
  ('FFRO005-R5', 43, 'cameras', 'As informações nas câmeras estão corretas (data e hora, placa, velocidade, latitude e longitude)?', false, true, 'video');

-- ===== Parâmetros (roteiro v1, escopo global) =====

INSERT INTO controle.parametro (chave, valor, unidade, descricao, motivo) VALUES
  ('fadiga.bocejos_hora.mensagem',        '4',    'eventos/h', 'Acima disso: mensagem no terminal + alerta no painel', 'Roteiro v1 §8'),
  ('fadiga.bocejos_hora.critico',         '10',   'eventos/h', 'Acima disso: sirene + alerta à central', 'Roteiro v1 §8'),
  ('fadiga.olhos_fechados_hora.critico',  '4',    'eventos/h', 'Acima disso: crítico', 'Roteiro v1 §8'),
  ('fadiga.bocejo.duracao_min',           '4',    's',         'Bocejo só conta acima desta duração', 'Roteiro v1 §8'),
  ('fadiga.velocidade_min',               '20',   'km/h',      'Bocejo só conta acima desta velocidade', 'Roteiro v1 §8'),
  ('velocidade.seca',        '{"leve":[81,83],"medio":[84,86],"grave_acima":86}', 'km/h', 'Faixas de excesso em pista seca', 'Roteiro v1 §9'),
  ('velocidade.molhada',     '{"leve":[60,63],"medio":[64,66],"grave_acima":66}', 'km/h', 'Faixas de excesso com limpador ligado', 'Roteiro v1 §9'),
  ('freada.reducao_1s',      '15',  'km/h', 'Freada brusca: queda de velocidade em 1 s', 'Roteiro v1 §9'),
  ('freada.velocidade_min',  '10',  'km/h', 'Freada só conta a partir desta velocidade', 'Roteiro v1 §9'),
  ('forca_g.limite',         '0.5', 'G',    'Aceleração brusca / força G', 'Roteiro v1 §9'),
  ('camera.sem_cinto.duracao_min',   '10',  's', 'Sem cinto: grave acima disso', 'Roteiro v1 §10'),
  ('camera.celular.duracao_min',     '10',  's', 'Celular: grave acima disso', 'Roteiro v1 §10'),
  ('camera.fumar.duracao_min',       '1',   's', 'Fumar: grave acima disso', 'Roteiro v1 §10'),
  ('camera.maos_fora.duracao_min',   '15',  's', 'Mãos fora do volante: grave acima disso', 'Roteiro v1 §10'),
  ('camera.distracao.eventos_hora',  '5',   'eventos/h', 'Distração: grave acima disso', 'Roteiro v1 §10'),
  ('jornada.normal',                 '8',   'h',   'Jornada normal', 'Lei 13.103 / Roteiro v1 §10'),
  ('jornada.extra_max',              '2',   'h',   'Horas extras (até 4 com acordo)', 'Lei 13.103 / Roteiro v1 §10'),
  ('jornada.direcao_continua_max',   '330', 'min', 'Direção contínua máxima (5h30)', 'Lei 13.103'),
  ('jornada.pausa_direcao',          '30',  'min', 'Pausa obrigatória na direção contínua', 'Lei 13.103'),
  ('jornada.refeicao_min',           '60',  'min', 'Refeição mínima', 'Lei 13.103'),
  ('jornada.interjornada_min',       '11',  'h',   'Descanso entre jornadas (sem fracionamento)', 'Lei 13.103 / STF ADI 5322'),
  ('jornada.dsr',                    '35',  'h',   'Descanso semanal', 'Lei 13.103'),
  ('jornada.direcao_semana_max',     '60',  'h',   'Direção máxima por semana', 'Roteiro v1 §10'),
  ('jornada.dias_sem_dsr.alerta',    '7',   'dias','Alerta a partir deste dia sem DSR', 'Roteiro v1 §10'),
  ('jornada.parado_sem_descarga',    '14',  'h',   'Parado sem descarga programada: alerta', 'Roteiro v1 §10'),
  ('parada.raio',                    '1000','m',   'Mesmo local para contar parada/DSR', 'Painel Jornada TIC'),
  ('parada.km_invalida_dsr',         '50',  'km',  'Acima disso no período, a parada não conta como DSR', 'Painel Jornada TIC'),
  ('telemetria.km_sem_jornada',      '20',  'km',  'Rodou mais que isso num dia sem jornada aberta: alerta', 'Painel Jornada TIC'),
  ('opi.janela',                     '15',  'min', 'Duração do trecho avaliado', 'Roteiro v1 §11'),
  ('opi.validacao_humana',           '50',  '%',   'Parte das OPIs validadas por humano no início', 'Roteiro v1 §11'),
  ('opi.referencia.seca',            '75',  'km/h','Referência de conduta da OPI, pista seca', 'FFRO 005 item 13'),
  ('opi.referencia.molhada',         '55',  'km/h','Referência de conduta da OPI, pista molhada', 'FFRO 005 item 13'),
  ('ia.teto_mensal',                 'null','USD', 'Teto mensal de consumo de IA (aguarda o André)', 'Roteiro v1 §15'),
  ('retencao.meses',                 '12',  'meses','Evidências pesquisáveis por', 'Roteiro v1 §5');

INSERT INTO controle.credencial_status (fonte) VALUES ('autotrac'), ('moovsec'), ('datapar'), ('portran'), ('claude');
