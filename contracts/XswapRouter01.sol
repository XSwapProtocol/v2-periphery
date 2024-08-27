pragma solidity =0.6.6;

import '../Swap/interfaces/IXswapFactory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './libraries/XswapLibrary.sol';
import './interfaces/IXswapRouter01.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWXDC.sol';

contract XswapRouter01 is IXswapRouter01 {
    address public immutable override factory;
    address public immutable override WXDC;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'XswapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WXDC) public {
        factory = _factory;
        WXDC = _WXDC;
    }

    receive() external payable {
        assert(msg.sender == WXDC); // only accept ETH via fallback from the WXDC contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IXswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IXswapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = XswapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = XswapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'XswapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = XswapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'XswapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = XswapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IXswapPair(pair).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WXDC,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = XswapLibrary.pairFor(factory, token, WXDC);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWXDC(WXDC).deposit{value: amountETH}();
        assert(IWXDC(WXDC).transfer(pair, amountETH));
        liquidity = IXswapPair(pair).mint(to);
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH); // refund dust eth, if any
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = XswapLibrary.pairFor(factory, tokenA, tokenB);
        IXswapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IXswapPair(pair).burn(to);
        (address token0,) = XswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'XswapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'XswapRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WXDC,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWXDC(WXDC).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountA, uint amountB) {
        address pair = XswapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IXswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountToken, uint amountETH) {
        address pair = XswapLibrary.pairFor(factory, token, WXDC);
        uint value = approveMax ? uint(-1) : liquidity;
        IXswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) private {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = XswapLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? XswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IXswapPair(XswapLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = XswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'XswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, XswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = XswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'XswapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, XswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    override
    payable
    ensure(deadline)
    returns (uint[] memory amounts)
    {
        require(path[0] == WXDC, 'XswapRouter: INVALID_PATH');
        amounts = XswapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'XswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWXDC(WXDC).deposit{value: amounts[0]}();
        assert(IWXDC(WXDC).transfer(XswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
    external
    override
    ensure(deadline)
    returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WXDC, 'XswapRouter: INVALID_PATH');
        amounts = XswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'XswapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, XswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWXDC(WXDC).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    override
    ensure(deadline)
    returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WXDC, 'XswapRouter: INVALID_PATH');
        amounts = XswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'XswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, XswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWXDC(WXDC).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
    external
    override
    payable
    ensure(deadline)
    returns (uint[] memory amounts)
    {
        require(path[0] == WXDC, 'XswapRouter: INVALID_PATH');
        amounts = XswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'XswapRouter: EXCESSIVE_INPUT_AMOUNT');
        IWXDC(WXDC).deposit{value: amounts[0]}();
        assert(IWXDC(WXDC).transfer(XswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust eth, if any
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public pure override returns (uint amountB) {
        return XswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure override returns (uint amountOut) {
        return XswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure override returns (uint amountIn) {
        return XswapLibrary.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view override returns (uint[] memory amounts) {
        return XswapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view override returns (uint[] memory amounts) {
        return XswapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
