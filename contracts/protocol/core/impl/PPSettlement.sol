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
import { PPStorage } from "./PPStorage.sol";
import { BaseMath } from "../../lib/BaseMath.sol";
import { SafeCast } from "../../lib/SafeCast.sol";
import { SignedMath } from "../../lib/SignedMath.sol";
import { I_PPFunder } from "../intf/I_PPFunder.sol";
import { I_PPOracle } from "../intf/I_PPOracle.sol";
import { PPBalanceMath } from "../lib/PPBalanceMath.sol";
import { PPIndexMath } from "../lib/PPIndexMath.sol";
import { PPTypes } from "../lib/PPTypes.sol";


/**
 * @title PPSettlement
 * @author Pulsar
 *
 * @notice Contract containing logic for settling funding payments between accounts.
 */
contract PPSettlement is
    PPStorage
{
    using BaseMath for uint256;
    using SafeCast for uint256;
    using SafeMath for uint256;
    using PPBalanceMath for PPTypes.Balance;
    using PPIndexMath for PPTypes.Index;
    using SignedMath for SignedMath.Int;

    // ============ Events ============

    event LogIndex(
        bytes32 index
    );

    event LogAccountSettled(
        address indexed account,
        bool isPositive,
        uint256 amount,
        bytes32 balance
    );

    // ============ Functions ============

    /**
     * @dev Calculates the funding change since the last update and stores it in the Global Index.
     *
     * @return Context struct that containing:
     *         - The current oracle price;
     *         - The global index;
     *         - The minimum required collateralization.
     */
    function _loadContext()
        internal
        returns (PPTypes.Context memory)
    {
        // SLOAD old index
        PPTypes.Index memory index = _GLOBAL_INDEX_;

        // get Price (P)
        uint256 price = I_PPOracle(_ORACLE_).getPrice();

        // get Funding (F)
        uint256 timeDelta = block.timestamp.sub(index.timestamp);
        if (timeDelta > 0) {
            // turn the current index into a signed integer
            SignedMath.Int memory signedIndex = SignedMath.Int({
                value: index.value,
                isPositive: index.isPositive
            });

            // Get the funding rate, applied over the time delta.
            (
                bool fundingPositive,
                uint256 fundingValue
            ) = I_PPFunder(_FUNDER_).getFunding(timeDelta);
            fundingValue = fundingValue.baseMul(price);

            // Update the index according to the funding rate, applied over the time delta.
            if (fundingPositive) {
                signedIndex = signedIndex.add(fundingValue);
            } else {
                signedIndex = signedIndex.sub(fundingValue);
            }

            // store new index
            index = PPTypes.Index({
                timestamp: block.timestamp.toUint32(),
                isPositive: signedIndex.isPositive,
                value: signedIndex.value.toUint128()
            });
            _GLOBAL_INDEX_ = index;
        }

        emit LogIndex(index.toBytes32());

        return PPTypes.Context({
            price: price,
            minCollateral: _MIN_COLLATERAL_,
            index: index
        });
    }

    /**
     * @dev Settle the funding payments for a list of accounts and return their resulting balances.
     */
    function _settleAccounts(
        PPTypes.Context memory context,
        address[] memory accounts
    )
        internal
        returns (PPTypes.Balance[] memory)
    {
        uint256 numAccounts = accounts.length;
        PPTypes.Balance[] memory result = new PPTypes.Balance[](numAccounts);

        for (uint256 i = 0; i < numAccounts; i++) {
            result[i] = _settleAccount(context, accounts[i]);
        }

        return result;
    }

    /**
     * @dev Settle the funding payment for a single account and return its resulting balance.
     */
    function _settleAccount(
        PPTypes.Context memory context,
        address account
    )
        internal
        returns (PPTypes.Balance memory)
    {
        PPTypes.Index memory newIndex = context.index;
        PPTypes.Index memory oldIndex = _LOCAL_INDEXES_[account];
        PPTypes.Balance memory balance = _BALANCES_[account];

        // Don't update the index if no time has passed.
        if (oldIndex.timestamp == newIndex.timestamp) {
            return balance;
        }

        // Store a cached copy of the index for this account.
        _LOCAL_INDEXES_[account] = newIndex;

        // No need for settlement if balance is zero.
        if (balance.position == 0) {
            return balance;
        }

        // Get the difference between the newIndex and oldIndex.
        SignedMath.Int memory signedIndexDiff = SignedMath.Int({
            isPositive: newIndex.isPositive,
            value: newIndex.value
        });
        if (oldIndex.isPositive) {
            signedIndexDiff = signedIndexDiff.sub(oldIndex.value);
        } else {
            signedIndexDiff = signedIndexDiff.add(oldIndex.value);
        }

        // By convention, positive funding (index increases) means longs pay shorts
        // and negative funding (index decreases) means shorts pay longs.
        bool settlementIsPositive = signedIndexDiff.isPositive != balance.positionIsPositive;

        // Settle the account balance by applying the index delta as a credit or debit.
        // The interest amount scales with the position size.
        //
        // We round interest debits up and credits down to ensure that the contract won't become
        // insolvent due to rounding errors.
        uint256 settlementAmount;
        if (settlementIsPositive) {
            settlementAmount = signedIndexDiff.value.baseMul(balance.position);
            balance.addToMargin(settlementAmount);
        } else {
            settlementAmount = signedIndexDiff.value.baseMulRoundUp(balance.position);
            balance.subFromMargin(settlementAmount);
        }
        _BALANCES_[account] = balance;

        // Log the change to the account balance, which is the negative of the change in the index.
        emit LogAccountSettled(
            account,
            settlementIsPositive,
            settlementAmount,
            balance.toBytes32()
        );

        return balance;
    }

    /**
     * @dev Returns true if the balance is collateralized according to the price and minimum
     * collateralization passed-in through the context.
     */
    function _isCollateralized(
        PPTypes.Context memory context,
        PPTypes.Balance memory balance
    )
        internal
        pure
        returns (bool)
    {
        (uint256 positive, uint256 negative) = balance.getPositiveAndNegativeValue(context.price);

        // Overflow risk assessment:
        // 2^256 / 10^36 is significantly greater than 2^120 and this calculation is therefore not
        // expected to be a limiting factor on the size of accounts that this contract can handle.
        return positive.mul(BaseMath.base()) >= negative.mul(context.minCollateral);
    }
}
