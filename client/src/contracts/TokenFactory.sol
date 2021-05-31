pragma solidity ^0.8.2;

// import "./ProductToken.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract TokenFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable { // is Initializable{

	// address daiAddress;
	// address chainlinkAddress;
	IBeacon public beacon;
	mapping(string => address) registry;

	function initialize(address _beacon) public initializer {
		UpdateBeacon(_beacon);
	}

	function UpdateBeacon(address _beacon) internal {
		require( Address.isContract(_beacon), "Invalid Beacon address");
		beacon = IBeacon(_beacon);
	}

	function createToken(string memory _productName, bytes memory _data) public {
		require(registry[_productName]==address(0), "The product token already exist");
		address newProxyToken = address(new BeaconProxy(address(beacon), _data));
		registry[_productName] = newProxyToken;
	}

	function retrieveToken(string memory _productName) public view returns(address) {
		require(registry[_productName]!=address(0), "This product token does not exist");
		return registry[_productName];
	}

	function _authorizeUpgrade(address) internal override onlyOwner {}

}
