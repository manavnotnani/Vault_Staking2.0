// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;
import "library/Ownable.sol";
import "library/TransferHelper.sol";
import "interface/IERC20.sol";
// import "hardhat/console.sol";

contract VaultStaking2pointO is Ownable {
    address USDTtokenaddress;
    address CHBtokenaddress;
    uint256 contractDeploymentTimeStamp;



    uint256 numberOfVault;

    mapping(address => bool) vaultUserMapping;

    struct VaultStruct {
        uint256 vaultTimeStamp;
        uint256 VaultBalance;
        address vaultOwner;
        uint256 penaltyPercentage;
        uint256 APYpercentage;
        uint256 MinUSDTrequired;
        uint256 MaxUSDTstakedInVault;
    }

    uint256 vaultAndStakeCreatingTimePeriod = 2 minutes;
    uint256 maturityTimePeriod = 5 minutes;

    struct UserDetails {
        uint256 stakeAmount;
        uint256 stakeTimeStamp;
        bool isStaked;
    }

    mapping(address => mapping(uint256 => UserDetails)) public userMapping;
    mapping(uint256 => VaultStruct) public vaultID;

    constructor(address _USDTtokenaddress, address _CHBtokenaddress) {
        USDTtokenaddress = _USDTtokenaddress;
        CHBtokenaddress = _CHBtokenaddress;
        contractDeploymentTimeStamp = block.timestamp;
    }

    function createVault(
        uint256 _penaltyPercentage,
        uint256 _APYPercentage,
        uint256 _MinUSDTrequired,
        uint256 _MaxUSDTstakedInVault
    ) public returns (bool success) {
        require(
            block.timestamp <
                contractDeploymentTimeStamp + vaultAndStakeCreatingTimePeriod,
            "Vault creation time exceeded"
        );
        require(!vaultUserMapping[msg.sender], "User can create vault once");
        VaultStruct storage vaults = vaultID[++numberOfVault];
        vaults.vaultTimeStamp = block.timestamp;
        vaults.vaultOwner = msg.sender;

        vaults.penaltyPercentage = _penaltyPercentage;
        vaults.APYpercentage = _APYPercentage;
        vaults.MinUSDTrequired = _MinUSDTrequired;
        vaults.MaxUSDTstakedInVault = _MaxUSDTstakedInVault;

        vaultUserMapping[msg.sender] = true;

        return true;
    }

    function stakeUSDT(uint256 _stakeAmount, uint256 _vaultId)
        public
        returns (bool success)
    {
        require(_stakeAmount > 0, "Stake amount should be greater than 0");
        require(
            block.timestamp <
                contractDeploymentTimeStamp + vaultAndStakeCreatingTimePeriod,
            "Staking time exceeded"
        );

        require(IERC20(USDTtokenaddress).balanceOf(msg.sender) >= _stakeAmount, "Not enough balance");
        require(
            IERC20(USDTtokenaddress).allowance(msg.sender, address(this)) >=
                _stakeAmount
        );
        require(
            _stakeAmount <= vaultID[_vaultId].MaxUSDTstakedInVault,
            "Max. staked amount in vault exceeded"
        );

        require(
            vaultID[_vaultId].MinUSDTrequired < _stakeAmount,
            "Stake Amount is less"
        );

        UserDetails storage udetails = userMapping[msg.sender][_vaultId];

        if (udetails.isStaked) {
            udetails.stakeAmount += _stakeAmount;
        } else {
            udetails.stakeAmount = _stakeAmount;
        }

        TransferHelper.safeTransferFrom(
            USDTtokenaddress,
            msg.sender,
            address(this),
            _stakeAmount
        );

        vaultID[_vaultId].VaultBalance += _stakeAmount;
        udetails.isStaked = true;

        udetails.stakeTimeStamp = block.timestamp;

        return true;
    }

    function unstakeUSDT(uint256 _vaultId) public returns (bool success) {
        UserDetails storage udetailsnew = userMapping[msg.sender][_vaultId];

        require(udetailsnew.isStaked, "User has not staked yet");

        require(
            block.timestamp >
                contractDeploymentTimeStamp + vaultAndStakeCreatingTimePeriod,
            "User has to wait for atleast vaultAndStakeCreatingTimePeriod for unstaking"
        );
        uint256 userRewards = ((99 * 100 * calculateRewardTokens(_vaultId)) /
            10000);
        uint256 ownerRewards = (calculateRewardTokens(_vaultId) * 1 * 100) /
            10000;

        // console.log(
        //     udetailsnew.stakeAmount,
        //     "stake amount before transferring"
        // );
        // console.log(userRewards, "reward tokens before transferring");

        if (
            block.timestamp >= udetailsnew.stakeTimeStamp + maturityTimePeriod
        ) {
            TransferHelper.safeTransfer(
                USDTtokenaddress,
                msg.sender,
                udetailsnew.stakeAmount
            );
            // console.log(udetailsnew.stakeAmount, "stake amount");
            // console.log(userRewards, "reward tokens");

            TransferHelper.safeTransfer(
                CHBtokenaddress,
                msg.sender,
                userRewards
            );
            // console.log(userRewards, "reward tokens after transferring");

            // console.log(ownerRewards, "Reward tokens for owner");

            TransferHelper.safeTransfer(
                CHBtokenaddress,
                vaultID[_vaultId].vaultOwner,
                ownerRewards
            );
        } else {
            uint256 penalty = (vaultID[_vaultId].penaltyPercentage *
                udetailsnew.stakeAmount *
                100) / 10000;
            TransferHelper.safeTransfer(USDTtokenaddress, owner, penalty);
            TransferHelper.safeTransfer(
                USDTtokenaddress,
                msg.sender,
                (udetailsnew.stakeAmount - penalty)
            );
        }
        vaultID[_vaultId].VaultBalance -= udetailsnew.stakeAmount;

        udetailsnew.isStaked = false;
        return true;
    }

    function calculateRewardTokens(uint256 _vaultId)
        public
        view
        returns (uint256)
    {
        UserDetails memory udetailsnew3 = userMapping[msg.sender][_vaultId];
        // uint256 rewards = (vaultID[_vaultId].APYpercentage *
        //     udetailsnew3.stakeAmount *
        //     maturityTimePeriod *
        //     100) / 10000 * maturityTimePeriod;

        uint256 rewards = (udetailsnew3.stakeAmount *
            vaultID[_vaultId].APYpercentage *
            (10**IERC20(CHBtokenaddress).decimals()) *
            100) / ((10**IERC20(USDTtokenaddress).decimals()) * 10000);

        if (
            block.timestamp - udetailsnew3.stakeTimeStamp < maturityTimePeriod
        ) {
            rewards = 0;
        }

        return rewards;
    }
}
