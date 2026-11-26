# Spec: Ingestão da Autotrac

**Status:** implementada localmente (26/11; spec aprovada pelo Marcus em 26/11): Telemetria e fase B (ATIC), com sandbox · **Marco:** 2 · **Atualizada em:** 2026-11-26
**Telas:** nenhuma nova (status na tela Admin · Integrações, spec `admin.md`) · **Tabelas:** lê e grava `cadastro.veiculo`, `cadastro.motorista`, `bruto.ingestao_lote`, `bruto.autotrac_evento`, `bruto.autotrac_posicao`, `bruto.autotrac_macro`, `bruto.autotrac_login`, `controle.credencial_status`; novas `controle.evento_mapa`, `controle.saneamento` · **Workflows:** `ing-autotrac-cadastro`, `ing-autotrac-telemetria`, `ing-autotrac-atic-cadastro`, `ing-autotrac-atic` · **Funções:** `job_autotrac_veiculos`, `job_autotrac_eventos`, `job_autotrac_posicoes`, `job_autotrac_macros`, `job_autotrac_logins`, `job_lote_abrir`, `job_lote_fechar`
**Base:** `../estudo-api-atic.md` (as duas APIs, o que os painéis do Rafael usam, o mapa de macros), roteiro V2 (Autotrac é a fonte da verdade da jornada; de-para com fila de saneamento no Admin).

## O que faz

Traz os dados da Autotrac para o banco do painel, sozinha, de tempos em tempos, sem ninguém exportar planilha. Da **API de Telemetria** (acesso confirmado em 25/11) vêm a frota e os eventos de condução (freada e aceleração bruscas, excesso de velocidade e de RPM, banguela, marcha lenta…) e os eventos de câmera da Autotrac (ADAS/SDS). Da **API ATIC** (fase B, depende da liberação) vêm as posições, as macros de jornada e o login do motorista. Tudo cai nas tabelas `bruto.*` como veio; o motor de jornada, a correlação e a Central leem dali. O que não casa com o cadastro (placa que não existe, motorista desconhecido) vai para uma fila de saneamento, não some.

## Regras

**Acesso**
- **R1.** Credenciais (URL, chave, usuário, senha) só no `.env` da VPS e na credencial do n8n. Nunca em log, em `ingestao_lote.erro`, em auditoria ou no git.
- **R2.** O login é `Authorization: Basic usuário:senha` **em texto puro** (formato da Autotrac) + `Ocp-Apim-Subscription-Key`. Só GET: a ingestão nunca altera nada na Autotrac (nem a lista de unidades autorizadas).
- **R3.** Toda chamada grava o resultado em `controle.credencial_status` (`autotrac`): último sucesso, último erro (sem dado sensível). Resposta 401/403 marca `senha_mudou = true` e para o ciclo até alguém corrigir.

**Cadastro (frota)**
- **R4.** A cada `autotrac.cadastro.intervalo_min` (padrão 60) busca todos os veículos da conta, página a página (100 por página, até `IsLastPage`).
- **R5.** A placa sai do `Name` do veículo: o primeiro trecho no formato de placa (antiga ou Mercosul), sem hífen. Ex.: `ATG8098` → ATG8098; `AUC5017 - VENDIDO` → AUC5017.
- **R6.** Placa que existe em `cadastro.veiculo` → grava o código da Autotrac em `id_autotrac`. Placa nova → **não cria** veículo: vai para `controle.saneamento` ("placa da Autotrac sem cadastro"). Nome sem placa (só número do equipamento) → saneamento ("veículo da Autotrac sem placa").
- **R6a.** Exceção decidida pelo Marcus em 26/11/2026 (sem planilha de frota da TIC): uma carga única (`cadastro.job_autotrac_cadastrar_frota`) cadastra as placas que estão no saneamento como "placa sem cadastro", **só as limpas** (placa válida, sem repetição, sem anotação), como cavalo, origem autotrac, sem operação, com o código ligado; os itens atendidos ficam "resolvidos" e tudo vai para a auditoria. Anotadas, repetidas e sem placa continuam no saneamento. A operação de cada veículo a TIC ajusta no Admin.
- **R7.** Nome com "VENDIDO" ou "ANTIGA" vai para o saneamento como aviso e **não recebe o código** (evita que um equipamento antigo ocupe a placa); não desativa nada sozinho.
- **R8.** Um código da Autotrac nunca aponta para dois veículos; um veículo nunca tem dois códigos ativos. Conflito → saneamento, e a ingestão daquele veículo para até resolver.

**Eventos de telemetria e de câmera (API de Telemetria)**
- **R9.** A cada `autotrac.telemetria.intervalo_min` (padrão 5) busca, para cada veículo com `id_autotrac`, os eventos de telemetria (`alltelemetryevents`) e os de câmera (`safetydrivingevents`) desde o último horário recebido daquele veículo, com sobreposição de `autotrac.telemetria.sobreposicao_min` (padrão 10) para não perder evento atrasado.
- **R10.** A janela de cada chamada tem no máximo `autotrac.janela_max_h` (padrão 24 h). Se o painel ficou parado, recupera em várias janelas até alcançar o agora, **no máximo 7 dias para trás** (o que a Autotrac guarda). Perda acima de 7 dias vira erro no lote ("dados perdidos de … a …").
- **R11.** Gravação idempotente: rodar o mesmo período duas vezes não duplica nada (chave: veículo + horário + tipo; para câmera, o `ID` do evento).
- **R12.** O tipo do evento vem de `controle.evento_mapa` (fonte, número ou nome do evento → tipo interno, ex.: 4 → `freada_brusca`). Evento com número/nome sem mapa é gravado com tipo `desconhecido` e o número original em `dados`, e vai para o saneamento ("tipo de evento sem mapa"): nunca é descartado.
- **R13.** `dados` guarda o registro original da Autotrac (para reprocessar), **sem CPF**.
- **R14.** O motorista do evento vem do `DriverID` da Autotrac ligado a `cadastro.motorista.codigo_autotrac`. Código desconhecido → evento entra sem motorista e o código vai para o saneamento ("motorista da Autotrac sem cadastro").
- **R15.** Vídeo de evento de câmera: guarda só o hash/link do vídeo (`VideoHash`); o vídeo fica na Autotrac e é buscado só quando alguém abrir o evento (fora do escopo desta spec).

**Fase B: API ATIC (quando liberada)**
- **R16.** Posições (`positions`) a cada `autotrac.atic.intervalo_min` (padrão 5), com as mesmas regras R9–R11; hodômetro **÷ 100**; `DirectionGPS` inválido é descartado; janela máxima 72 h.
- **R17.** Macros (`returnmessages` com `MacroNumber > 0`) → `bruto.autotrac_macro`; o significado vem de `controle.macro_mapa` (o motor já usa). Mensagem livre (`MacroNumber = 0`) não entra.
- **R18.** Login e logout (`driverlogs`) → `bruto.autotrac_login`; `LogoutTime` em 1970 = ainda logado (não grava logout). O login da ATIC **não traz código do motorista**, só nome e CPF: liga pelo nome (exatamente um motorista ativo com esse nome, sem diferença de maiúscula/espaço); senão vai para o saneamento. Provisório até a decisão sobre o CPF (Em aberto). Os logins viram `derivado.sessao_motorista` (quem dirigia, de um login até o próximo logout ou login), que dá o motorista de cada macro.
- **R18a.** Cada API tem o seu código de veículo: Telemetria em `cadastro.veiculo.id_autotrac`, ATIC em `id_autotrac_atic`. Na frota da ATIC a placa vem do campo `LicensePlate` (e do nome, se faltar).
- **R18b.** Macro com número sem significado em `controle.macro_mapa` é gravada e vai para o saneamento (`macro_sem_mapa`): é assim que os números reais das macros da TIC aparecem para alguém mapear.
- **R19.** Depois de gravar macros e logins de um ciclo, chama o motor de jornada (`job_jornada`) só para os motoristas afetados.

**Registro**
- **R20.** Cada ciclo abre e fecha um `bruto.ingestao_lote` (fonte, janela buscada, linhas gravadas, estado, erro sem dado sensível). Ciclo que dá erro em um veículo continua nos outros e fecha o lote como `erro` com a lista dos veículos que falharam.
- **R21.** Sem sucesso há mais de `autotrac.alerta_sem_dados_min` (padrão 30) → a tela de Integrações e a Central mostram "Autotrac sem dados desde HH:MM" (não esconde o problema).

## Quem pode

Ingestão é rotina do sistema (sem usuário). A fila de saneamento e o status da integração aparecem na tela **Admin · Integrações** (spec `admin.md`), para `ti` e `admin`.

| Ação | diretoria | operação | frota_opi | central | ti | admin |
|---|---|---|---|---|---|---|
| Ver status da integração e o saneamento | — | — | — | — | ✅ | ✅ |
| Resolver item do saneamento (ligar placa/código) | — | — | — | — | ✅ | ✅ |

## Fluxo

1. **`ing-autotrac-cadastro`** (agendado, R4): `sub-autotrac` busca as páginas de veículos → `job_autotrac_veiculos(lote, itens)` aplica R5–R8.
2. **`ing-autotrac-telemetria`** (agendado, R9): `job_lote_abrir` devolve a lista de veículos com o "desde" de cada um → para cada veículo, `sub-autotrac` busca eventos e eventos de câmera (paginado) → `job_autotrac_eventos(lote, veiculo, itens)` grava (R11–R14) → `job_lote_fechar`.
3. **`ing-autotrac-atic`** (fase B): o mesmo para posições, macros e logins, e no fim `job_jornada` dos afetados (R19).
4. **`sub-autotrac`**: monta os cabeçalhos (R2), faz a chamada, pagina, devolve os registros; em 401/403 grava R3 e interrompe.

O n8n só busca e entrega a lista; **toda regra (placa, mapa, deduplicação, saneamento) fica nas funções `job_*` do banco** (regra 3 do projeto).

## Como verificar

- [x] **V1 (R5).** `ATG8098`, `AUC5017 - VENDIDO`, `AUT7540 UCC ANTIGA`, `ABC1D23` viram as placas certas; `340685` não vira placa.
- [x] **V2 (R6, R7).** Placa cadastrada ganha `id_autotrac`; placa nova e nome sem placa vão para o saneamento; nenhum veículo é criado nem desativado.
- [x] **V3 (R8).** Dois veículos da Autotrac com a mesma placa → saneamento e nenhum dos dois recebe código.
- [x] **V4 (R11).** Gravar o mesmo lote de eventos duas vezes → mesma contagem de linhas.
- [x] **V5 (R12).** Evento com número sem mapa entra como `desconhecido`, com o número em `dados`, e aparece no saneamento.
- [x] **V6 (R13).** Nenhuma linha de `bruto.autotrac_evento.dados` contém a chave `DriverCPF`.
- [x] **V7 (R14).** `DriverID` conhecido liga o motorista; desconhecido entra sem motorista e vai para o saneamento.
- [x] **V8 (R9, R10).** Com o último evento de um veículo há 3 dias, o ciclo busca em janelas de 24 h até agora; há 9 dias, busca 7 dias e fecha o lote com "dados perdidos".
- [x] **V9 (R3).** Resposta 401 (simulada) → `senha_mudou = true`, ciclo interrompido, erro sem a senha.
- [ ] **V10 (R1).** Procurar a senha e a chave em `bruto.ingestao_lote`, `controle.credencial_status`, `controle.auditoria` e nos logs do n8n → nada encontrado.
- [x] **V11 (R20).** Falha num veículo (simulada) → os outros gravam e o lote fecha como `erro` citando o veículo.
- [x] **V12 (manual).** Contra o **sandbox** da Autotrac: ciclo completo grava veículos e eventos fictícios.
- [ ] **V13 (manual).** Contra a **produção** (o Marcus roda): contagem de veículos e de eventos das últimas 24 h bate com o que o Postman mostra.
- [x] **V14 (R16–R19, fase B).** Posições com hodômetro ÷ 100; macro 0 ignorada; logout de 1970 não gravado; motor recalcula o motorista afetado.

## Fora do escopo

Enviar mensagem ou acionar sirene (a API não faz; prova técnica do Marco 1 em aberto) · baixar ou mostrar vídeo (fica para a Central) · alterar a lista de unidades autorizadas · alertas expandidos de OBC (falta o "Dicionário_Alerta_Expandido") · áreas de informação (`informationregionslog`, vai para a spec `torre.md`) · Jornada Business como fonte de violações prontas (depende da resposta do Rafael) · a tela de saneamento em si (spec `admin.md`).

## Em aberto

- [ ] **Tabela de eventos → tipo e gravidade.** Quais eventos de telemetria e de câmera viram alerta, e com que gravidade? (Michael / Rafael). Enquanto isso, todos são gravados e nenhum abre alerta sozinho.
- [ ] **Nomes dos eventos ADAS/SDS** que a frota da TIC gera (só se sabe olhando os dados reais: V13).
- [ ] **Limite de chamadas da Autotrac.** Com N veículos × 2 chamadas a cada 5 min, cabe? (Autotrac, via Michael). O intervalo é parâmetro e pode subir.
- [ ] **A ATIC está liberada para esta chave/usuário?** (teste do Marcus; senão, pedir à Autotrac).
- [ ] **CPF:** guardar o CPF do motorista para o de-para com o Rodopar (roteiro V2), ou ligar só pela matrícula/código? Se guardar, como (cifrado ou só o hash)? (Michael, LGPD).
- [ ] **Quantos veículos estão na lista de unidades autorizadas** e se os ~158 motoristas do painel do Rafael estão todos lá (Michael).
- [ ] **Datas:** confirmar se a Telemetria interpreta `_dateTimeFrom` sem fuso como UTC (a documentação diz UTC; conferir no V13).

Conferido em 26/11/2026 (local): V1–V9 e V11 em `tests/sql/07_ingestao_autotrac.sql` (7/7 conjuntos ok); V12 com os workflows `ing-autotrac-cadastro` e `ing-autotrac-telemetria` no n8n local contra o sandbox da Autotrac (credencial fictícia): frota buscada, os 2 veículos sem placa foram para o saneamento; eventos de telemetria e de câmera buscados e descartados por estarem fora dos 7 dias (o sandbox devolve eventos de 2024). Ajustes vindos do teste: a paginação para também quando a página vem com menos de 100 registros (o sandbox ignora `_offset`) e erro sem código HTTP conta como falha. **Não conferido:** V10 (procurar a senha nos logs: só com a credencial real), V13 (produção, quem roda é o Marcus) e V14 (fase B). Os workflows têm também o gatilho "Executar agora" para forçar uma busca.

Conferido em 26/11/2026 (local), fase B: V14 em `tests/sql/08_ingestao_atic.sql` (8/8 conjuntos ok): frota pelo `LicensePlate`, códigos separados por API, login ligado pelo nome (homônimo vai para o saneamento), logout de 1970 ignorado, sessão aberta, posição com hodômetro ÷ 100, macro 0 ignorada, macro com o motorista da sessão, macro sem mapa no saneamento, fim do ciclo liga a macro atrasada e recalcula a jornada. Workflows `ing-autotrac-atic-cadastro` e `ing-autotrac-atic` contra o sandbox da ATIC: 9 chamadas ok, posição e macro gravadas, logins de 2018 descartados, macro 27 no saneamento.

R6a conferida em 26/11/2026 em `tests/sql/07_ingestao_autotrac.sql` (cadastra a placa limpa, liga o código, resolve o saneamento, audita, não toca na duplicada, idempotente).
