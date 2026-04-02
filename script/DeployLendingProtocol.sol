// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {LendingProtocol} from "src/LendingProtocol.sol";

contract DeployLendingProtocol is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        new LendingProtocol();
        vm.stopBroadcast();
    }
}