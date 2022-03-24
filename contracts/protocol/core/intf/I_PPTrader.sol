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

import { PPTypes } from "../lib/PPTypes.sol";


/**
 * @title I_PPTrader
 * @author Pulsar
 *
 * @notice Interface that PowerPerpetual Traders must implement.
 */
interface I_PPTrader {

    /**
     * @notice Returns the result of the trade between the maker and the taker. Expected to be
     *  called by PowerPerpetual. Reverts if the trade is disallowed.
     *
     * @param  sender       The address that called the `trade()` function of PowerPerpetual.
     * @param  maker        The address of the passive maker account.
     * @param  taker        The address of the active taker account.
     * @param  price        The current oracle price of the underlying asset.
     * @param  data         Arbitrary data passed in to the `trade()` function of PowerPerpetual.
     * @param  traderFlags  Any flags that have been set by other I_PPTrader contracts during the
     *                      same call to the `trade()` function of PowerPerpetual.
     * @return              The result of the trade from the perspective of the taker.
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
        returns (PPTypes.TradeResult memory);
}
