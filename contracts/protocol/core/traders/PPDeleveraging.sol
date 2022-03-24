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
import { Ownable } from "@openzeppelin/contracts/ownership/Ownable.sol";
import { PPTraderConstants } from "./PPTraderConstants.sol";
import { Math } from "../../lib/Math.sol";
import { PPGetters } from "../impl/PPGetters.sol";
import { I_PPOracle } from "../intf/I_PPOracle.sol";
import { PPBalanceMath } from "../lib/PPBalanceMath.sol";
import { PPTypes } from "../lib/PPTypes.sol";


/**
 * @title PPDeleveraging
 * @author Pulsar
 *
 * @notice Contract allowing underwater accounts to be deleveraged against offsetting accounts.
 */
contract PPDeleveraging is
    Ownable,
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

    event LogDeleveraged(
        address indexed maker,
        address indexed taker,
        uint256 amount,
        bool isBuy, // from taker's perspective
        uint256 oraclePrice
    );

    event LogMarkedForDeleveraging(
        address indexed account
    );

    event LogUnmarkedForDeleveraging(
        address indexed account
    );

    event LogDeleveragingOperatorSet(
        address deleveragingOperator
    );

    // ============ Immutable Storage ============

    // address of the power perpetual contract
    address public _POWER_PERPETUAL_;

    // Waiting period for non-admin to deleverage an account after marking it.
    uint256 constant public DELEVERAGING_TIMELOCK_S = 1800; // 30 minutes

    // ============ Mutable Storage ============

    // account => timestamp at which an account was marked as underwater
    //
    // After an account has been marked for the timelock period, it can be deleveraged by anybody.
    // The contract admin can deleverage underwater accounts at any time.
    mapping (address => uint256) public _MARKED_TIMESTAMP_;

    // Address which has the ability to deleverage accounts without marking them first.
    address public _DELEVERAGING_OPERATOR_;

    // ============ Constructor ============

    constructor (
        address perpetual,
        address deleveragingOperator
    )
        public
    {
        _POWER_PERPETUAL_ = perpetual;
        _DELEVERAGING_OPERATOR_ = deleveragingOperator;

        emit LogDeleveragingOperatorSet(deleveragingOperator);
    }

    // ============ External Functions ============

    /**
     * @notice Allows an underwater (less than 100% collateralization) account to be subsumed by any
     *  other account with an offsetting position (a position of opposite sign). The sender must be
     *  the privileged deleveraging operator unless the account has been marked as underwater for
     *  the timelock period.
     * @dev Emits the LogDeleveraged event. May emit the LogUnmarkedForDeleveraging event.
     *
     * @param  sender  The address that called the trade() function on PowerPerpetual.
     * @param  maker   The underwater account.
     * @param  taker   The offsetting account.
     * @param  price   The current oracle price of the underlying asset.
     * @param  data    A struct of type TradeData.
     * @return         The amounts to be traded, and flags indicating that deleveraging occurred.
     */
    function trade(
        address sender,
        address maker,
        address taker,
        uint256 price,
        bytes calldata data,
        bytes32 traderFlags
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
            traderFlags == 0,
            "cannot deleverage after other trade operations, in the same tx"
        );

        _verifyPermissions(
            sender,
            maker
        );

        TradeData memory tradeData = abi.decode(data, (TradeData));
        PPTypes.Balance memory makerBalance = PPGetters(perpetual).getAccountBalance(maker);
        PPTypes.Balance memory takerBalance = PPGetters(perpetual).getAccountBalance(taker);

        _verifyTrade(
            tradeData,
            makerBalance,
            takerBalance,
            price
        );

        // Bound the execution amount by the size of the maker and taker positions.
        uint256 amount = Math.min(
            tradeData.amount,
            Math.min(makerBalance.position, takerBalance.position)
        );

        // When partially deleveraging the maker, maintain the same position/margin ratio.
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

        if (amount == makerBalance.position && _isMarked(maker)) {
            _unmark(maker);
        }

        emit LogDeleveraged(
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
            traderFlags: TRADER_FLAG_DELEVERAGING
        });
    }

    /**
     * @notice Mark an account as underwater. An account must be marked for a period of time before
     *  any non-admin is allowed to deleverage that account.
     * @dev Emits the LogMarkedForDeleveraging event.
     *
     * @param  account  The account to mark.
     */
    function mark(
        address account
    )
        external
    {
        require(
            _isAccountUnderwater(account),
            "Cannot mark since account is not underwater"
        );
        _MARKED_TIMESTAMP_[account] = block.timestamp;
        emit LogMarkedForDeleveraging(account);
    }

    /**
     * @notice Un-mark an account which is no longer underwater.
     * @dev Emits the LogUnmarkedForDeleveraging event.
     *
     * @param  account  The account to unmark.
     */
    function unmark(
        address account
    )
        external
    {
        require(
            !_isAccountUnderwater(account),
            "Cannot unmark since account is underwater"
        );
        _unmark(account);
    }

    /**
     * @notice Set the privileged deleveraging operator. Can only be called by the admin.
     * @dev Emits the LogFundingRateProviderSet event.
     *
     * @param  newOperator  The new operator, who will have the ability to deleverage accounts
     *                      without first marking them and waiting the timelock period.
     */
    function setDeleveragingOperator(
        address newOperator
    )
        external
        onlyOwner
    {
        _DELEVERAGING_OPERATOR_ = newOperator;
        emit LogDeleveragingOperatorSet(newOperator);
    }

    // ============ Helper Functions ============

    function _unmark(
        address account
    )
        private
    {
        _MARKED_TIMESTAMP_[account] = 0;
        emit LogUnmarkedForDeleveraging(account);
    }

    function _isMarked(
        address account
    )
        private
        view
        returns (bool)
    {
        return _MARKED_TIMESTAMP_[account] != 0;
    }

    function _verifyPermissions(
        address sender,
        address maker
    )
        private
        view
    {
        // The privileged deleveraging operator may deleverage underwater accounts at any time.
        if (sender != _DELEVERAGING_OPERATOR_) {
            uint256 markedTimestamp = _MARKED_TIMESTAMP_[maker];
            require(
                markedTimestamp != 0,
                "Cannot deleverage since account is not marked"
            );
            uint256 timeDelta = block.timestamp.sub(markedTimestamp);
            require(
                timeDelta >= DELEVERAGING_TIMELOCK_S,
                "Cannot deleverage since account has not been marked for the timelock period"
            );
        }
    }

    function _verifyTrade(
        TradeData memory tradeData,
        PPTypes.Balance memory makerBalance,
        PPTypes.Balance memory takerBalance,
        uint256 price
    )
        private
        pure
    {
        require(
            _isUnderwater(makerBalance, price),
            "Cannot deleverage since maker is not underwater"
        );
        require(
            !tradeData.allOrNothing || makerBalance.position >= tradeData.amount,
            "allOrNothing is set and maker position is less than amount"
        );
        require(
            takerBalance.positionIsPositive != makerBalance.positionIsPositive,
            "Taker position has wrong sign to deleverage this maker"
        );
        require(
            !tradeData.allOrNothing || takerBalance.position >= tradeData.amount,
            "allOrNothing is set and taker position is less than amount"
        );
        require(
            tradeData.isBuy == makerBalance.positionIsPositive,
            "deleveraging must not increase maker's position size"
        );

        // Disallow deleveraging in the edge case where both the position and margin are negative.
        //
        // This case is not handled correctly by PPTrade. If an account is in this situation, the
        // margin should first be set to zero via a deposit, then the account should be deleveraged.
        require(
            makerBalance.marginIsPositive || makerBalance.margin == 0 ||
                makerBalance.positionIsPositive || makerBalance.position == 0,
            "Cannot liquidate when maker position and margin are both negative"
        );
    }

    function _isUnderwater(
        PPTypes.Balance memory balance,
        uint256 price
    )
        private
        pure
        returns (bool)
    {
        (uint256 positive, uint256 negative) = balance.getPositiveAndNegativeValue(price);
        return positive < negative;
    }

    function _isAccountUnderwater(
        address account
    )
        private
        view
        returns (bool)
    {
        address perpetual = _POWER_PERPETUAL_;
        PPTypes.Balance memory balance = PPGetters(perpetual).getAccountBalance(account);
        address oracle = PPGetters(perpetual).getOracleContract();
        uint256 price = I_PPOracle(oracle).getPrice();
        return _isUnderwater(balance, price);
    }
}
