// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {UAIFAISBTRegistry} from "../src/UAIFAISBTRegistry.sol";

/**
 * @title UAIFAISBTRegistry.t.sol
 * @notice Testes Foundry para o contrato UAIFAISBTRegistry.
 *
 * Executar: forge test -vvv
 */
contract UAIFAISBTRegistryTest is Test {
    UAIFAISBTRegistry registry;

    address admin    = address(0xA01);
    address alice    = address(0xA02);
    address bob      = address(0xA03);
    address quilombo = address(0xA04);

    function setUp() public {
        vm.prank(admin);
        registry = new UAIFAISBTRegistry(admin);
    }

    function test_IssueSBT() public {
        vm.prank(admin);
        uint256 sbtId = registry.issueSBT(
            alice,
            "CURSO-BLC-01",
            '{"title":"Blockchain Avancado","territory":"","gps":"","date":"2026-06-01"}',
            false
        );

        assertEq(sbtId, 1);
        assertEq(registry.sbtHolder(sbtId), alice);
        assertTrue(registry.hasSBTForCourse(alice, "CURSO-BLC-01"));
        assertFalse(registry.hasSBTForCourse(bob, "CURSO-BLC-01"));
    }

    function test_IssueSBT_WithGPS_Quilombola() public {
        vm.prank(admin);
        registry.issueSBT(
            quilombo,
            "EVENTO-QUILOMBO-KALUNGA-01",
            '{"title":"Assembleia Kalunga","territory":"Quilombo Kalunga","gps":"-13.5,-47.2","date":"2026-06-15","organizer":"Liderana Local"}',
            true
        );

        UAIFAISBTRegistry.SBT[] memory sbts = registry.getSBTs(quilombo);
        assertEq(sbts.length, 1);
        assertTrue(sbts[0].hasGPS);
        assertEq(sbts[0].courseId, "EVENTO-QUILOMBO-KALUNGA-01");
    }

    function test_RevertIf_NonOwnerIssuesSBT() public {
        vm.prank(alice);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        registry.issueSBT(bob, "CURSO", "metadata", false);
    }

    function test_MultipleSBTsPerHolder() public {
        vm.startPrank(admin);
        registry.issueSBT(alice, "CURSO-A", "{}", false);
        registry.issueSBT(alice, "CURSO-B", "{}", false);
        vm.stopPrank();

        UAIFAISBTRegistry.SBT[] memory sbts = registry.getSBTs(alice);
        assertEq(sbts.length, 2);
        assertTrue(registry.hasSBTForCourse(alice, "CURSO-A"));
        assertTrue(registry.hasSBTForCourse(alice, "CURSO-B"));
        assertFalse(registry.hasSBTForCourse(alice, "CURSO-C"));
    }
}
