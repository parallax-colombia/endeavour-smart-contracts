// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IDOFactory} from "../src/IDOFactory.sol";

contract IDOFactoryTest is Test {
    IDOFactory public idoFactory;

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        
        idoFactory = new IDOFactory(initialOwner);
  
    }

}
