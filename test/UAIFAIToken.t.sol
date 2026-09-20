// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {UAIFAIToken} from "../src/UAIFAIToken.sol";

/**
 * @title UAIFAIToken.t.sol
 * @notice Testes Foundry para o contrato UAIFAIToken.
 *
 * Executar: forge test -vvv
 */
contract UAIFAITokenTest is Test {
    UAIFAIToken token;

    address admin   = address(0xA01);
    address alice   = address(0xA02); // aluna com histórico
    address bob     = address(0xA03); // professor
    address quilombo = address(0xA04); // membro quilombola
    address newcomer = address(0xA05); // novo sem histórico

    uint256 constant INITIAL = 1_000_000 ether;
    uint256 constant ALICE_START = 200 ether;
    uint256 constant BOB_START   = 80 ether;

    function setUp() public {
        vm.prank(admin);
        token = new UAIFAIToken("UAIFAI Token", "UAIFAI", INITIAL, admin);

        // Distribui tokens para alice e bob via adminMint
        vm.startPrank(admin);
        token.adminMint(alice, ALICE_START);
        token.adminMint(bob, BOB_START);
        vm.stopPrank();
    }

    //  ARIGATO CREATION
    function test_SendWithMessage_ArigatoCreation() public {
        uint256 amount = 50 ether;
        uint256 expectedBonus = (amount * amount) / ALICE_START; // 12.5 ether

        uint256 supplyBefore = token.totalSupply();

        vm.prank(alice);
        token.sendWithMessage(bob, amount, "Obrigada pelo curso incrivel!", 1);

        // Alice: 200 - 50 + 12.5 = 162.5
        assertEq(token.balanceOf(alice), 162.5 ether, "Saldo alice incorreto");
        // Bob: 80 + 50 = 130
        assertEq(token.balanceOf(bob), 130 ether, "Saldo bob incorreto");
        // Supply cresce pelo bonus
        assertEq(token.totalSupply(), supplyBefore + expectedBonus, "Supply deve crescer pelo bonus");
    }

    function test_LowerBalance_GetsHigherProportionalBonus() public {
        // quilombo com saldo 60 envia 50 — bonus proporcional maior
        vm.prank(admin);
        token.adminMint(quilombo, 60 ether);

        uint256 amount = 50 ether;
        uint256 expectedBonus = (amount * amount) / 60 ether; // ~41.67 ether

        vm.prank(quilombo);
        token.sendWithMessage(bob, amount, "Gratidao pela sabedoria!", 1);

        // bonus > 12.5 ether (o do cenário com saldo 200)
        assertGt(expectedBonus, 12.5 ether, "Bonus proporcional deve ser maior para quem tem menos");
        // quilombo: 60 - 50 + 41.67 = 51.67
        assertApproxEqAbs(token.balanceOf(quilombo), 51.67 ether, 0.01 ether);
    }

    function test_RevertIf_MessageTooShort() public {
        vm.prank(alice);
        vm.expectRevert(UAIFAIToken.MessageTooShort.selector);
        token.sendWithMessage(bob, 10 ether, "curto", 0); // menos de 10 chars
    }

    function test_RevertIf_InsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(UAIFAIToken.InsufficientBalance.selector);
        token.sendWithMessage(bob, 500 ether, "Mensagem longa o suficiente aqui", 0);
    }

    function test_RevertIf_SelfTransfer() public {
        // alice tenta enviar para si mesma para duplicar o proprio saldo via bonus
        vm.prank(alice);
        vm.expectRevert(UAIFAIToken.SelfTransferNotAllowed.selector);
        token.sendWithMessage(alice, ALICE_START, "Tentando duplicar meu proprio saldo", 0);
    }

    function test_CirculationTracking() public {
        vm.prank(alice);
        token.sendWithMessage(bob, 50 ether, "Agradecimento pela aula!", 1);

        uint256 circulated = token.circulatedLast30Days(alice);
        assertEq(circulated, 50 ether, "Circulacao 30d incorreta");

        (bool meets, uint256 actual) = token.meetsCirculationCriteria(alice, 40 ether);
        assertTrue(meets, "Deve atender criterio de 40");
        assertEq(actual, 50 ether);

        (bool fails,) = token.meetsCirculationCriteria(alice, 100 ether);
        assertFalse(fails, "Nao deve atender criterio de 100");
    }

   //  Decaimento
    function test_Decay_ReducesSaldoAfterInterval() public {
        // Avança 7 dias
        vm.warp(block.timestamp + 7 days + 1);

        uint256 balBefore = token.balanceOf(alice); // 200
        token.applyDecay(alice);
        uint256 balAfter = token.balanceOf(alice);

        // 10% de 200 = 20 tokens de decaimento → 180
        assertEq(balAfter, 180 ether, "Decaimento padrao 10% incorreto");
    }

    function test_Decay_QuilombolaRateIsLower() public {
        vm.prank(admin);
        token.activateQuilombola(quilombo);
        vm.prank(admin);
        token.adminMint(quilombo, 200 ether);

        vm.warp(block.timestamp + 7 days + 1);

        uint256 balBefore = token.balanceOf(quilombo);
        token.applyDecay(quilombo);
        uint256 balAfter = token.balanceOf(quilombo);

        // 2% de 200 = 4 tokens → 196
        assertEq(balAfter, 196 ether, "Decaimento quilombola 2% incorreto");
        assertGt(balAfter, 180 ether, "Quilombola deve decair menos que padrao");
    }

    function test_Decay_FloorAtZero() public {
        // Membro com saldo 1 wei — decaimento não pode ir negativo
        vm.prank(admin);
        token.adminMint(newcomer, 1);

        // Avança 100 semanas
        vm.warp(block.timestamp + 700 days + 1);
        token.applyDecay(newcomer);

        assertGe(token.balanceOf(newcomer), 0, "Saldo nao pode ser negativo");
    }

    function test_Decay_NotApplied_BeforeInterval() public {
        vm.warp(block.timestamp + 3 days);
        uint256 balBefore = token.balanceOf(alice);
        token.applyDecay(alice);
        assertEq(token.balanceOf(alice), balBefore, "Decaimento nao deve ocorrer antes do intervalo");
    }

    //  Distribution Code

    function test_CreateAndRedeemDistributionCode() public {
        string memory plainCode = "QUILOMBO-KALUNGA-2026";
        bytes32 codeHash = keccak256(abi.encodePacked(plainCode));

        vm.prank(admin);
        uint256 codeId = token.createDistributionCode(
            codeHash,
            150 ether,      // 150 tokens por resgate
            10,             // max 10 resgates
            block.timestamp,
            block.timestamp + 30 days,
            "CURSO-QUILOMBOLA-01"
        );

        uint256 balBefore = token.balanceOf(newcomer);

        vm.prank(newcomer);
        token.redeemDistributionCode(codeId, plainCode);

        assertEq(token.balanceOf(newcomer), balBefore + 150 ether, "Tokens creditados incorretamente");

        // Não pode resgatar duas vezes
        vm.prank(newcomer);
        vm.expectRevert(UAIFAIToken.CodeExhausted.selector);
        token.redeemDistributionCode(codeId, plainCode);
    }

    function test_DistributionCode_RejectWrongCode() public {
        bytes32 codeHash = keccak256(abi.encodePacked("CODIGO-CERTO"));
        vm.prank(admin);
        uint256 codeId = token.createDistributionCode(
            codeHash, 100 ether, 5,
            block.timestamp, block.timestamp + 30 days, ""
        );

        vm.prank(newcomer);
        vm.expectRevert(UAIFAIToken.InvalidCode.selector);
        token.redeemDistributionCode(codeId, "CODIGO-ERRADO");
    }

    function test_DistributionCode_ExpiredCode() public {
        bytes32 codeHash = keccak256(abi.encodePacked("CODIGO-VENCIDO"));
        vm.prank(admin);
        uint256 codeId = token.createDistributionCode(
            codeHash, 100 ether, 5,
            block.timestamp, block.timestamp + 1 days, ""
        );

        // Avança além da validade
        vm.warp(block.timestamp + 2 days);

        vm.prank(newcomer);
        vm.expectRevert(UAIFAIToken.CodeExpired.selector);
        token.redeemDistributionCode(codeId, "CODIGO-VENCIDO");
    }

    //  Quilombola

    function test_ActivateQuilombola() public {
        vm.prank(admin);
        token.activateQuilombola(quilombo);
        assertTrue(token.isQuilombola(quilombo));
    }

    function test_RevertIf_ActivateQuilombolaTwice() public {
        vm.prank(admin);
        token.activateQuilombola(quilombo);

        vm.prank(admin);
        vm.expectRevert(UAIFAIToken.AlreadyQuilombola.selector);
        token.activateQuilombola(quilombo);
    }
}
