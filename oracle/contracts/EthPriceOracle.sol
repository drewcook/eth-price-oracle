// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import {CallerContractInterface} from "./CallerContractInterface.sol";

contract EthPriceOracle is Ownable {
    uint private randNonce = 0;
    uint private modulus = 1000;

    mapping(uint256 => bool) pendingRequests;

    event GetLatestEthPrice(address callerAddress, uint id);
    event SetLatestEthPrice(uint256 ethPrice, address callerAddress);

    /// @notice Computes and generates the request id and, for security reasons, this number should be hard to guess. Generating a unique id makes it harder for oracles to collude and manipulate the price for a particular request.
    /// @dev Uses a naive random number generataion algorithm, better to use Chainlink VRF
    /// @return The request ID, a random number between 0 and modulus
    function getLatestEthPrice() public returns (uint256) {
        randNonce++;
        uint id = uint(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, randNonce))
        ) % modulus;
        pendingRequests[id] = true;
        emit GetLatestEthPrice(msg.sender, id);
        return id;
    }

    function setLatestEthPrice(
        uint256 _ethPrice,
        address _callerAddress,
        uint256 _id
    ) public onlyOwner {
        require(
            pendingRequests[_id],
            "This request is not in my pending list."
        );
        delete pendingRequests[_id];
        CallerContractInterface callerContractInstance;
        callerContractInstance = CallerContractInterface(_callerAddress);
        callerContractInstance.callback(_ethPrice, _id);
        emit SetLatestEthPrice(_ethPrice, _callerAddress);
    }
}
