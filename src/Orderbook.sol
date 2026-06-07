// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOrderbook} from "./IOrderbook.sol";

/// @dev Minimal ERC20 surface the orderbook needs. The provided `MockERC20`
///      implements all of these methods (plus `mint`).
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @title Orderbook (template)
/// @notice Skeleton to complete. The constructor, immutable
///         token wiring, and the two trivial getters are already done —
///         everything else reverts with `"NotImplemented"`.
///
///         You are free to add additional state, structs, errors, and
///         helper functions. The only hard constraints are:
///         (1) keep the `IOrderbook` ABI exactly as declared in the
///             interface (the grading harness depends on it), and
///         (2) keep `baseToken`/`quoteToken` as immutables set in the
///             constructor.
contract Orderbook is IOrderbook {
    IERC20 public immutable baseToken;
    IERC20 public immutable quoteToken;

    struct Order {
        uint256 id;
        address maker;
        uint256 price;
        uint256 amount;
        uint256 remaining;
    }

    Order[] private bids;
    Order[] private asks;

    uint256 private nextOrderId = 1;

    /// @dev Suggested events. These are a starting point — your
    ///      implementation may emit a different set, rename them, or omit
    ///      events entirely. Nothing in the grading harness depends on
    ///      these signatures.
    event OrderPlaced(
        uint256 indexed orderId,
        address indexed maker,
        Side side,
        uint256 price,
        uint256 amount
    );
    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 fillAmount,
        uint256 fillPrice
    );
    event OrderCleared();

    constructor(address _baseToken, address _quoteToken) {
        require(_baseToken != address(0), "baseToken=0");
        require(_quoteToken != address(0), "quoteToken=0");
        require(_baseToken != _quoteToken, "base==quote");
        baseToken = IERC20(_baseToken);
        quoteToken = IERC20(_quoteToken);
    }

    function getBaseToken() external view returns (address) {
        return address(baseToken);
    }

    function getQuoteToken() external view returns (address) {
        return address(quoteToken);
    }

    function placeLimitOrder(Side side, uint256 price, uint256 amount) external returns (uint256) {
        if (price == 0) {
            revert("price = 0");
        }

        if (amount == 0) {
            revert("amount = 0");
        }

        uint256 orderId = nextOrderId;
        nextOrderId = orderId + 1;

        Order memory order;
        order.id = orderId;
        order.maker = msg.sender;
        order.price = price;
        order.amount = amount;
        order.remaining = amount;

        if (side == Side.BUY) {
            uint256 quoteAmount = amount * price;
            quoteAmount = quoteAmount / 1e18;

            if (!quoteToken.transferFrom(msg.sender, address(this), quoteAmount)) {
                revert("quote");
            }

            bids.push(order);
        } else {
            if (!baseToken.transferFrom(msg.sender, address(this), amount)) {
                revert("base");
            }
            asks.push(order);
        }

        emit OrderPlaced(orderId, msg.sender, side, price, amount);
        return orderId;
    }

    function placeMarketOrder(Side side, uint256 amount) external {
        if (amount == 0) {
            revert("amount = 0");
        }

        uint256 remaining = amount;

        if (side == Side.BUY) {
            while (remaining > 0) {
                int256 bestIndex = bestAskIndex();

                if (bestIndex < 0) {
                    break;
                }

                uint256 index = uint256(bestIndex);
                Order storage order = asks[index];

                uint256 fillAmount = order.remaining;
                if (fillAmount > remaining) {
                    fillAmount = remaining;
                }

                uint256 quoteAmount = fillAmount * order.price;
                quoteAmount = quoteAmount / 1e18;

                if (!quoteToken.transferFrom(msg.sender, order.maker, quoteAmount)) {
                    revert("quote");
                }

                if (!baseToken.transfer(msg.sender, fillAmount)) {
                    revert("base");
                }

                order.remaining = order.remaining - fillAmount;
                remaining = remaining - fillAmount;

                emit OrderFilled(order.id, msg.sender, fillAmount, order.price);
            }
        } else {
            while (remaining > 0) {
                int256 bestIndex = bestBidIndex();

                if (bestIndex < 0) {
                    break;
                }

                uint256 index = uint256(bestIndex);
                Order storage order = bids[index];

                uint256 fillAmount = order.remaining;
                if (fillAmount > remaining) {
                    fillAmount = remaining;
                }

                if (!baseToken.transferFrom(msg.sender, order.maker, fillAmount)) {
                    revert("base");
                }

                uint256 quoteAmount = fillAmount * order.price;
                quoteAmount = quoteAmount / 1e18;

                if (!quoteToken.transfer(msg.sender, quoteAmount)) {
                    revert("quote");
                }

                order.remaining = order.remaining - fillAmount;
                remaining = remaining - fillAmount;

                emit OrderFilled(order.id, msg.sender, fillAmount, order.price);
            }
        }
    }

    function clear() external {
        uint256 i = 0;
        while (i < asks.length) {
            Order storage order = asks[i];

            if (order.remaining > 0) {
                if (!baseToken.transfer(order.maker, order.remaining)) {
                    revert("base");
                }

                order.remaining = 0;
            }

            i = i + 1;
        }

        i = 0;
        while (i < bids.length) {
            Order storage order = bids[i];

            if (order.remaining > 0) {
                uint256 quoteAmount = order.remaining * order.price;
                quoteAmount = quoteAmount / 1e18;

                if (!quoteToken.transfer(order.maker, quoteAmount)) {
                    revert("quote");
                }

                order.remaining = 0;
            }

            i = i + 1;
        }

        delete asks;
        delete bids;

        emit OrderCleared();
    }

    function getBidsCount() external view returns (uint256) {
        uint256 count = 0;

        uint256 i = 0;
        while (i < bids.length) {
            if (bids[i].remaining > 0) {
                count = count + 1;
            }

            i = i + 1;
        }

        return count;
    }

    function getAsksCount() external view returns (uint256) {
        uint256 count = 0;

        uint256 i = 0;
        while (i < asks.length) {
            if (asks[i].remaining > 0) {
                count = count + 1;
            }

            i = i + 1;
        }

        return count;
    }

    function getMidPrice() external view returns (uint256) {
        uint256 bestBid = bestBidPrice();
        uint256 bestAsk = bestAskPrice();

        if (bestBid == 0) {
            revert("mid");
        }

        if (bestAsk == 0) {
            revert("mid");
        }

        return (bestBid + bestAsk) / 2;
    }

    function bestAskIndex() internal view returns (int256) {
        uint256 bestPrice = type(uint256).max;
        int256 bestIndex = -1;

        uint256 i = 0;
        while (i < asks.length) {
            if (asks[i].remaining > 0) {
                if (asks[i].price < bestPrice) {
                    bestPrice = asks[i].price;
                    bestIndex = int256(i);
                }
            }

            i = i + 1;
        }

        return bestIndex;
    }

    function bestBidIndex() internal view returns (int256) {
        uint256 bestPrice = 0;
        int256 bestIndex = -1;

        uint256 i = 0;
        while (i < bids.length) {
            if (bids[i].remaining > 0) {
                if (bids[i].price > bestPrice) {
                    bestPrice = bids[i].price;
                    bestIndex = int256(i);
                }
            }

            i = i + 1;
        }

        return bestIndex;
    }

    function bestAskPrice() internal view returns (uint256) {
        int256 bestIndex = bestAskIndex();

        if (bestIndex < 0) {
            return 0;
        }

        return asks[uint256(bestIndex)].price;
    }

    function bestBidPrice() internal view returns (uint256) {
        int256 bestIndex = bestBidIndex();

        if (bestIndex < 0) {
            return 0;
        }

        return bids[uint256(bestIndex)].price;
    }
}
