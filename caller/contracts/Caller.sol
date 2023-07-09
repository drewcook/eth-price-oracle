// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EthOraclePriceInterface} from "./EthOraclePriceInterface.sol";

contract Caller {
    uint256 private ethPrice;

    EthOraclePriceInterface private oracleInstance;
    address private oracleAddress;

    mapping(uint256 => bool) myRequests;

    event NewOracleAddress(address oracleAddress);
    event ReceivedNewRequestId(uint256 id);
    event EthPriceUpdated(uint256 ethPrice, uint256 id);

    modifier onlyOracle() {
        require(
            msg.sender == oracleAddress,
            "You are not authorized to call this function."
        );
        _;
    }

    function setOracleInstanceAddress(address _oracleInstanceAddress) public {
        oracleAddress = _oracleInstanceAddress;
        oracleInstance = EthOraclePriceInterface(oracleAddress);
        emit NewOracleAddress(oracleAddress);
    }

    function updateEthPrice() public {
        uint256 id = oracleInstance.getLatestEthPrice();
        myRequests[id] = true;
        emit ReceivedNewRequestId(id);
    }

    function callback(uint256 _ethPrice, uint256 _id) public onlyOracle {
        require(myRequests[_id], "This request is not in my pending list.");
        ethPrice = _ethPrice;
        delete myRequests[_id];
        emit EthPriceUpdated(_ethPrice, _id);
    }
}
