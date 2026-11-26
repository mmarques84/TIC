# Montagem: VPS e containers

Mesmo padrão do Elysium (`E:\ProjetoParticular\Elysium\docs\setup-vps-hostinger.md`), com servidor, repositório e credenciais próprios da TIC.

## O que roda na VPS

```
Internet ──443──► caddy (HTTPS automático)
                    ├── /api/*  ──► n8n:5678  (webhooks; editor do n8n NUNCA exposto)
                    └── /*      ──► frontend:80 (Angular compilado, nginx)
                 n8n ──► postgres:5432 (rede interna "dados", sem porta pública)
                 n8n ──► Autotrac API, servidor Moovsec, API do Claude (saída)
```

| Container | Imagem | Para quê | Porta exposta |
|---|---|---|---|
| `postgres` | `postgis/postgis:17-3.5` | Banco (dados, regras, auditoria) | só `127.0.0.1:5433` (túnel SSH) |
| `n8n` | `n8nio/n8n` (versão fixada no `.env`) | API `/api/*`, ingestões agendadas, IA | só `127.0.0.1:5678` (túnel SSH) |
| `frontend` | build do `frontend/` (nginx) | Portal Angular | interna |
| `caddy` | `caddy:2` | HTTPS, proxy, cabeçalhos de segurança | 80, 443 |
| `migrador` | `postgis/postgis:17-3.5` (perfil `migrar`) | Aplica migrations e recria funções | — (só quando chamado) |

Volumes nomeados: `pg_dados`, `n8n_dados`, `caddy_dados`. **Nunca `docker compose down -v`.**

## Banco: como fica por dentro

```
tic (database)
├── acesso     usuario, perfil, permissao, sessao
├── cadastro   operacao, base, veiculo, conjunto, motorista, cliente
├── bruto      autotrac_posicao*, autotrac_evento*, autotrac_macro, autotrac_login, moovsec_alarme*, ingestao_lote
├── derivado   sessao_motorista, jornada, interjornada, parada, motorista_situacao, evento*, evento_frame, alerta, acao, tratativa
├── ia         triagem, opi_modelo, opi_modelo_item, opi, opi_resposta, consumo
└── controle   parametro, auditoria, credencial_status, fila_acao
                                                    * particionada por mês
```

Usuários do Postgres:
- `tic_dono`: dono das tabelas e funções (sem login).
- `tic_n8n`: só `EXECUTE` nas `sp_*`, `job_*` e funções de ingestão; sem `SELECT/INSERT/UPDATE` direto nas tabelas.
- `tic_leitura`: só leitura, para consultas de suporte por túnel.

## Situação da VPS (26/11/2026)

- **No ar:** https://paineldigital.tic.com.br (DNS da TIC → 187.53.119.147, VPS Hostinger `srv2168185`, Ubuntu 26.04). HTTPS automático pelo Caddy.
- **Acesso:** `ssh -i ~/.ssh/tic_vps tic@187.53.119.147` (usuário `tic` com sudo e docker). Projeto em `/opt/tic` (cópia do commit em `/opt/tic/VERSAO`; sem git no servidor: enviar com `git archive HEAD | ssh ... tar -x -C /opt/tic`). `.env` gerado no servidor (chmod 600); **copiar os segredos para o cofre da TIC**.
- **Feito:** firewall (22, 80, 443), fail2ban, atualizações automáticas, fuso UTC; postgres, n8n, front e caddy; 13 migrations; workflows da API publicados; primeiro admin por link (`scripts/criar-primeiro-admin.sh`); backup diário 03:15 UTC em `/opt/tic-backups` (14 dias, `scripts/backup.sh`).
- **Falta:** ingestão da Autotrac (credencial real no `.env` da VPS + `scripts/n8n-credencial-autotrac.sh` + publicar `ing-autotrac-*`), liberar o IP da VPS na Autotrac; cópia do backup para fora da VPS e teste de restauração; dono do n8n (túnel `ssh -L 5678:127.0.0.1:5678`); desligar login do root por senha quando ninguém mais depender dele.

## Passo a passo na VPS (dia 1)

1. **Acesso:** usuário `tic` com sudo e chave SSH; `PermitRootLogin no` e `PasswordAuthentication no` (arquivo próprio em `/etc/ssh/sshd_config.d/00-tic.conf`); firewall só 22, 80, 443; `unattended-upgrades` e `fail2ban`; fuso UTC.
2. **Docker:** Engine + Compose plugin; `tic` no grupo `docker`.
3. **Projeto:** clone em `/opt/tic` (chave de deploy somente leitura); `.env` gerado no servidor (`openssl rand -base64 32` por segredo), `chmod 600`; cópia dos segredos no cofre da TIC.
4. **Subir:** `docker compose up -d postgres n8n frontend caddy`; conferir `docker compose ps`.
5. **DNS:** registro A do subdomínio (ex.: `painel.tic.com.br`, pedir ao Flávio) → IP da VPS; enquanto não houver, usar o nome `srvXXXX.hstgr.cloud`.
6. **n8n:** pelo túnel `ssh -L 5678:127.0.0.1:5678 tic@<vps>`, criar o dono com MFA; credencial Postgres com `tic_n8n`.
7. **Banco:** `docker compose run --rm migrador` (backup antes, sempre).
8. **Backup:** cron diário `pg_dump -Fc` + export dos workflows, cifrado, copiado para fora da VPS; snapshot semanal da Hostinger; **uma restauração testada** antes de entrar dado real.
9. **Firewall da TIC:** passar o IP da VPS ao Flávio para liberar o servidor Moovsec.

## Ingestão da Autotrac (spec ingestao-autotrac)

- **VPS:** `AUTOTRAC_USUARIO`, `AUTOTRAC_SENHA` e `AUTOTRAC_CHAVE` no `.env` → `sh scripts/n8n-credencial-autotrac.sh` → `sh scripts/publicar-n8n.sh` (publica e ativa `ing-autotrac-cadastro` e `ing-autotrac-atic-cadastro`, de hora em hora, e `ing-autotrac-telemetria` e `ing-autotrac-atic`, a cada 5 min). Os parâmetros `autotrac.url_*` e `autotrac.conta_*` já vêm com a produção (conferir `autotrac.conta_atic` no primeiro acesso).
- **Computador do dev (sandbox, dados fictícios):** `sh scripts/n8n-credencial-autotrac.sh --sandbox` e, no banco local, `autotrac.url_telemetria` = `https://wapi.autotrac-online.com.br/sandboxtelemetryapi` e `autotrac.conta_telemetria` = `3253`; `autotrac.url_atic` = `https://wapi.autotrac-online.com.br/sandboxaticapi` e `autotrac.conta_atic` = `801`; ligar um veículo fictício aos códigos `262763` (`id_autotrac`) e `540` (`id_autotrac_atic`). Nunca usar a credencial real no computador do dev.
- **Forçar uma busca:** `docker compose exec -e N8N_RUNNERS_BROKER_PORT=5699 -e N8N_PORT=5690 n8n n8n execute --id=TicIngAutotracEv` (ou `TicIngAutotracCa`).
- **Conferir:** `bruto.ingestao_lote` (estado de cada ciclo), `controle.credencial_status` (último sucesso/erro), `controle.saneamento` (o que não casou com o cadastro).

## Nunca

- `docker compose down -v` · expor 5432 ou 5678 na internet · commitar `.env` · copiar `material-cliente/` para a VPS sem necessidade.
