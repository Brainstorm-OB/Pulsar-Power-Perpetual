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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { I_PowerPerpetual } from "../intf/I_PowerPerpetual.sol";


/**
 * @title PPProxy
 * @author Pulsar
 *
 * @notice Base contract for proxy contracts, which can be used to provide additional functionality
 *  or restrictions when making calls to a PowerPerpetual contract on behalf of a user.
 */
contract PPProxy {
    using SafeERC20 for IERC20;

    /**
     * @notice Sets the maximum allowance on the PowerPerpetual contract. Must be called at least once
     *  on a given PowerPerpetual before deposits can be made.
     * @dev Cannot be run in the constructor due to technical restrictions in Solidity.
     */
    function approveMaximumOnPowerPerpetual(
        address perpetual
    )
        external
    {
        IERC20 tokenContract = IERC20(I_PowerPerpetual(perpetual).getTokenContract());

        // safeApprove requires unsetting the allowance first.
        tokenContract.safeApprove(perpetual, 0);

        // Set the allowance to the highest possible value.
        tokenContract.safeApprove(perpetual, uint256(-1));
    }
}
