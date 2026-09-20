// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title UAIFAISBTRegistry
 * @notice Registro de Soulbound Tokens (SBT) de participação da plataforma USP Iconomy.
 *
 * Separado do UAIFAIToken (moeda de circulação) porque não movimenta saldo
 * nem é transferível — é apenas um registro imutável por endereço de
 * conclusão de curso ou participação em evento presencial/quilombola
 * [RN-04, RF-05, RF-12].
 */

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UAIFAISBTRegistry is Ownable {
    struct SBT {
        uint256 id;
        string courseId;
        string metadata; // JSON-like: title, territory, gps, organizer, date
        uint256 issuedAt;
        bool hasGPS;
    }

    uint256 private _sbtCounter;
    mapping(address => SBT[]) private _sbtsByHolder;
    // sbtId → holder (para lookup reverso)
    mapping(uint256 => address) public sbtHolder;

    event SBTIssued(address indexed to, uint256 sbtId, string courseId, bool hasGPS);

    constructor(address admin_) Ownable(admin_) {}

    /**
     * @notice Emite um SBT de participação para um membro.
     *         Apenas o owner (administrador USP / backend autorizado) pode emitir.
     *
     * @param to        Titular do SBT
     * @param courseId  Identificador do curso ou evento
     * @param metadata  Dados estruturados (JSON): title, territory, gps, organizer, date
     * @param hasGPS    true se o SBT inclui coordenadas GPS (cursos presenciais / quilombola)
     */
    function issueSBT(
        address to,
        string calldata courseId,
        string calldata metadata,
        bool hasGPS
    ) external onlyOwner returns (uint256 sbtId) {
        sbtId = ++_sbtCounter;
        _sbtsByHolder[to].push(SBT({
            id: sbtId,
            courseId: courseId,
            metadata: metadata,
            issuedAt: block.timestamp,
            hasGPS: hasGPS
        }));
        sbtHolder[sbtId] = to;
        emit SBTIssued(to, sbtId, courseId, hasGPS);
    }

    /// @notice Retorna todos os SBTs de um titular
    function getSBTs(address holder) external view returns (SBT[] memory) {
        return _sbtsByHolder[holder];
    }

    /// @notice Verifica se holder possui SBT de um curso específico (pré-requisito Tipo 4)
    function hasSBTForCourse(address holder, string calldata courseId) external view returns (bool) {
        SBT[] memory sbts = _sbtsByHolder[holder];
        for (uint256 i = 0; i < sbts.length; i++) {
            if (keccak256(bytes(sbts[i].courseId)) == keccak256(bytes(courseId))) {
                return true;
            }
        }
        return false;
    }

    function version() external pure returns (string memory) {
        return "1.0.0-sepolia-uaifai-sbt";
    }
}
