# UAIFAIToken — Contrato Inteligente para Sepolia

> Moeda comunitária da plataforma USP Iconomy · Algoritmo ARIGATO CREATION · Sepolia testnet

---

## Visão geral

O `UAIFAIToken.sol` implementa toda a lógica de negócio do token UAIFAI descrita na documentação técnica v1.0, **sem depender de infra externa além do blockchain**. É projetado para deploy em Sepolia e, após validação, migração para o padrão `PCECommunityToken` (Beacon Proxy) do repositório `peacecoin-protocol/core` em Polygon.

---

## O que o contrato implementa

| Feature | Spec | Status |
|---|---|---|
| ARIGATO CREATION (incremento proporcional ao remetente) | RF-07 | ✅ |
| Mensagem obrigatória (≥ 10 chars) | RN-02 | ✅ |
| Decaimento semanal por inatividade | RN-01 | ✅ |
| Floor em 0 (saldo nunca negativo) | RN-05 | ✅ |
| Taxa de decaimento diferenciada para quilombolas | RN-07 | ✅ |
| SBT de participação (não-transferível) | RN-04, RF-05 | ✅ |
| SBT com GPS para cursos presenciais/quilombola | RF-12 | ✅ (metadata) |
| Verificação de SBT de pré-requisito (Tipo 4) | RF-04 | ✅ |
| Circulação histórica de 30 dias (critério Tipo 2) | RN-03, RF-04 | ✅ |
| Distribution Code com validade e limite de resgates | RF-09, RN-06 | ✅ |
| Modo UAIFAI Quilombola | RF-12 | ✅ |
| Batch decay (keeper off-chain) | RF-07 | ✅ |

---

## Fórmula ARIGATO CREATION

```
bonus_remetente = amount × (amount / saldo_remetente)
saldo_remetente_final = saldo_remetente - amount + bonus
saldo_destinatário_final = saldo_destinatário + amount
supply_total_final = supply_total + bonus
```

**Propriedade redistributiva:** quem tem menos tokens e ainda assim circula recebe proporcionalmente mais de volta. Contrário ao capital financeiro convencional.

**Nota importante (corrige RF-06 da doc v1.0):** O incremento vai para o **remetente**, não para o destinatário. O destinatário recebe exatamente o valor enviado.

---

## Diferença em relação ao PCECommunityToken original

| Aspecto | PCECommunityToken (core) | UAIFAIToken (este) |
|---|---|---|
| Padrão proxy | Beacon Proxy (UUPS) | Sem proxy (testnet) |
| Rede alvo | Polygon mainnet | Sepolia testnet |
| Upgrade | Via `script/upgrade.sh` | Não upgradeable |
| Governança | DAO + Timelock | `onlyOwner` (admin USP) |
| SBT | Separado (outro contrato) | Separado (`UAIFAISBTRegistry.sol`) |
| Distribuição | Configurado via Explorer API | Direto no contrato |

Ao avançar para produção em Polygon:
1. Envolver `UAIFAISBTRegistry.sol` também no padrão do core, se necessário
2. Envolver `UAIFAIToken` no padrão Beacon Proxy do core
3. Substituir `onlyOwner` por role-based access control (AccessControl do OZ)
4. Conectar ao Explorer API para validações off-chain

---

## Setup e deploy em Sepolia

### Pré-requisitos

```bash
# Instalar Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clonar o repositório core do Peace Coin (como base)
git clone https://github.com/peacecoin-protocol/core
cd core
bun install
```

### Estrutura de arquivos

```
src/
  UAIFAIToken.sol          ← moeda de circulação (ARIGATO CREATION, decay, Distribution Code)
  UAIFAISBTRegistry.sol    ← registro de SBTs de participação (separado, não-transferível)
script/
  DeployUAIFAI.s.sol       ← script de deploy (token + registry)
test/
  UAIFAIToken.t.sol        ← testes do token
  UAIFAISBTRegistry.t.sol  ← testes do registro de SBTs
```

### Configurar variáveis de ambiente

```bash
cp .env.example .env
# Editar .env com:
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/<SUA_API_KEY>
DEPLOYER_PRIVATE_KEY=0x<CHAVE_PRIVADA_TESTNET>
USP_ADMIN_ADDRESS=0x<ENDERECO_ADMIN_USP>
ETHERSCAN_API_KEY=<PARA_VERIFICACAO>
```

### foundry.toml — adicionar Sepolia

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib", "node_modules"]

[rpc_endpoints]
sepolia = "${SEPOLIA_RPC_URL}"
polygon = "https://polygon-rpc.com"
amoy    = "https://rpc-amoy.polygon.technology"

[etherscan]
sepolia = { key = "${ETHERSCAN_API_KEY}", chain = 11155111 }
```

### Rodar testes locais

```bash
forge test -vvv
```

Saída esperada:
```
[PASS] test_SendWithMessage_ArigatoCreation()
[PASS] test_LowerBalance_GetsHigherProportionalBonus()
[PASS] test_RevertIf_MessageTooShort()
[PASS] test_RevertIf_InsufficientBalance()
[PASS] test_CirculationTracking()
[PASS] test_Decay_ReducesSaldoAfterInterval()
[PASS] test_Decay_QuilombolaRateIsLower()
[PASS] test_Decay_FloorAtZero()
[PASS] test_Decay_NotApplied_BeforeInterval()
[PASS] test_IssueSBT()
[PASS] test_IssueSBT_WithGPS_Quilombola()
[PASS] test_RevertIf_NonOwnerIssuesSBT()
[PASS] test_CreateAndRedeemDistributionCode()
[PASS] test_DistributionCode_RejectWrongCode()
[PASS] test_DistributionCode_ExpiredCode()
[PASS] test_ActivateQuilombola()
[PASS] test_RevertIf_ActivateQuilombolaTwice()
```

### Deploy em Sepolia

```bash
forge script script/DeployUAIFAI.s.sol \
  --broadcast \
  --fork-url sepolia \
  --interactives 1
```

### Verificar no Etherscan Sepolia

```bash
forge verify-contract <DEPLOYED_ADDRESS> UAIFAIToken \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

---

## Jornadas de teste no Sepolia

### 1. Testar ARIGATO CREATION

```bash
# Via cast (Foundry CLI)
cast send <TOKEN_ADDR> \
  "sendWithMessage(address,uint256,string,uint8)" \
  <BOB_ADDR> 50000000000000000000 "Obrigado pela aula incrivel!" 1 \
  --private-key $ALICE_KEY \
  --rpc-url $SEPOLIA_RPC_URL
```

### 2. Criar Distribution Code para piloto

```bash
# Calcular hash off-chain
CODE="UAIFAI-PILOTO-2026"
HASH=$(cast keccak "$CODE")

# Criar código: 150 tokens, 20 resgates, válido por 30 dias
cast send <TOKEN_ADDR> \
  "createDistributionCode(bytes32,uint256,uint256,uint256,uint256,string)" \
  $HASH 150000000000000000000 20 $(date +%s) $(($(date +%s) + 2592000)) "CURSO-01" \
  --private-key $ADMIN_KEY \
  --rpc-url $SEPOLIA_RPC_URL
```

### 3. Resgatar bolsa (novo membro)

```bash
cast send <TOKEN_ADDR> \
  "redeemDistributionCode(uint256,string)" \
  1 "UAIFAI-PILOTO-2026" \
  --private-key $NEWCOMER_KEY \
  --rpc-url $SEPOLIA_RPC_URL
```

### 4. Emitir SBT quilombola com GPS

```bash
cast send <SBT_REGISTRY_ADDR> \
  "issueSBT(address,string,string,bool)" \
  <MEMBER_ADDR> \
  "EVENTO-KALUNGA-01" \
  '{"title":"Assembleia Kalunga","territory":"Quilombo Kalunga","gps":"-13.5,-47.2","date":"2026-06-15"}' \
  true \
  --private-key $ADMIN_KEY \
  --rpc-url $SEPOLIA_RPC_URL
```

### 5. Aplicar decaimento em batch (keeper semanal)

```bash
cast send <TOKEN_ADDR> \
  "applyDecayBatch(address[])" \
  "[<ADDR1>,<ADDR2>,<ADDR3>]" \
  --private-key $KEEPER_KEY \
  --rpc-url $SEPOLIA_RPC_URL
```

---

## Pontos de atenção para auditoria

| Item | Risco | Mitigação |
|---|---|---|
| Overflow no cálculo do bonus | Médio | Solidity 0.8 reverte em overflow; testar com valores extremos |
| `applyDecayBatch` sem auth | Baixo | Decaimento só reduz — nunca beneficia chamador malicioso |
| `plainCode` visível no mempool | Médio | Usar commit-reveal scheme em produção; aceitável para testnet |
| Emissão ilimitada via `adminMint` | Alto | Em produção, substituir por multisig ou DAO Timelock |
| SBT não tem registro de transferência (impossível) | Design | Proposital — SBTs são não-transferíveis por ausência de função |

---

## Próximos passos (pós-Sepolia)

1. ~~**Extrair SBT** para `UAIFAISBTRegistry.sol` independente~~ ✅ feito
2. **Role-based access**: `MINTER_ROLE`, `DECAY_KEEPER_ROLE`, `QUILOMBOLA_VERIFIER_ROLE`
3. **Beacon Proxy**: migrar para o padrão do `peacecoin-protocol/core`
4. **Commit-reveal para Distribution Codes**: evitar front-running em mainnet
5. **Oracle de GPS**: integrar Chainlink Functions ou attestação off-chain assinada
6. **Explorer API**: conectar `meetsCirculationCriteria` ao Peace Coin Explorer via API Gateway

---

*USP Iconomy · Projeto UAIFAI Quilombola · 2026*
