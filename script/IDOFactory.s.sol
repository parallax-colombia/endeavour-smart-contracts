// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IDOFactory} from "../src/IDOFactory.sol";

contract IDOFactoryScript is Script {
    IDOFactory public idoFactory;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.envAddress("INITIAL_OWNER");

        vm.startBroadcast(deployerPrivateKey);

        idoFactory = new IDOFactory(initialOwner);

        vm.stopBroadcast();
    }
}
