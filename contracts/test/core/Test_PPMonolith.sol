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

import { Test_PPFunder } from "./Test_PPFunder.sol";
import { Test_PPOracle } from "./Test_PPOracle.sol";
import { Test_PPTrader } from "./Test_PPTrader.sol";


/**
 * @title Test_PPMonolith
 * @author Pulsar
 *
 * @notice A second contract for testing the funder, oracle, and trader.
 */
/* solium-disable-next-line camelcase, no-empty-blocks */
contract Test_PPMonolith is
    Test_PPFunder,
    Test_PPOracle,
    Test_PPTrader
{}
