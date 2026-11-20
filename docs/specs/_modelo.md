# Spec: <Nome da funcionalidade>

**Status:** rascunho | aprovada | implementada · **Etapa:** 0 | 1 | 2 · **Atualizada em:** AAAA-MM-DD
**Telas:** `design/...` · **Tabelas:** `...` · **Workflows:** `api-...` · **Procedures:** `sp_...`

## O que faz

Um parágrafo, na linguagem da TIC: quem usa, para quê, de onde vem o dado, para onde vai.

## Regras

Frases curtas, uma regra por linha, cada uma testável. Numere para poder citar (R1, R2…).

- **R1.** Exemplo: todo alerta tem placa, horário UTC e, quando houver login, motorista.
- **R2.** Exemplo: só o perfil frota_opi valida uma OPI.
- **R3.** Exemplo: marcar falso positivo encerra o alerta, mas nunca o apaga.

## Quem pode

| Ação | diretoria | operação | frota_opi | ti | central |
|---|---|---|---|---|---|
| ver | ✅ | ✅ | ✅ | — | ✅ |
| agir | — | ✅ | ✅ | — | ✅ |

## Fluxo

Passo a passo do caminho principal (e dos desvios importantes). Desenho só se ajudar.

## Como verificar

Cada item vira teste automatizado (marque **manual** se não der). Cite a regra.

- [ ] **V1 (R1).** Criar ação sem responsável → erro "Informe um responsável".
- [ ] **V2 (R2).** CEO tenta resolver ação → 403.
- [ ] **V3.** Toda alteração gera linha em `auditoria`.
- [ ] **V4.** Sem sessão → 401.
- [ ] **V5 (manual).** Tela em 360 e 1280 px sem rolagem lateral.

## Fora do escopo

O que esta funcionalidade **não** faz (para não crescer sem querer).

## Em aberto

Perguntas sem resposta, com dono e onde serão respondidas. Não inventar a resposta.

- [ ] Exemplo: a prioridade é Alta/Normal ou Urgente/Importante/Outros? (Michael, Marco 1)
