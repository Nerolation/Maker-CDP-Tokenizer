// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "CDPToken.sol";
import "inheritingForTestPurpose.sol";



contract CDPTokenizer is inheritingForTestingPurpose{
     
    address private owner;
    mapping(address => uint256) tokenizedCDPs;  // Keep track of senders` CDP IDs
    mapping(uint256 => uint256) tokenization;   // Keep track of swap ratios
    
    CDPToken cdp_token;                         // Token Contract
    
    // Maker Dao 
    DssCdpManagerLike private mk_cdpman  = DssCdpManagerLike(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    ProxyRegistryLike private mk_proxy   = ProxyRegistryLike(0x4678f0a6958e4D2Bc4F1BAF7Bc52E8F3564f3fE4);
    
    
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
        // Get CDP ID
        uint CDPID = mk_cdpman.getFirstCDP(mk_proxy.proxies(msg.sender));
        
        mk_cdpman.give(CDPID, address(this));
        
        // Mint
        cdp_token.mint(msg.sender, 1 ether);
        
        // Store swap ratio
        tokenization[CDPID] = 1 ether;
        
        // Store address of locking entity
        tokenizedCDPs[msg.sender] = CDPID;
    }
    
    /**
     * @dev Overloaded function, see above.
     * 
     * Allows to specify a specific CDP by ID
     */
    function tokenizeCDP(uint256 CDPID) public {
         mk_cdpman.give(CDPID, address(this));
         cdp_token.mint(msg.sender, 1 ether);
         tokenization[CDPID] = 1 ether;
         tokenizedCDPs[msg.sender] = CDPID;
    }
    
    /**
     * @dev Overloaded function, see above.
     * 
     * Allows to split one's CDP in as many tokens as desired
     */
    function tokenizeCDP(uint256 CDPID,uint256 preferedNumber) public {
         mk_cdpman.give(CDPID, address(this));
         cdp_token.mint(msg.sender, preferedNumber);
         tokenization[CDPID] = preferedNumber;
         tokenizedCDPs[msg.sender] = CDPID;
    }
    
    /**
     * @dev Unlock CDP without any arguments 
     */
    function unlockCDP() public {
        // Get CDP ID
        uint CDPID = tokenizedCDPs[msg.sender];
        
        // Make sure that all minted tokens are returned
        require(tokenization[CDPID] == cdp_token.balanceOf(msg.sender), "Not all tokens provided");

        // Burn
        cdp_token.burn(msg.sender, tokenization[CDPID]);
        
        // Grant access right of CDP to sender
        mk_cdpman.give(CDPID, msg.sender);
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
