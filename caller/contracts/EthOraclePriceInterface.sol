// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface EthOraclePriceInterface {
    function getLatestEthPrice() external returns (uint256);
}
