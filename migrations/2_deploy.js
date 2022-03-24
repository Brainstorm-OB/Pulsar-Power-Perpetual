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

const {
  getChainId,
  isDevNetwork,
  getChainlinkPriceOracleAddress,
  getMakerPriceOracleAddress,
  getDeployerAddress,
  getOracleAdjustment,
  getChainlinkOracleAdjustmentExponent,
  getInverseOracleAdjustmentExponent,
  getTokenAddress,
  getWethAddress,
  getMinCollateralization,
  getInsuranceFundAddress,
  getInsuranceFee,
  getDeleveragingOperatorAddress,
  getFundingRateProviderAddress,
  getSoloAddress,
} = require('./helpers');

// ============ Constants ============

const SOLO_USDC_MARKET = 2;

// ============ Contracts ============

// Base Protocol
const PowerPerpetualProxy = artifacts.require('PowerPerpetualProxy');
const PowerPerpetual = artifacts.require('PowerPerpetual');

// Funding Oracles
const PPFundingOracle = artifacts.require('PPFundingOracle');
const PPInverseFundingOracle = artifacts.require('PPInverseFundingOracle');

// Traders
const PPOrders = artifacts.require('PPOrders');
const PPInverseOrders = artifacts.require('PPInverseOrders');
const PPDeleveraging = artifacts.require('PPDeleveraging');
const PPLiquidation = artifacts.require('PPLiquidation');

// Price Oracles
const PPChainlinkOracle = artifacts.require('PPChainlinkOracle');
const PPMakerOracle = artifacts.require('PPMakerOracle');
const PPPOracleInverter = artifacts.require('PPPOracleInverter');
const PPPMirrorOracleETHUSD = artifacts.require('PPPMirrorOracleETHUSD');

// Proxies
const PPCurrencyConverterProxy = artifacts.require('PPCurrencyConverterProxy');
const PPLiquidatorProxy = artifacts.require('PPLiquidatorProxy');
const PPSoloBridgeProxy = artifacts.require('PPSoloBridgeProxy');
const PPWethProxy = artifacts.require('PPWethProxy');

// Test Contracts
const TestExchangeWrapper = artifacts.require('Test_ExchangeWrapper');
const TestLib = artifacts.require('Test_Lib');
const TestPPFunder = artifacts.require('Test_PPFunder');
const TestPPMonolith = artifacts.require('Test_PPMonolith');
const TestPPOracle = artifacts.require('Test_PPOracle');
const TestPPTrader = artifacts.require('Test_PPTrader');
const TestSolo = artifacts.require('Test_Solo');
const TestToken = artifacts.require('Test_Token');
const TestToken2 = artifacts.require('Test_Token2');
const TestMakerOracle = artifacts.require('Test_MakerOracle');
const TestChainlinkAggregator = artifacts.require('Test_ChainlinkAggregator');
const WETH9 = artifacts.require('WETH9');

// ============ Main Migration ============

const migration = async (deployer, network, accounts) => {
  await deployTestContracts(deployer, network);
  await deployProtocol(deployer, network, accounts);
  await deployOracles(deployer, network);
  await initializePowerPerpetual(deployer, network);
  await deployTraders(deployer, network);
};

module.exports = migration;

// ============ Deploy Functions ============

async function deployTestContracts(deployer, network) {
  if (isDevNetwork(network)) {
    await Promise.all([
      deployer.deploy(TestExchangeWrapper),
      deployer.deploy(TestLib),
      deployer.deploy(TestPPFunder),
      deployer.deploy(TestPPMonolith),
      deployer.deploy(TestPPOracle),
      deployer.deploy(TestPPTrader),
      deployer.deploy(TestSolo),
      deployer.deploy(TestToken),
      deployer.deploy(TestToken2),
      deployer.deploy(TestMakerOracle),
      deployer.deploy(TestChainlinkAggregator),
      deployer.deploy(WETH9),
    ]);
  }
}

async function deployProtocol(deployer, network, accounts) {
  await deployer.deploy(PowerPerpetual);
  await deployer.deploy(
    PowerPerpetualProxy,
    PowerPerpetual.address, // logic
    getDeployerAddress(network, accounts), // admin
    '0x', // data
  );
}

async function deployOracles(deployer, network) {
  // Get external oracle addresses.
  const chainlinkOracle = getChainlinkPriceOracleAddress(network, TestChainlinkAggregator);
  const makerOracle = getMakerPriceOracleAddress(network, TestMakerOracle);

  // Deploy funding oracles, Maker oracle wrapper, and Chainlink oracle wrapper.
  await Promise.all([
    deployer.deploy(
      PPFundingOracle,
      getFundingRateProviderAddress(network),
    ),
    deployer.deploy(
      PPInverseFundingOracle,
      getFundingRateProviderAddress(network),
    ),
    deployer.deploy(
      PPChainlinkOracle,
      chainlinkOracle,
      PowerPerpetualProxy.address,
      getChainlinkOracleAdjustmentExponent(network),
    ),
    deployer.deploy(PPMakerOracle),
  ]);

  // Deploy oracle inverter.
  await deployer.deploy(
    PPPOracleInverter,
    PPMakerOracle.address,
    PowerPerpetualProxy.address,
    getInverseOracleAdjustmentExponent(network),
  );

  // Deploy mirror oracle.
  await deployer.deploy(
    PPPMirrorOracleETHUSD,
    makerOracle,
  );

  // Configure routing and permissions.
  const [oracle, mirror] = await Promise.all([
    PPMakerOracle.deployed(),
    PPPMirrorOracleETHUSD.deployed(),
  ]);
  await Promise.all([
    oracle.setRoute(
      PowerPerpetualProxy.address,
      makerOracle,
    ),
    oracle.setRoute(
      PPPOracleInverter.address,
      makerOracle,
    ),
    oracle.setAdjustment(
      makerOracle,
      getOracleAdjustment(network),
    ),
    mirror.kiss(
      PPMakerOracle.address,
    ),
  ]);
}

async function deployTraders(deployer, network) {
  // deploy traders
  await Promise.all([
    deployer.deploy(
      PPOrders,
      PowerPerpetualProxy.address,
      getChainId(network),
    ),
    deployer.deploy(
      PPInverseOrders,
      PowerPerpetualProxy.address,
      getChainId(network),
    ),
    deployer.deploy(
      PPDeleveraging,
      PowerPerpetualProxy.address,
      getDeleveragingOperatorAddress(network),
    ),
    deployer.deploy(
      PPLiquidation,
      PowerPerpetualProxy.address,
    ),
  ]);

  // deploy proxies
  await Promise.all([
    deployer.deploy(
      PPCurrencyConverterProxy,
    ),
    deployer.deploy(
      PPLiquidatorProxy,
      PowerPerpetualProxy.address,
      PPLiquidation.address,
      getInsuranceFundAddress(network),
      getInsuranceFee(network),
    ),
    deployer.deploy(
      PPSoloBridgeProxy,
      getSoloAddress(network, TestSolo),
      getChainId(network),
    ),
    deployer.deploy(
      PPWethProxy,
      getWethAddress(network, WETH9),
    ),
  ]);

  // initialize proxies on non-testnet
  if (!isDevNetwork(network)) {
    const currencyConverterProxy = await PPCurrencyConverterProxy.deployed();
    await currencyConverterProxy.approveMaximumOnPowerPerpetual(PowerPerpetualProxy.address);

    const liquidatorProxy = await PPLiquidatorProxy.deployed();
    await liquidatorProxy.approveMaximumOnPowerPerpetual();

    const soloBridgeProxy = await PPSoloBridgeProxy.deployed();
    await soloBridgeProxy.approveMaximumOnPowerPerpetual(PowerPerpetualProxy.address);
    await soloBridgeProxy.approveMaximumOnSolo(SOLO_USDC_MARKET);

    const wethProxy = await PPWethProxy.deployed();
    await wethProxy.approveMaximumOnPowerPerpetual(PowerPerpetualProxy.address);
  }

  // set global operators
  const perpetual = await PowerPerpetual.at(PowerPerpetualProxy.address);
  await Promise.all([
    // TODO: Approve either PPOrders or PPInverseOrders depending on the power perpetual market.
    perpetual.setGlobalOperator(PPOrders.address, true),
    perpetual.setGlobalOperator(PPDeleveraging.address, true),
    perpetual.setGlobalOperator(PPLiquidation.address, true),
    perpetual.setGlobalOperator(PPCurrencyConverterProxy.address, true),
    perpetual.setGlobalOperator(PPLiquidatorProxy.address, true),
    perpetual.setGlobalOperator(PPSoloBridgeProxy.address, true),
    perpetual.setGlobalOperator(PPWethProxy.address, true),
  ]);
  if (isDevNetwork(network)) {
    await perpetual.setGlobalOperator(TestPPTrader.address, true);
  }
}

async function initializePowerPerpetual(deployer, network) {
  const perpetual = await PowerPerpetual.at(PowerPerpetualProxy.address);
  if (!isDevNetwork(network)) {
    await perpetual.initialize(
      getTokenAddress(network),
      PPMakerOracle.address,
      PPFundingOracle.address,
      getMinCollateralization(network),
    );
  }
}
