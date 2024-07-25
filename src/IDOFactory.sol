// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract IDOFactory is Ownable, ReentrancyGuard {
    enum PoolType { LBP, FixedPrice }

    struct Pool {
        address tokenAddress;
        uint256 tokenAmount;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startTime;
        uint256 endTime;
        PoolType poolType;
        bool isActive;
    }

    mapping(uint256 => Pool) public pools;
    uint256 public poolCount;

    event PoolCreated(uint256 indexed poolId, address indexed tokenAddress, PoolType poolType);
    event TokensPurchased(uint256 indexed poolId, address indexed buyer, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner){}

    function createLBPool(
        address _tokenAddress,
        uint256 _tokenAmount,
        uint256 _startPrice,
        uint256 _endPrice,
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_startPrice > _endPrice, "Start price must be greater than end price");
        require(_startTime < _endTime, "Start time must be before end time");
        require(_startTime > block.timestamp, "Start time must be in the future");

        uint256 poolId = poolCount++;
        pools[poolId] = Pool({
            tokenAddress: _tokenAddress,
            tokenAmount: _tokenAmount,
            startPrice: _startPrice,
            endPrice: _endPrice,
            startTime: _startTime,
            endTime: _endTime,
            poolType: PoolType.LBP,
            isActive: true
        });

        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _tokenAmount);

        emit PoolCreated(poolId, _tokenAddress, PoolType.LBP);
    }

    function createFixedPricePool(
        address _tokenAddress,
        uint256 _tokenAmount,
        uint256 _price,
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");
        require(_startTime < _endTime, "Start time must be before end time");
        require(_startTime > block.timestamp, "Start time must be in the future");

        uint256 poolId = poolCount++;
        pools[poolId] = Pool({
            tokenAddress: _tokenAddress,
            tokenAmount: _tokenAmount,
            startPrice: _price,
            endPrice: _price,
            startTime: _startTime,
            endTime: _endTime,
            poolType: PoolType.FixedPrice,
            isActive: true
        });

        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _tokenAmount);

        emit PoolCreated(poolId, _tokenAddress, PoolType.FixedPrice);
    }

    function buyTokens(uint256 _poolId) external payable nonReentrant {
        Pool storage pool = pools[_poolId];
        require(pool.isActive, "Pool is not active");
        require(block.timestamp >= pool.startTime && block.timestamp <= pool.endTime, "Pool is not open");

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
        require(tokensToBuy <= pool.tokenAmount, "Not enough tokens in the pool");

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

        return pool.startPrice - (priceDiff * timeElapsed / totalTime);
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