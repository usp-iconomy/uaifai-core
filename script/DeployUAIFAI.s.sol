// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UAIFAIToken} from "../src/UAIFAIToken.sol";

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

    function run() external {
        address admin = vm.envOr("USP_ADMIN_ADDRESS", msg.sender);
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        UAIFAIToken token = new UAIFAIToken(
            "UAIFAI Token",   // name
            "UAIFAI",         // symbol (☮ como string não é válido em ERC20)
            INITIAL_SUPPLY,
            admin
        );

        console.log("=== UAIFAI Token deployado ===");
        console.log("Endereco:        ", address(token));
        console.log("Admin/Owner:     ", admin);
        console.log("Supply inicial:  ", INITIAL_SUPPLY / 1e18, "UAIFAI");
        console.log("Rede:            Sepolia (chain-id 11155111)");
        console.log("");
        console.log("Proximos passos:");
        console.log("1. Configurar taxas: setDecayRates(1000, 200)  // 10% padrao, 2% quilombola");
        console.log("2. Criar Distribution Codes para piloto");
        console.log("3. Ativar membros quilombola: activateQuilombola(address)");
        console.log("4. Emitir primeiros SBTs apos conclusao de cursos");

        vm.stopBroadcast();
    }
}
