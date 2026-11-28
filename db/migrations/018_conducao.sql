INSERT INTO acesso.permissao (codigo, descricao)
VALUES ('conducao.ver', 'Consultar eventos de condução');

INSERT INTO acesso.perfil_permissao (perfil, permissao)
VALUES ('admin', 'conducao.ver'), ('diretoria', 'conducao.ver'),
       ('operacao', 'conducao.ver'), ('frota_opi', 'conducao.ver');

INSERT INTO controle.parametro (chave, valor, unidade, descricao, motivo)
VALUES ('conducao.eventos_por_pagina', '50', NULL, 'Eventos por página de Condução', 'Spec Condução E1');
