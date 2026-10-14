// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UAIFAIToken} from "../src/UAIFAIToken.sol";
import {UAIFAISBTRegistry} from "../src/UAIFAISBTRegistry.sol";

/**
 * @title DeployUAIFAI
 * @notice Script de deploy para Sepolia testnet.
 *
 * Uso:
 *   forge script script/DeployUAIFAI.s.sol \
 *     --broadcast \
 *     --fork-url https://eth-sepolia.g.alchemy.com/v2/<API_KEY> \
 *     --interactives 1
 *
 * Variáveis de ambiente necessárias (no .env):
 *   SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/<API_KEY>
 *   DEPLOYER_PRIVATE_KEY=0x...
 *   USP_ADMIN_ADDRESS=0x...   (endereço do administrador USP)
 *
 * Após deploy, verificar no Etherscan Sepolia:
 *   forge verify-contract <DEPLOYED_ADDRESS> UAIFAIToken \
 *     --chain sepolia \
 *     --etherscan-api-key <API_KEY>
 */
contract DeployUAIFAI is Script {
    // Emissão inicial: 1.000.000 tokens (com 18 decimais)
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    // Configuração padrão de decaimento (IMPLEMENTATION.md §7.A1)
    uint256 constant DECAY_RATE_DEFAULT_BPS = 1000;      // 10%
    uint256 constant DECAY_RATE_QUILOMBOLA_BPS = 200;    // 2%
    uint256 constant DECAY_INTERVAL = 7 days;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        // Default: deployer == admin (piloto Sepolia).
        address admin = vm.envOr("USP_ADMIN_ADDRESS", deployer);

        vm.startBroadcast(deployerKey);

        UAIFAIToken token = new UAIFAIToken(
            "UAIFAI Token",   // name
            "UAIFAI",         // symbol (☮ como string não é válido em ERC20)
            INITIAL_SUPPLY,
            admin
        );

        UAIFAISBTRegistry sbtRegistry = new UAIFAISBTRegistry(admin);

        // Configuração administrativa (A1 DoD).
        // onlyOwner: só funciona se o deployer == admin. Se admin for outro
        // endereço, as duas chamadas abaixo precisam ser feitas por ele depois.
        if (admin == deployer) {
            token.setDecayRates(DECAY_RATE_DEFAULT_BPS, DECAY_RATE_QUILOMBOLA_BPS);
            token.setDecayInterval(DECAY_INTERVAL);
        }

        vm.stopBroadcast();

        console.log("=== UAIFAI Token deployado ===");
        console.log("Endereco:        ", address(token));
        console.log("SBT Registry:    ", address(sbtRegistry));
        console.log("Admin/Owner:     ", admin);
        console.log("Supply inicial:  ", INITIAL_SUPPLY / 1e18, "UAIFAI");
        console.log("Decay default:   ", DECAY_RATE_DEFAULT_BPS, "bps");
        console.log("Decay quilombola:", DECAY_RATE_QUILOMBOLA_BPS, "bps");
        console.log("Decay interval:  ", DECAY_INTERVAL, "segundos");
        console.log("Rede chain-id:   ", block.chainid);
        console.log("Bloco:           ", block.number);

        _writeDeployment(address(token), address(sbtRegistry), admin);

        if (admin != deployer) {
            console.log("");
            console.log("ATENCAO: admin != deployer. Rode como admin:");
            console.log("  cast send <token> 'setDecayRates(uint256,uint256)' 1000 200");
            console.log("  cast send <token> 'setDecayInterval(uint256)' 604800");
        }
    }

    function _writeDeployment(address token, address sbtRegistry, address admin) internal {
        // Nome do arquivo = <chain-id>.json (sepolia = 11155111).
        // Mantém versionado para a API consumir (IMPLEMENTATION.md §7.A1).
        string memory root = "deployment";
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "blockNumber", block.number);
        vm.serializeAddress(root, "admin", admin);
        vm.serializeAddress(root, "uaifaiToken", token);
        vm.serializeAddress(root, "sbtRegistry", sbtRegistry);
        vm.serializeUint(root, "decayRateDefaultBps", DECAY_RATE_DEFAULT_BPS);
        vm.serializeUint(root, "decayRateQuilombolaBps", DECAY_RATE_QUILOMBOLA_BPS);
        vm.serializeUint(root, "decayIntervalSeconds", DECAY_INTERVAL);
        vm.serializeUint(root, "initialSupply", INITIAL_SUPPLY);
        string memory json = vm.serializeString(root, "tokenVersion", UAIFAIToken(token).version());

        string memory path = string.concat(
            "deployments/",
            vm.toString(block.chainid),
            ".json"
        );
        vm.writeJson(json, path);
        console.log("Deployment gravado em:", path);
    }
}
