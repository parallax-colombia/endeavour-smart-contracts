// SPDX-License-Identifier: MIT

// The MIT License (MIT)

// Copyright (c) [2024] [Parallax labs]
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract IDOFactory is 
Ownable,
Pausable,
ReentrancyGuard 
{
    enum PoolType {
        LBP,
        FixedPrice
    }

    struct Pool {
        address tokenAddress;
        uint256 tokenAmount;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startTime;
        uint256 endTime;
        PoolType poolType;
        bool isActive;
        bool whitelistEnabled;
    }

    mapping(uint256 => Pool) public pools;

    uint256 public poolCount;
    bytes32 public merkleRoot;
    bool public globalWhitelistEnabled;

    event PoolCreated(
        uint256 indexed poolId,
        address indexed tokenAddress,
        PoolType poolType,
        bool whitelistEnabled
    );
    event TokensPurchased(
        uint256 indexed poolId,
        address indexed buyer,
        uint256 amount
    );
    event WhitelistUpdated (bytes32 newMerkleRoot);
    event GlobalWhitelistToggled(bool isEnabled);
    event PoolWhitelistToggled(uint256 indexed poolId, bool isEnabled);

    constructor(address initialOwner) Ownable(initialOwner) {}
        function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit WhitelistUpdated(_merkleRoot);
    }

    function toggleGlobalWhitelist(bool _enabled) external onlyOwner {
        globalWhitelistEnabled = _enabled;
        emit GlobalWhitelistToggled(_enabled);
    }

    function togglePoolWhitelist(uint256 _poolId, bool _enabled) external onlyOwner {
        require(_poolId < poolCount, "Pool does not exist");
        pools[_poolId].whitelistEnabled = _enabled;
        emit PoolWhitelistToggled(_poolId, _enabled);
    }

    function isWhitelisted(address _user, bytes32[] calldata _merkleProof) public view returns (bool) {
        if (!globalWhitelistEnabled) return true;
        bytes32 leaf = keccak256(abi.encodePacked(_user));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }

    function createLBPool(
        address _tokenAddress,
        uint256 _tokenAmount,
        uint256 _startPrice,
        uint256 _endPrice,
        uint256 _startTime,
        uint256 _endTime,
        bool _whitelistEnabled
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(
            _startPrice > _endPrice,
            "Start price must be greater than end price"
        );
        require(_startTime < _endTime, "Start time must be before end time");
        require(
            _startTime > block.timestamp,
            "Start time must be in the future"
        );

        uint256 poolId = poolCount++;
        pools[poolId] = Pool({
            tokenAddress: _tokenAddress,
            tokenAmount: _tokenAmount,
            startPrice: _startPrice,
            endPrice: _endPrice,
            startTime: _startTime,
            endTime: _endTime,
            poolType: PoolType.LBP,
            isActive: true,
            whitelistEnabled: _whitelistEnabled
        });

        IERC20(_tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );

        emit PoolCreated(poolId, _tokenAddress, PoolType.LBP, _whitelistEnabled);
    }

    function createFixedPricePool(
        address _tokenAddress,
        uint256 _tokenAmount,
        uint256 _price,
        uint256 _startTime,
        uint256 _endTime,
        bool _whitelistEnabled
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");
        require(_startTime < _endTime, "Start time must be before end time");
        require(
            _startTime > block.timestamp,
            "Start time must be in the future"
        );

        uint256 poolId = poolCount++;
        pools[poolId] = Pool({
            tokenAddress: _tokenAddress,
            tokenAmount: _tokenAmount,
            startPrice: _price,
            endPrice: _price,
            startTime: _startTime,
            endTime: _endTime,
            poolType: PoolType.FixedPrice,
            isActive: true,
            whitelistEnabled: _whitelistEnabled
        });

        IERC20(_tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );

        emit PoolCreated(poolId, _tokenAddress, PoolType.FixedPrice, _whitelistEnabled);
    }

    function buyTokens(uint256 _poolId,  bytes32[] calldata _merkleProof) external payable nonReentrant {
        require(_poolId < poolCount, "Pool does not exist");
        Pool storage pool = pools[_poolId];
        require(pool.isActive, "Pool is not active");
        require(
            block.timestamp >= pool.startTime &&
                block.timestamp <= pool.endTime,
            "Pool is not open"
        );
        if (globalWhitelistEnabled && pool.whitelistEnabled) {
            require(isWhitelisted(msg.sender, _merkleProof), "Not whitelisted");
        }

        uint256 tokensToBuy;
        uint256 refund;

        if (pool.poolType == PoolType.LBP) {
            uint256 currentPrice = getCurrentPrice(_poolId);
            tokensToBuy = msg.value / currentPrice;
            refund = msg.value % currentPrice;
        } else {
            tokensToBuy = msg.value / pool.startPrice;
            refund = msg.value % pool.startPrice;
        }

        require(tokensToBuy > 0, "Not enough ETH sent");
        require(
            tokensToBuy <= pool.tokenAmount,
            "Not enough tokens in the pool"
        );

        pool.tokenAmount -= tokensToBuy;
        IERC20(pool.tokenAddress).transfer(msg.sender, tokensToBuy);

        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }

        emit TokensPurchased(_poolId, msg.sender, tokensToBuy);
    }

    function getCurrentPrice(uint256 _poolId) public view returns (uint256) {
        Pool storage pool = pools[_poolId];
        require(pool.poolType == PoolType.LBP, "Not an LBP pool");

        if (block.timestamp <= pool.startTime) return pool.startPrice;
        if (block.timestamp >= pool.endTime) return pool.endPrice;

        uint256 timeElapsed = block.timestamp - pool.startTime;
        uint256 totalTime = pool.endTime - pool.startTime;
        uint256 priceDiff = pool.startPrice - pool.endPrice;

        return pool.startPrice - ((priceDiff * timeElapsed) / totalTime);
    }

    function closePool(uint256 _poolId) external onlyOwner {
        Pool storage pool = pools[_poolId];
        require(pool.isActive, "Pool is already closed");

        pool.isActive = false;

        if (pool.tokenAmount > 0) {
            IERC20(pool.tokenAddress).transfer(owner(), pool.tokenAmount);
        }
    }
}
