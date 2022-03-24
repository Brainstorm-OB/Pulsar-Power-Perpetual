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

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { PPTraderConstants } from "./PPTraderConstants.sol";
import { BaseMath } from "../../lib/BaseMath.sol";
import { Math } from "../../lib/Math.sol";
import { PPGetters } from "../impl/PPGetters.sol";
import { PPBalanceMath } from "../lib/PPBalanceMath.sol";
import { PPTypes } from "../lib/PPTypes.sol";


/**
 * @title PPLiquidation
 * @author Pulsar
 *
 * @notice Contract allowing accounts to be liquidated by other accounts.
 */
contract PPLiquidation is
    PPTraderConstants
{
    using SafeMath for uint256;
    using Math for uint256;
    using PPBalanceMath for PPTypes.Balance;

    // ============ Structs ============

    struct TradeData {
        uint256 amount;
        bool isBuy; // from taker's perspective
        bool allOrNothing; // if true, will revert if maker's position is less than the amount
    }

    // ============ Events ============

    event LogLiquidated(
        address indexed maker,
        address indexed taker,
        uint256 amount,
        bool isBuy, // from taker's perspective
        uint256 oraclePrice
    );

    // ============ Immutable Storage ============

    // address of the power perpetual contract
    address public _POWER_PERPETUAL_;

    // ============ Constructor ============

    constructor (
        address perpetual
    )
        public
    {
        _POWER_PERPETUAL_ = perpetual;
    }

    // ============ External Functions ============

    /**
     * @notice Allows an account below the minimum collateralization to be liquidated by another
     *  account. This allows the account to be partially or fully subsumed by the liquidator.
     * @dev Emits the LogLiquidated event.
     *
     * @param  sender  The address that called the trade() function on PowerPerpetual.
     * @param  maker   The account to be liquidated.
     * @param  taker   The account of the liquidator.
     * @param  price   The current oracle price of the underlying asset.
     * @param  data    A struct of type TradeData.
     * @return         The amounts to be traded, and flags indicating that a liquidation occurred.
     */
    function trade(
        address sender,
        address maker,
        address taker,
        uint256 price,
        bytes calldata data,
        bytes32 /* traderFlags */
    )
        external
        returns (PPTypes.TradeResult memory)
    {
        address perpetual = _POWER_PERPETUAL_;

        require(
            msg.sender == perpetual,
            "msg.sender must be PowerPerpetual"
        );

        require(
            PPGetters(perpetual).getIsGlobalOperator(sender),
            "Sender is not a global operator"
        );

        TradeData memory tradeData = abi.decode(data, (TradeData));
        PPTypes.Balance memory makerBalance = PPGetters(perpetual).getAccountBalance(maker);

        _verifyTrade(
            tradeData,
            makerBalance,
            perpetual,
            price
        );

        // Bound the execution amount by the size of the maker position.
        uint256 amount = Math.min(tradeData.amount, makerBalance.position);

        // When partially liquidating the maker, maintain the same position/margin ratio.
        // Ensure the collateralization of the maker does not decrease.
        uint256 marginAmount;
        if (tradeData.isBuy) {
            marginAmount = uint256(makerBalance.margin).getFractionRoundUp(
                amount,
                makerBalance.position
            );
        } else {
            marginAmount = uint256(makerBalance.margin).getFraction(amount, makerBalance.position);
        }

        emit LogLiquidated(
            maker,
            taker,
            amount,
            tradeData.isBuy,
            price
        );

        return PPTypes.TradeResult({
            marginAmount: marginAmount,
            positionAmount: amount,
            isBuy: tradeData.isBuy,
            traderFlags: TRADER_FLAG_LIQUIDATION
        });
    }

    // ============ Helper Functions ============

    function _verifyTrade(
        TradeData memory tradeData,
        PPTypes.Balance memory makerBalance,
        address perpetual,
        uint256 price
    )
        private
        view
    {
        require(
            _isUndercollateralized(makerBalance, perpetual, price),
            "Cannot liquidate since maker is not undercollateralized"
        );
        require(
            !tradeData.allOrNothing || makerBalance.position >= tradeData.amount,
            "allOrNothing is set and maker position is less than amount"
        );
        require(
            tradeData.isBuy == makerBalance.positionIsPositive,
            "liquidation must not increase maker's position size"
        );

        // Disallow liquidating in the edge case where both the position and margin are negative.
        //
        // This case is not handled correctly by PPTrade. If an account is in this situation, the
        // margin should first be set to zero via a deposit, then the account should be deleveraged.
        require(
            makerBalance.marginIsPositive || makerBalance.margin == 0 ||
                makerBalance.positionIsPositive || makerBalance.position == 0,
            "Cannot liquidate when maker position and margin are both negative"
        );
    }

    function _isUndercollateralized(
        PPTypes.Balance memory balance,
        address perpetual,
        uint256 price
    )
        private
        view
        returns (bool)
    {
        uint256 minCollateral = PPGetters(perpetual).getMinCollateral();
        (uint256 positive, uint256 negative) = balance.getPositiveAndNegativeValue(price);

        // See PPSettlement.sol for discussion of overflow risk.
        return positive.mul(BaseMath.base()) < negative.mul(minCollateral);
    }
}
