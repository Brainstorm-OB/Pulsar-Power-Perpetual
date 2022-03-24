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

import { I_PPFunder } from "../../protocol/core/intf/I_PPFunder.sol";


/**
 * @title Test_PPFunder
 * @author Pulsar
 *
 * @notice I_PPFunder implementation for testing.
 */
/* solium-disable-next-line camelcase */
contract Test_PPFunder is
    I_PPFunder
{
    bool public _FUNDING_IS_POSITIVE_ = true;
    uint256 public _FUNDING_ = 0;

    function getFunding(
        uint256 // timeDelta
    )
        external
        view
        returns (bool, uint256)
    {
        return (_FUNDING_IS_POSITIVE_, _FUNDING_);
    }

    function setFunding(
        bool isPositive,
        uint256 newFunding
    )
        external
    {
        _FUNDING_IS_POSITIVE_ = isPositive;
        _FUNDING_ = newFunding;
    }
}
