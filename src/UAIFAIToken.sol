// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title UAIFAIToken
 * @notice Moeda comunitária da plataforma USP Iconomy.
 *
 * Implementa o algoritmo ARIGATO CREATION conforme documentação UAIFAI v1.0:
 *   incremento_remetente = tokens_enviados × (tokens_enviados / saldo_atual)
 *   novo_saldo_remetente = saldo_atual - tokens_enviados + incremento
 *   saldo_destinatário   = saldo_destinatário + tokens_enviados
 *
 * Adicionalmente:
 *   - Mensagem obrigatória (mín. 10 chars) em cada transferência  [RN-02]
 *   - Decaimento semanal por inatividade, floor em 0              [RN-01, RN-05]
 *   - Taxa diferenciada para comunidades quilombolas              [RN-07]
 *   - Distribution Code para inclusão de novos membros            [RF-09]
 *
 * SBTs de participação [RN-04, RF-05, RF-12] vivem em um contrato separado,
 * UAIFAISBTRegistry.sol, por não movimentarem saldo nem serem transferíveis.
 *
 * Deploy target: Sepolia testnet (EVM chain-id 11155111)
 *
 * Nota sobre o PCECommunityToken original (peacecoin-protocol/core):
 *   O contrato de produção roda em Polygon com padrão Beacon Proxy (UUPS upgradeable).
 *   Para testes em Sepolia adotamos um contrato autônomo não-upgradeable, mantendo
 *   a mesma lógica de negócio. Ao migrar para produção, envolver com o padrão
 *   Beacon da USP/Peace Coin conforme script/Deploy.s.sol do repositório core.
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UAIFAIToken is ERC20, Ownable {
    error MessageTooShort();
    error InsufficientBalance();
    error InvalidCode();
    error CodeExpired();
    error CodeExhausted();
    error AlreadyQuilombola();
    error SelfTransferNotAllowed();

    /// @notice Intervalo entre aplicações de decaimento (padrão: 7 dias)
    uint256 public decayInterval = 7 days;
    /// @notice Taxa de decaimento padrão em basis points (100 bp = 1%)
    uint256 public decayRateBps = 1000;
    /// @notice Taxa de decaimento diferenciada para quilombolas (bp)
    uint256 public quilombolaDecayRateBps = 200; 
    /// @notice Mínimo de caracteres exigido na mensagem de envio [RN-02]
    uint256 public constant MIN_MESSAGE_LENGTH = 10;

    mapping(address => uint256) private _lastActivity;
    mapping(address => bool) public isQuilombola;

    //  Distribution Codes [RF-09]
    struct DistributionCode {
        bytes32 codeHash;        // keccak256(code) — só o hash é armazenado
        uint256 tokensPerRedeem; // tokens creditados por resgate
        uint256 maxRedeems;      // limite de resgates (0 = ilimitado)
        uint256 redeemCount;     // contador atual
        uint256 validFrom;
        uint256 validUntil;
        string courseId;         // vínculo opcional a curso
        bool active;
    }

    uint256 private _codeCounter;
    mapping(uint256 => DistributionCode) public distributionCodes;
    mapping(uint256 => mapping(address => bool)) public hasRedeemed;

    //  Circulação histórica (para acesso Tipo 2)
    mapping(address => mapping(uint256 => uint256)) public circulation30d;

    event TokensSentWithMessage(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 bonus,
        string message,
        uint8 sentiment // 0=neutral,1=positive,2=negative (classificado off-chain, registrado on-chain)
    );
    event DecayApplied(address indexed wallet, uint256 before, uint256 after_);
    event DistributionCodeCreated(uint256 indexed codeId, uint256 tokensPerRedeem, uint256 validUntil);
    event DistributionCodeRedeemed(uint256 indexed codeId, address indexed redeemer, uint256 tokens);
    event QuilombolaActivated(address indexed member);

    //  Constructor
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address admin_
    ) ERC20(name_, symbol_) Ownable(admin_) {
        _mint(admin_, initialSupply_);
        _lastActivity[admin_] = block.timestamp;
    }

    //  ARIGATO CREATION — transferência com mensagem
    /**
     * @notice Envia tokens com mensagem obrigatória.
     *         Aplica o algoritmo ARIGATO CREATION:
     *         bonus = amount × (amount / saldo_atual)
     *         O bônus vai para o REMETENTE, não para o destinatário.
     *
     * @param to        Destinatário
     * @param amount    Quantidade de tokens a enviar
     * @param message   Mensagem descritiva (mín. 10 chars) [RN-02]
     * @param sentiment Classificação (0=neutro,1=positivo,2=negativo)  enviado pelo backend
     */
    function sendWithMessage(
        address to,
        uint256 amount,
        string calldata message,
        uint8 sentiment
    ) external {
        if (bytes(message).length < MIN_MESSAGE_LENGTH) revert MessageTooShort();
        if (to == msg.sender) revert SelfTransferNotAllowed();

        address from = msg.sender;
        uint256 senderBalance = balanceOf(from);

        if (senderBalance < amount) revert InsufficientBalance();

        // Calcula bônus ARIGATO (escalonado para evitar overflow com fixed-point ×1e18)
        uint256 bonus = (amount * amount) / senderBalance;
        // Burn do valor enviado do remetente
        _burn(from, amount);
        // Mint bônus de volta ao remetente (supply cresce exatamente = bonus)
        _mint(from, bonus);
        // Mint do valor recebido para o destinatário
        _mint(to, amount);
        // Registra circulação histórica (janela de 30 dias)
        uint256 window = block.timestamp / 30 days;
        circulation30d[from][window] += amount;
        // Atualiza timestamp de atividade
        _lastActivity[from] = block.timestamp;
        _lastActivity[to]   = block.timestamp;

        emit TokensSentWithMessage(from, to, amount, bonus, message, sentiment);
    }

    //  Decaimento [RN-01, RN-05, RN-07]
    /**
     * @notice Aplica decaimento por inatividade a uma wallet.
     *         Pode ser chamado por qualquer um (keeper off-chain / backend USP).
     *         Floor absoluto em 0 tokens [RN-05].
     */
    function applyDecay(address wallet) external {
        _applyDecay(wallet);
    }

    /// @notice Aplica decaimento em batch para reduzir custo operacional
    function applyDecayBatch(address[] calldata wallets) external {
        for (uint256 i = 0; i < wallets.length; i++) {
            _applyDecay(wallets[i]);
        }
    }

    function _applyDecay(address wallet) internal {
        uint256 last = _lastActivity[wallet];
        if (last == 0) return; // wallet nunca ativa

        uint256 elapsed = block.timestamp - last;
        if (elapsed < decayInterval) return; // ainda dentro do intervalo

        uint256 periods = elapsed / decayInterval;
        uint256 bal = balanceOf(wallet);
        if (bal == 0) return;

        uint256 rateBps = isQuilombola[wallet] ? quilombolaDecayRateBps : decayRateBps;

        // Decaimento composto: bal_final = bal × (1 - rate)^periods
        uint256 remaining = bal;
        uint256 maxPeriods = periods > 52 ? 52 : periods; 
        for (uint256 i = 0; i < maxPeriods; i++) {
            remaining = remaining - (remaining * rateBps) / 10_000;
        }

        uint256 toBurn = bal - remaining;
        if (toBurn > 0) {
            _burn(wallet, toBurn);
            emit DecayApplied(wallet, bal, remaining);
        }

        // Avança o timestamp em múltiplos de decayInterval para não saltar
        _lastActivity[wallet] = last + (periods * decayInterval);
    }

    //  Distribution Codes [RF-09, RF-10, RN-06]
    /**
     * @notice Cria um Distribution Code (bolsa de acesso).
     *         Apenas o owner (administrador USP) pode criar.
     *
     * @param codeHash       keccak256(abi.encodePacked(plainCode)) — calculado off-chain
     * @param tokensPerRedeem Quantidade de tokens por resgate
     * @param maxRedeems     Limite de resgates (0 = ilimitado)
     * @param validFrom      Timestamp de início
     * @param validUntil     Timestamp de expiração [RN-06]
     * @param courseId       Curso vinculado (pode ser "" para código genérico)
     */
    function createDistributionCode(
        bytes32 codeHash,
        uint256 tokensPerRedeem,
        uint256 maxRedeems,
        uint256 validFrom,
        uint256 validUntil,
        string calldata courseId
    ) external onlyOwner returns (uint256 codeId) {
        codeId = ++_codeCounter;
        distributionCodes[codeId] = DistributionCode({
            codeHash: codeHash,
            tokensPerRedeem: tokensPerRedeem,
            maxRedeems: maxRedeems,
            redeemCount: 0,
            validFrom: validFrom,
            validUntil: validUntil,
            courseId: courseId,
            active: true
        });
        emit DistributionCodeCreated(codeId, tokensPerRedeem, validUntil);
    }

    /**
     * @notice Resgata um Distribution Code.
     *         O usuário passa o código em texto simples; o contrato verifica o hash.
     *
     * @param codeId    ID do código (fornecido pelo parceiro / USP)
     * @param plainCode Código em texto claro (o hash é verificado on-chain)
     */
    function redeemDistributionCode(uint256 codeId, string calldata plainCode) external {
        DistributionCode storage dc = distributionCodes[codeId];

        if (!dc.active) revert InvalidCode();
        if (dc.codeHash != keccak256(abi.encodePacked(plainCode))) revert InvalidCode();
        if (block.timestamp < dc.validFrom || block.timestamp > dc.validUntil) revert CodeExpired();
        if (dc.maxRedeems > 0 && dc.redeemCount >= dc.maxRedeems) revert CodeExhausted();
        if (hasRedeemed[codeId][msg.sender]) revert CodeExhausted();

        dc.redeemCount++;
        hasRedeemed[codeId][msg.sender] = true;

        _mint(msg.sender, dc.tokensPerRedeem);
        _lastActivity[msg.sender] = block.timestamp;

        emit DistributionCodeRedeemed(codeId, msg.sender, dc.tokensPerRedeem);
    }

    //  Modo Quilombola [RN-07, RF-12]
    /**
     * @notice Ativa o modo UAIFAI quilombola para um membro verificado.
     *         Taxa de decaimento reduzida conforme [RN-07].
     *         Apenas o owner (admin USP) pode verificar.
     */
    function activateQuilombola(address member) external onlyOwner {
        if (isQuilombola[member]) revert AlreadyQuilombola();
        isQuilombola[member] = true;
        emit QuilombolaActivated(member);
    }

    //  Consulta de circulação (para acesso Tipo 2)
    /**
     * @notice Retorna tokens circulados por um endereço nos últimos 30 dias.
     *         Critério de acesso a cursos Tipo 2 [RN-03].
     */
    function circulatedLast30Days(address holder) external view returns (uint256) {
        uint256 currentWindow = block.timestamp / 30 days;
        return circulation30d[holder][currentWindow];
    }

    /**
     * @notice Verifica se holder atende o critério de circulação para um curso Tipo 2.
     * @param holder       Candidato à matrícula
     * @param minCirculated Mínimo de tokens circulados exigido pelo professor
     */
    function meetsCirculationCriteria(
        address holder,
        uint256 minCirculated
    ) external view returns (bool, uint256 actual) {
        uint256 currentWindow = block.timestamp / 30 days;
        actual = circulation30d[holder][currentWindow];
        return (actual >= minCirculated, actual);
    }

    //  Configuração administrativa
    function setDecayInterval(uint256 interval_) external onlyOwner {
        decayInterval = interval_;
    }

    function setDecayRates(uint256 defaultBps_, uint256 quilombolaBps_) external onlyOwner {
        decayRateBps = defaultBps_;
        quilombolaDecayRateBps = quilombolaBps_;
    }

    function deactivateDistributionCode(uint256 codeId) external onlyOwner {
        distributionCodes[codeId].active = false;
    }

    /// @notice Mint direto para emissões iniciais / administration (Fase 0)
    function adminMint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        _lastActivity[to] = block.timestamp;
    }

    //  Overrides ERC20 — registra atividade
    /**
     * @dev Overridamos _update (OZ v5) para registrar atividade em transferências normais.
     *      UAIFAI tokens circulantes SÃO transferíveis — diferente dos SBTs.
     *      Transferências normais NÃO aplicam ARIGATO (só sendWithMessage aplica).
     */
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from != address(0)) _lastActivity[from] = block.timestamp;
        if (to != address(0))   _lastActivity[to]   = block.timestamp;
    }

    //  View helpers
    function lastActivity(address wallet) external view returns (uint256) {
        return _lastActivity[wallet];
    }

    function version() external pure returns (string memory) {
        return "1.1.0-sepolia-uaifai";
    }
}
