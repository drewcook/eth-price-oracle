// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Roles.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./CallerContractInterface.sol";

contract EthPriceOracle {
    using Roles for Roles.Role;
    using SafeMath for uint256;

    Roles.Role private owners;
    Roles.Role private oracles;
    uint private randNonce = 0;
    uint private modulus = 1000;
    uint private numOracles = 0;
    uint private THRESHOLD = 0;

    mapping(uint256 => bool) pendingRequests;

    struct Response {
        address oracleAddress;
        address callerAddress;
        uint256 ethPrice;
    }

    event GetLatestEthPriceEvent(address callerAddress, uint id);
    event SetLatestEthPriceEvent(uint256 ethPrice, address callerAddress);
    event AddOracleEvent(address oracleAddress);
    event RemoveOracleEvent(address oracleAddress);
    event SetThresholdEvent(uint threshold);

    constructor(address _owner) public {
        owners.add(_owner);
    }

    function addOracle(address _oracle) public {
        require(owners.has(msg.sender), "Not an owner!");
        require(!oracles.has(_oracle), "Already an oracle!");
        oracles.add(_oracle);
        numOracles++;
        emit AddOracleEvent(_oracle);
    }

    function removeOracle(address _oracle) public {
        require(owners.has(msg.sender), "Not an owner!");
        require(oracles.has(_oracle), "Not an oracle!");
        require(numOracles > 1, "Do not remove the last oracle!");
        oracles.remove(_oracle);
        numOracles--;
        emit RemoveOracleEvent(_oracle);
    }

    function setThreshold(uint _threshold) public {
        require(owners.has(msg.sender), "Not an owner!");
        THRESHOLD = _threshold;
        emit SetThresholdEvent(THRESHOLD);
    }

    /// @notice Computes and generates the request id and, for security reasons, this number should be hard to guess. Generating a unique id makes it harder for oracles to collude and manipulate the price for a particular request.
    /// @dev Uses a naive random number generataion algorithm, better to use Chainlink VRF
    /// @return The request ID, a random number between 0 and modulus
    function getLatestEthPrice() public returns (uint256) {
        randNonce++;
        uint id = uint(
            keccak256(abi.encodePacked(now, msg.sender, randNonce))
        ) % modulus;
        pendingRequests[id] = true;
        emit GetLatestEthPriceEvent(msg.sender, id);
        return id;
    }

    function setLatestEthPrice(
        uint256 _ethPrice,
        address _callerAddress,
        uint256 _id
    ) public {
        require(oracles.has(msg.sender), "Not an oracle!");
        require(
            pendingRequests[_id],
            "This request is not in my pending list."
        );
        // Create a response and add it to the request id
        Response memory resp;
        resp = Response(msg.sender, _callerAddress, _ethPrice);
        requestIdToResponse[_id].push(resp);
        uint numResponses = requestIdToResponse[_id].length;
        // If oracle responses reaches threshold, calculate the median ETH price and fulfill the request
        if (numResponses == THRESHOLD) {
            uint computedEthPrice = 0;
            for (uint f = 0; f < requestIdToResponse[_id].length; f++) {
                computedEthPrice = computedEthPrice.add(
                    requestIdToResponse[_id][f].ethPrice
                );
            }
            computedEthPrice = computedEthPrice.div(numResponses);
            delete pendingRequests[_id];
            delete requestIdToResponse[_id];
            CallerContractInterface callerContractInstance;
            callerContractInstance = CallerContractInterface(_callerAddress);
            callerContractInstance.callback(computedEthPrice, _id);
            emit SetLatestEthPriceEvent(computedEthPrice, _callerAddress);
        }
    }
}
