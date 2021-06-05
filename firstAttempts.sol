// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "fungible_CDPToken.sol";
import "inheritingForTestPurpose.sol";



// Uniswap Pair Interface
interface UniswapV2PairLike {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

// Uniswap Factory Interface
interface UniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

// Vat Interface
contract VatLike {
    struct Ilk {
        uint256 Art; // Total Normalised Debt     [wad]
        uint256 rate; // Accumulated Rates         [ray]
        uint256 spot; // Price with Safety Margin  [ray]
        uint256 line; // Debt Ceiling              [rad]
        uint256 dust; // Urn Debt Floor            [rad]
    }
    struct Urn {
        uint256 ink; // Locked Collateral  [wad]
        uint256 art; // Normalised Debt    [wad]
    }
    mapping(bytes32 => Ilk) public ilks;
    mapping(bytes32 => mapping(address => Urn)) public urns;
}


contract CDPWrapper is inheritingForTestPurpose{
     
    address private owner;
    mapping(address => uint256) tokenizedCDPs;  // Keep track of senders` CDP IDs
    mapping(uint256 => uint256) tokenization;   // Keep track of swap ratios
    
    mapping(uint256 => uint256) depts;
    
    uint256[] private wrappedCDPs;
    
    CDPToken cdp_token;                         // Token Contract
    
    // Maker Dao 
    DssCdpManagerLike private mk_cdpman  = DssCdpManagerLike(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    ProxyRegistryLike private mk_proxy   = ProxyRegistryLike(0x4678f0a6958e4D2Bc4F1BAF7Bc52E8F3564f3fE4);
    UniswapV2FactoryLike private us_fac  = UniswapV2FactoryLike(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    VatLike private vat                  = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    
    address private DAI_TOKEN = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private Wrapped_ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Only Owner
    modifier onlyOwner {
        require(msg.sender==owner, "Not the owner");
        _;
    }
    
    constructor() {
         owner = msg.sender;
     }
     
    /**
     * @dev Create CDPToken Contract
     * 
     * The contract required a `CdpTokenizer` to be defined
     * The `CdpTokenizer` is set to the address of this contract to
     * permit others minting and burning tokens
     */
    function createTokenContract() public onlyOwner returns(address) {
         cdp_token = new CDPToken(address(this));
         return address(cdp_token);
    }
    
    /**
     * @dev Update Tokenizer within the Token Contract
     * 
     * This function allows to flexibly upgrade this Contract
     * Execute this function after deploying the upgraded contract
     */
    function updateCDPTokenizer(address newtokenizer) public onlyOwner {
         require(cdp_token.setTokenizer(newtokenizer), "Switch failed");
    }
    
    /**
     * @dev Tokenize CDP by transfering ownership and reciving tokens.
     * 
     * Automatically takes the `sender` first CDP 
     */
    function tokenizeCDP() public {
        // Get CDP ID of first Vault
        uint CDPID = mk_cdpman.getFirstCDP(mk_proxy.proxies(msg.sender));
        
        address urn = mk_cdpman.getURNHandler(CDPID);
         
         (, uint256 rate,,,) = vat.ilks(ilk);
         (uint256 collateral, uint256 dept) = vat.urns(ilk, urn);
         
         
         uint256 dai_eth = getExchangeRate();
         
         uint256 amoutToMint = collateral - (dept*rate/10**27/dai_eth); // Differance between collateral in ETH and stablecoin dept in ETH
         
         mk_cdpman.give(CDPID, address(this));
         cdp_token.mint(msg.sender, amoutToMint);
         
         depts[CDPID] = amoutToMint;
         wrappedCDPs.push(CDPID);
    }
    
    /**
     * @dev Overloaded function, see above.
     * 
     * Allows to specify a specific CDP by ID
     */
    function tokenizeCDP(uint256 CDPID) public {
         
         
         address urn = mk_cdpman.getURNHandler(CDPID);
         
         (, uint256 rate,,,) = vat.ilks(ilk);
         (uint256 collateral, uint256 dept) = vat.urns(ilk, urn);
         
         
         uint256 dai_eth = getExchangeRate();
         
         uint256 amoutToMint = collateral - (dept*rate/10**27/dai_eth); // Differance between collateral in ETH and stablecoin dept in ETH
         
         mk_cdpman.give(CDPID, address(this));
         cdp_token.mint(msg.sender, amoutToMint);
         
         depts[CDPID] = amoutToMint;
         wrappedCDPs.push(CDPID);
    }

    
    /**
     * @dev Unlock any CDP without any arguments 
     */
    function unlockAnyCDP() public returns(uint256 cdpid){
        // Get Token balance of sender
        uint256 balance = cdp_token.balanceOf(msg.sender);
        
        for (uint256 i=0; i<wrappedCDPs.length-1; i++) {
            if(depts[wrappedCDPs[i]] <= balance) {
                cdp_token.burn(msg.sender, depts[wrappedCDPs[i]]);
                // Grant access right of CDP to sender
                mk_cdpman.give(wrappedCDPs[i], msg.sender);
                 
                wrappedCDPs[i] = wrappedCDPs[wrappedCDPs.length - 1];
                delete wrappedCDPs[wrappedCDPs.length - 1];
                wrappedCDPs.pop();
                return wrappedCDPs[i];
            } 
        }
        return 0;
    }
    
    /**
     * @dev Unlock specific CDP by providing its ID
     */
    function unlockAnyCDP(uint256 CDPID) public returns(uint256 cdpid){
        // Get Token balance of sender
        uint256 balance = cdp_token.balanceOf(msg.sender);
        


        cdp_token.burn(msg.sender, depts[CDPID]);
        // Grant access right of CDP to sender
        mk_cdpman.give(CDPID, msg.sender);
         
        wrappedCDPs[CDPID] = wrappedCDPs[wrappedCDPs.length - 1];
        delete wrappedCDPs[wrappedCDPs.length - 1];
        wrappedCDPs.pop();
        return CDPID;
    }
    
    function getWrappedCDPCount() public view returns(uint count) {
        return wrappedCDPs.length;
    }
    
    
    // get Uniswap's exchange rate of DAI/WETH
    function getExchangeRate() public view returns (uint256) {
        (uint256 a, uint256 b) = getTokenReserves_uni();
        return a / b;
    }
    
    // get token reserves from the pool to determine the current exchange rate
    function getTokenReserves_uni()
        public
        view
        returns (uint256, uint256)
    {
        address pair = us_fac.getPair(DAI_TOKEN, Wrapped_ETH);
        
        (uint256 reserve0, uint256 reserve1, ) = UniswapV2PairLike(pair).getReserves();
            
        return (reserve0, reserve1);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "IERC20.sol";
import "IERC20Metadata.sol";
import "Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract CDPToken is Context, IERC20, IERC20Metadata {
    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name = "TokenizedCDP";
    string private _symbol = "tCDP";
    address private _tokenizer;
    
    modifier onlyCdpTokenizer {
        require(msg.sender==_tokenizer, "Not the Tokenizer");
        _;
    }

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (address tokenizer_) {
        _tokenizer = tokenizer_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        
        
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
     

    function mint(address account, uint256 amount) public onlyCdpTokenizer returns (bool) { 
        _mint(account, amount);
        return true;
    }
    
    function burn(address account, uint256 amount) public onlyCdpTokenizer returns (bool) { 
        _burn(account, amount);
        return true;
    }
    
    function setTokenizer(address account) public onlyCdpTokenizer returns (bool) { 
        _tokenizer = account;
        return true;
    }
    
    function tokenizerAddress() public view virtual returns (address) {
        return _tokenizer;
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// Proxy Registry Interface
interface ProxyRegistryLike {
    function proxies(address) external view returns (address);

    // build proxy contract
    function build(address owner) external;
}




// CDP Interface
// NEEDS TO BE PLACED INTO THE MAIN FAIL AFTER REMOVING TESTS
interface DssCdpManagerLike {
    function getFirstCDP(address addr) external view returns (uint);
    function getOwner(uint) external view returns (address);
    function give(uint cdp, address dst) external;
    function getURNHandler(uint256) external view returns(address); // CDPId => UrnHandler
}







contract inheritingForTestPurpose{
    
    ProxyRegistryLike private mk_proxy   = ProxyRegistryLike(0x4678f0a6958e4D2Bc4F1BAF7Bc52E8F3564f3fE4);
    address private mk_action  = 0x82ecD135Dce65Fbc6DbdD0e4237E0AF93FFD5038;
    DssCdpManagerLike private mk_cdpman  = DssCdpManagerLike(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    address private mk_jug     = 0x19c0976f590D67707E62397C87829d896Dc0f1F1;
    address private mk_ethjoin = 0x2F0b23f53734252Bda2277357e97e1517d6B042A;
    address private mk_daijoin = 0x9759A6Ac90977b93B58547b4A71c78317f391A28;
    bytes32 ilk =
        0x4554482d41000000000000000000000000000000000000000000000000000000;
    uint256 public cdpi;
    function buildProxyOpenCdpLockETH() public payable {
        if (mk_proxy.proxies(msg.sender) == address(0)) {
            mk_proxy.build(msg.sender);
            
        }
        
        
        bytes memory payload =
            abi.encodeWithSignature(
                "openLockETHAndDraw(address,address,address,address,bytes32,uint256)",
                mk_cdpman,
                mk_jug,
                mk_ethjoin,
                mk_daijoin,
                ilk,
                0
            );
             
             
        (bool success, ) = mk_proxy.proxies(msg.sender).call{value: msg.value}(abi.encodeWithSignature("execute(address,bytes)",
                                                                                                                    mk_action,
                                                                                                                    payload
                                                                                                                    ));
        require(success, "no success");
        cdpi = mk_cdpman.getFirstCDP(mk_proxy.proxies(msg.sender));
     }
    
}
