# Estudo: API do Moovsec (Intelbras) — câmeras

**Fonte:** documentação pública https://developers.moovsec.com/api-docs (v1.9.0), lida em 26/11/2026. Base da spec `ingestao-moovsec.md` (a criar). Hoje a TIC exporta CSV (ver `bruto.moovsec_alarme`); a API substitui o CSV.

## Como funciona

- **Servidor próprio:** o Moovsec roda num servidor da instalação (a documentação fala em "raiz do Moovsec" e serviços locais). Precisamos do **endereço do Moovsec da TIC** (URL base da API).
- **Login:** `POST /auth/login` com `{ login, password }` → token **JWT**; nas chamadas seguintes `Authorization: Bearer <token>`.
- **Duas formas de receber os alarmes:**
  1. **Consultar (pull):** `POST /alarm/all` com filtros e paginação, a cada N minutos.
  2. **Receber (push, webhook):** o "webhook-adapter" do Moovsec envia cada alarme, GPS e evidência por HTTP para um endereço nosso, quase em tempo real, com até 10 retentativas. Precisa ser **instalado e configurado no servidor do Moovsec** (script `update.sh`, com sudo) — depende da TI da TIC / Intelbras.

## Recursos que interessam

| Recurso | O que faz | Para quê |
|---|---|---|
| `POST /alarm/all` | lista alarmes com filtro: veículos, motoristas, período (ISO 8601 + fuso ±HH:MM), tipos, status, criticidade (0 baixa, 1 média, 2 alta), busca; paginação `page`/`limit` | ingestão da Central de alertas |
| `GET /alarm/{id}` | alarme completo | detalhe |
| `GET /alarm/getEvidenceDownloadFile/{alarmId}` | links da evidência (vídeo e miniatura; campo `ready` diz se já está disponível) | quadro/vídeo na Central |
| `PATCH /alarm/updateStatus` | muda o status no Moovsec: 0 não tratado, 1 resolvido, 2 alarme falso, com texto | **devolver ao Moovsec** o que a Central decidiu (só se a TIC quiser; é escrita) |
| `GET /vehicle/all/{active}` | veículos (placa, frotas) | de-para placa → `cadastro.veiculo.serial_dvr` |
| Driver, AlarmType, Fleet, GPS, Video (seções 7, 10, 11, 14, 20) | motoristas, tipos de alarme, frotas, posições, vídeo | a detalhar quando tivermos acesso |

Webhook (eventos enviados): `alarms`, `gps`, `deviceConnectionStatus`, `deviceNetworkStatus`, `progressAlarmEvidence`, `alarmEvidence`, `progressExport`. Filtros por veículo e por tipo de alarme ("lista vazia não libera nenhum alarme"). Entrega pode repetir e vir fora de ordem: deduplicar pelo `_id` do alarme (`Idempotency-Key`).

## Como encaixa no projeto

- **Começar pelo pull** (`/alarm/all` a cada 1–2 min pelo n8n): não depende de instalar nada no servidor do Moovsec.
- **Webhook depois**, se a TIC/Intelbras instalar o adapter: endpoint nosso `/api/ingest/moovsec` (token de integração, regra 2 de exceção do `sub-autorizar`), grava no `bruto.moovsec_alarme` com o mesmo parser.
- Evidência: guardar só o link e o `ready`; o vídeo fica no Moovsec (LGPD e espaço).

## Perguntas para a TIC

1. **URL do Moovsec da TIC** e versão (a doc é da 1.9.0).
2. Um **usuário só para a integração**, com acesso a todos os veículos e só leitura (se existir papel assim). Senha direto no `.env` da VPS.
3. O servidor do Moovsec **aceita conexões da VPS** (187.53.119.147)? Está na internet ou só na rede da TIC?
4. Dá para **instalar o webhook-adapter**? Quem administra o servidor (TI da TIC ou Intelbras)?
5. A Central deve **devolver o status** ao Moovsec (resolvido / alarme falso), ou só lemos?
6. Pedir a **collection do Postman** à Intelbras ("Entre em contato com o time").
