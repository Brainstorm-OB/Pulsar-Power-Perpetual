/*

    Copyright 2021 Pulsar Trading Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

*/

pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import { Storage } from "../lib/Storage.sol";
import { PPAdmin } from "./impl/PPAdmin.sol";
import { PPFinalSettlement } from "./impl/PPFinalSettlement.sol";
import { PPGetters } from "./impl/PPGetters.sol";
import { PPMargin } from "./impl/PPMargin.sol";
import { PPOperator } from "./impl/PPOperator.sol";
import { PPTrade } from "./impl/PPTrade.sol";
import { PPTypes } from "./lib/PPTypes.sol";


/**
 * @title PowerPerpetual
 * @author Pulsar
 *
 * @notice A market for a power perpetual contract, a financial derivative which may be traded on margin
 *  and which aims to closely track the spot power price (x**p) of an underlying asset. The underlying asset is
 *  specified via the price oracle which reports its spot price. Tethering of the power perpetual market
 *  price is supported by a funding oracle which governs funding payments between longs and shorts.
 * @dev Main power perpetual market implementation contract that inherits from other contracts.
 */
contract PowerPerpetual is
    PPFinalSettlement,
    PPAdmin,
    PPGetters,
    PPMargin,
    PPOperator,
    PPTrade
{
    // Non-colliding storage slot.
    bytes32 internal constant POWER_PERPETUAL_INITIALIZE_SLOT =
    bytes32(uint256(keccak256("Pulsar.PowerPerpetual.initialize")) - 1);

    /**
     * @dev Once-only initializer function that replaces the constructor since this contract is
     *  proxied. Uses a non-colliding storage slot to store if this version has been initialized.
     * @dev Can only be called once and can only be called by the admin of this contract.
     *
     * @param  token          The address of the token to use for margin-deposits.
     * @param  oracle         The address of the price oracle contract.
     * @param  funder         The address of the funder contract.
     * @param  minCollateral  The minimum allowed initial collateralization percentage.
     */
    function initialize(
        address token,
        address oracle,
        address funder,
        uint256 minCollateral
    )
        external
        onlyAdmin
        nonReentrant
    {
        // only allow initialization once
        require(
            Storage.load(POWER_PERPETUAL_INITIALIZE_SLOT) == 0x0,
            "PowerPerpetual already initialized"
        );
        Storage.store(POWER_PERPETUAL_INITIALIZE_SLOT, bytes32(uint256(1)));

        _TOKEN_ = token;
        _ORACLE_ = oracle;
        _FUNDER_ = funder;
        _MIN_COLLATERAL_ = minCollateral;

        _GLOBAL_INDEX_ = PPTypes.Index({
            timestamp: uint32(block.timestamp),
            isPositive: false,
            value: 0
        });
    }
}
