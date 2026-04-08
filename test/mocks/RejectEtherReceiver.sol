// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract RejectEtherReceiver {
    receive() external payable {
        revert("RejectEtherReceiver: cannot receive ETH");
    }
}