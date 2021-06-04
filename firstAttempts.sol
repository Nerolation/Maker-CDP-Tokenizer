// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "CDPToken.sol";

// Proxy Registry Interface
interface ProxyRegistryLike {
    function proxies(address) external view returns (address);

    // build proxy contract
    function build(address owner) external;
}

// CDP Interface
contract DssCdpManagerLike {
    mapping(address => uint256) public first; // Owner => First CDPId
}

contract CDPTokenizer {
     
    address private _owner;
    ProxyRegistryLike private mk_proxy   = ProxyRegistryLike(0x4678f0a6958e4D2Bc4F1BAF7Bc52E8F3564f3fE4);
    address private mk_action  = 0x82ecD135Dce65Fbc6DbdD0e4237E0AF93FFD5038;
    DssCdpManagerLike private mk_cdpman  = DssCdpManagerLike(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    address private mk_jug     = 0x19c0976f590D67707E62397C87829d896Dc0f1F1;
    address private mk_ethjoin = 0x2F0b23f53734252Bda2277357e97e1517d6B042A;
    address private mk_daijoin = 0x9759A6Ac90977b93B58547b4A71c78317f391A28;
    bytes32 ilk =
        0x4554482d41000000000000000000000000000000000000000000000000000000;
        
    CDPToken _tcdp;
    
    uint256 public cdpi;

     
     
     
     
    constructor() {
         _owner = msg.sender;
     }
     
     
    function createTokenContract() public returns(address) {
         _tcdp = new CDPToken(address(this));
         return address(_tcdp);
    }
     
    function updateCDPTokenizer(address newtokenizer) public {
         require(_tcdp.setTokenizer(newtokenizer), "Switch failed");
    }
     
     
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
        cdpi = mk_cdpman.first(mk_proxy.proxies(msg.sender));
     }
    
    
    
    
    
    
    
    
}
