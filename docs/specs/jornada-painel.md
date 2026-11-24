# Spec: Tela de Jornada

**Status:** implementada localmente com dados fictícios (23/11/2026; spec e layout aprovados pelo Marcus em 23/11) · **Marco:** 3b (adiantado) · **Atualizada em:** 2026-11-23
**Telas:** canvas "TIC Painel Digital · Login", artboard `Jornada` (para validar) · **Tabelas:** lê `derivado.motorista_situacao`, `derivado.jornada`, `derivado.parada`, `bruto.autotrac_macro`, `controle.macro_mapa`; grava `derivado.tratativa`, `controle.auditoria` · **Workflows:** `api-jornada` (novo) · **Funções:** `sp_jornada_listar`, `sp_jornada_resumo`, `sp_jornada_detalhe`, `sp_tratativa_criar`
**Base:** painel "Jornada TIC" do Rafael (`estudo-paineis.md` §1), spec `motor-jornada.md` (que calcula tudo), skill `regras-jornada`.

## O que faz

Substitui o painel de Jornada do Rafael por uma tela com dado guardado e histórico. Mostra, para cada motorista, o que está acontecendo agora (dirigindo, em jornada, refeição, descanso), a jornada atual contra os limites da lei, há quanto tempo está parado, os dias sem descanso semanal e os alertas que o motor de jornada levantou. A equipe de operação e de frota abre a linha de um motorista para ver as últimas jornadas, as paradas longas e as macros, e registra a **tratativa** (DSR confirmado, tempo de espera, macro errada…), que tira a pendência de "conferir".

## Regras

**Quem usa**
- **R1.** Ver exige `jornada.ver`; registrar tratativa exige `jornada.tratar`. Hoje: diretoria só vê; operação, frota/OPI e admin veem e tratam.
- **R2.** Cada pessoa vê só os motoristas das operações dela (motorista sem operação aparece para todos).

**Faixas e filtros (topo)**
- **R3.** Faixas clicáveis com a contagem: **Todos** (com controle de jornada), **Violação**, **Conferir**, **Atenção**, **Parado 35 h+**, **Em jornada agora**, **Tratados** (com tratativa nas últimas 24 h). Clicar filtra a tabela; clicar de novo limpa.
- **R4.** Filtro "dias seguidos sem descanso de 35 h": todos, 0–2, 3–5, 6, 7 ou mais. Busca por motorista, placa ou local. Opção "mostrar sem controle de jornada" (padrão: escondidos).
- **R5.** Ordem padrão: nível (violação, conferir, atenção, dentro) e, dentro do nível, mais dias sem DSR primeiro. Outras ordens: nome, dias sem DSR, horas na semana.

**Linha do motorista**
- **R6.** Mostra: nome e placa; **agora** (status com rótulo escrito); **jornada atual** (horas de trabalho com uma barra até 13 h e marcas em 8, 10 e 12 h, nas cores dentro/atenção/violação da operação); **parado no mesmo local** (horas, desde quando e onde); **descanso semanal** (dias sem DSR com destaque em 6 e 7, e a data do último DSR); **semana** (horas de trabalho na semana); **alertas** (até 3, com "+N"); **tratativa** (a última, com quem e quando).
- **R7.** Nenhum alerta aparece só pela cor: sempre com o texto (ex.: "Direção contínua de 6h10 (máx. 5h30)").

**Detalhe (abrir a linha)**
- **R8.** Mostra: as jornadas dos últimos 8 dias (dia, início, fim, horas líquidas, refeição, direção, maior direção contínua, interjornada, situação e motivos); as paradas de 11 h ou mais (período, horas, local, se contou como DSR e por quê não); as últimas 20 macros (hora, macro, local), com as **macros desconhecidas** marcadas.
- **R9.** O detalhe mostra também as tratativas anteriores do motorista.

**Tratativa**
- **R10.** Tipos: DSR confirmado (descanso), Tempo de espera (conta jornada), Macro errada – corrigir, Jornada correta, Orientado / advertido, Outro. Observação até 1.000 caracteres; obrigatória quando o tipo é "Outro".
- **R11.** A tratativa pode ser da jornada (uma jornada sem fim ou inconsistente) ou do motorista (parado 35 h, km sem jornada, outro login). Ela **não altera** o cálculo: fica ao lado e tira o "conferir" correspondente (motor-jornada R24).
- **R12.** Tratativa não se edita nem se apaga: uma nova substitui a anterior na tela, e todas ficam no histórico.

**Atualização**
- **R13.** A tela mostra a hora do último cálculo do motor ("Retrato das 09:39") e se atualiza a cada 60 s.

**Registro**
- **R14.** Tratativa grava `controle.auditoria` (`jornada.tratativa`), com o autor.

## Quem pode

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| Ver a tela e o detalhe | ✅ | ✅ | ✅ | — | — | ✅ |
| Registrar tratativa | — | ✅ | ✅ | — | — | ✅ |

## Fluxo

1. O motor (`derivado.job_jornada`) recalcula depois de cada ingestão e atualiza `motorista_situacao`.
2. A tela consulta `GET /api/jornada/motoristas` e `GET /api/jornada/resumo` a cada 60 s.
3. Abrir uma linha: `GET /api/jornada/motorista?id=`.
4. Registrar tratativa: `POST /api/jornada/tratativa` `{ motorista, jornada?, tipo, observacao }` → `sp_tratativa_criar` → recalcula a situação daquele motorista (`int_jornada_motorista`) para o "conferir" sumir na hora.

| Rota | Função |
|---|---|
| `GET jornada/motoristas?faixa=&dias=&q=&semcontrole=` | `sp_jornada_listar` |
| `GET jornada/resumo` | `sp_jornada_resumo` (contagens das faixas e hora do retrato) |
| `GET jornada/motorista?id=` | `sp_jornada_detalhe` |
| `POST jornada/tratativa` | `sp_tratativa_criar` |

## Como verificar

- [x] **V1 (R1, R2).** Central e TI: 403. Diretoria vê, mas o botão de tratativa não aparece e a rota dá 403. Pessoa de outra operação não vê o motorista.
- [x] **V2 (R3, R5).** Com motoristas fictícios em violação, conferir, atenção e dentro, a faixa conta certo e a tabela sai na ordem.
- [x] **V3 (R4).** Filtro de 7+ dias e busca por placa funcionam; "sem controle" só aparece com a opção ligada.
- [x] **V4 (R6, R7).** A linha mostra jornada atual, parado, dias sem DSR, semana e os alertas com texto.
- [x] **V5 (R8, R9).** O detalhe traz as jornadas de 8 dias, as paradas (com o motivo de não contar como DSR) e as macros, com a desconhecida marcada.
- [x] **V6 (R10, R11).** Tratativa "DSR confirmado" num motorista "parado 35 h com jornada aberta" tira o "conferir" na hora; "Outro" sem observação é recusado.
- [x] **V7 (R12, R14).** Duas tratativas seguidas: a tela mostra a última, o histórico as duas, e a auditoria tem as duas linhas.
- [ ] **V8 (manual).** Tela a 1366 e 1920 px; funciona a 390 px sem rolagem lateral.

## Fora do escopo

Jornada Ipiranga pelo Datapar (depende da aprovação) · editar ou corrigir macros (é na Autotrac) · exportar para planilha (backlog) · a regra de exceção de DSR para viagem longa (em aberto no motor).

## Em aberto

- [ ] As faixas e colunas do painel do Rafael estão todas aqui? Falta alguma que a equipe usa todo dia? (Rafael)
- [ ] Central também precisa ver a jornada (para saber se o motorista do alerta está em descanso)? Hoje ela vê só o status dentro do alerta. (Michael)
- [ ] Tratativa "Orientado / advertido" deve virar registro para a OPI do mês? (Natanael)

Conferido em 23/11/2026 (local): V1–V7 em `tests/sql/06_jornada_tela.sql` com `tests/dados/jornada-ficticio.sql` (6/6 conjuntos ok); rotas `api-jornada` por curl. Ajustes no motor feitos junto: "parado 35 h com jornada aberta" passa a valer também para jornada "sem fim", e refeição em andamento não conta como "refeição curta". **Não conferido:** a tela logada no navegador e V8 (larguras).
