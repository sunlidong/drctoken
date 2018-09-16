pragma solidity ^0.4.17;

import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import './OwnerContract.sol';
import './LockedStorageInterface.sol';
import './FlyDropTokenMgrInterface.sol';


/**
 * contract that manage the DRCT lock and release mechanism
 */
contract ReleaseAndLockToken is OwnerContract {
    using SafeMath for uint256;

    ILockedStorage public lockedStorage;
    IFlyDropTokenMgr public flyDropMgr;
    // ERC20 public erc20tk;
    mapping (address => uint256) preReleaseAmounts;

    event ReleaseFunds(address indexed _target, uint256 _amount);

    /**
     * @dev bind a contract as its owner
     *
     * @param _contract the LockedStorage contract address that will be binded by this Owner Contract
     * @param _flyDropcontract the flydrop contract for transfer tokens from the fixed main accounts
     * @param _tk the erc20 token address
     */
    function initialize(address _contract, address _flyDropContract/*, address _tk*/) onlyOwner public returns (bool) {
        require(_contract != address(0));
        require(_flyDropContract != address(0));
        require(_tk != address(0));

        require(super.bindContract(_contract));
        lockedStorage = ILockedStorage(_contract);
        flyDropMgr = IFlyDropTokenMgr(_flyDropContract);
        // erc20tk = ERC20(_tk);

        return true;
    }

    /**
     * @dev remove an account from the frozen accounts list
     *
     * @param _ind the index of the account in the list
     */
    // function removeAccount(uint _ind) internal returns (bool) {
    //     require(_ind < frozenAccounts.length);
        
    //     uint256 i = _ind;
    //     while (i < frozenAccounts.length.sub(1)) {
    //         frozenAccounts[i] = frozenAccounts[i.add(1)];
    //         i = i.add(1);
    //     }
        
    //     delete frozenAccounts[frozenAccounts.length.sub(1)];
    //     frozenAccounts.length = frozenAccounts.length.sub(1);
    //     return true;
    // }

    /**
     * @dev remove a time records from the time records list of one account
     *
     * @param _target the account that holds a list of time records which record the freeze period
     */
    // function removeLockedTime(address _target, uint _ind) internal returns (bool) {
    //     require(_target != address(0));

    //     TimeRec[] storage lockedTimes = frozenTimes[_target];
    //     require(_ind < lockedTimes.length);
       
    //     uint256 i = _ind;
    //     while (i < lockedTimes.length.sub(1)) {
    //         lockedTimes[i] = lockedTimes[i.add(1)];
    //         i = i.add(1);
    //     }
        
    //     delete lockedTimes[lockedTimes.length.sub(1)];
    //     lockedTimes.length = lockedTimes.length.sub(1);
    //     return true;
    // }

    /**
     * @dev get total remain locked tokens of an account
     *
     * @param _account the owner of some amount of tokens
     */
    function getRemainLockedOf(address _account) public view returns (uint256) {
        require(_account != address(0));

        uint256 totalRemain = 0;
        uint256 len = lockedStorage.size();
        uint256 i = 0;
        while (i < len) {
            address frozenAddr = lockedStorage.addressByIndex(i);
            if (frozenAddr == _account) {
                uint256 timeRecLen = lockedStorage.lockedStageNum(_account);
                uint256 j = 0;
                while (j < timeRecLen) {
                    totalRemain = totalRemain.add(lockedStorage.remainLockedOf(_account, j));

                    j = j.add(1);
                }
                break;
            }

            i = i.add(1);
        }

        return totalRemain;
    }

    /**
     * judge whether we need to release some of the locked token
     *
     */
    function needRelease() public view returns (bool) {
        uint256 len = lockedStorage.size();
        uint256 i = 0;
        while (i < len) {
            address frozenAddr = lockedStorage.addressByIndex(i);
            uint256 timeRecLen = lockedStorage.lockedStageNum(frozenAddr);
            uint256 j = 0;
            while (j < timeRecLen) {
                // TimeRec storage timePair = frozenTimes[frozenAddr][j];
                if (now >= lockedStorage.endTimeOfStage(frozenAddr, j)) {
                    return true;
                }

                j = j.add(1);
            }

            i = i.add(1);
        }

        return false;
    }

    /**
     * @dev judge whether we need to release the locked token of the target address
     * @param _target the owner of the amount of tokens
     *
     */
    function needRelease(address _target) public view returns (bool) {
        require(_target != address(0));

        uint256 timeRecLen = lockedStorage.lockedStageNum(_target);
        uint256 j = 0;
        while (j < timeRecLen) {
            if (now >= lockedStorage.endTimeOfStage(frozenAddr, j)) {
                return true;
            }

            j = j.add(1);
        }

        return false;
    }

    /**
     * @dev freeze the amount of tokens of an account
     *
     * @param _target the owner of some amount of tokens
     * @param _name the user name of the _target
     * @param _value the amount of the tokens
     * @param _frozenEndTime the end time of the lock period, unit is second
     * @param _releasePeriod the locking period, unit is second
     */
    function freeze(address _target, string _name, uint256 _value, uint256 _frozenEndTime, uint256 _releasePeriod) onlyOwner public returns (bool) {
        //require(_tokenAddr != address(0));
        require(_target != address(0));
        require(_value > 0);
        require(_frozenEndTime > 0);

        if (!lockedStorage.isExisted(_target)) {
            lockedStorage.addAccount(_target, _name, _value); // add new account
        } 
        
        // each time the new locked time will be added to the backend
        require(lockedStorage.addLockedTime(_target, _value, _frozenEndTime, _releasePeriod));
        require(lockedStorage.freezeTokens(_target, true, _value));
        
        return true;
    }

    /**
     * @dev transfer an amount of tokens to an account, and then freeze the tokens
     *
     * @param _target the account address that will hold an amount of the tokens
     * @param _name the user name of the _target
     * @param _tk the erc20 token need to be transferred
     * @param _value the amount of the tokens which has been transferred
     * @param _frozenEndTime the end time of the lock period, unit is second
     * @param _releasePeriod the locking period, unit is second
     */
    function transferAndFreeze(address _target, 
                               string _name, 
                               address _from,
                               address _tk, 
                               uint256 _value, 
                               uint256 _frozenEndTime, 
                               uint256 _releasePeriod) onlyOwner public returns (bool) {
        //require(_tokenOwner != address(0));
        require(_target != address(0));
        require(_value > 0);
        require(_frozenEndTime > 0);

        // check firstly that the allowance of this contract has been set
        // require(owned.allowance(msg.sender, this) > 0);
        uint rand = now % 6 + 7; // random number between 7 to 12
        require(flyDropMgr.prepare(rand, _from, _tk, _value));

        // now we need transfer the funds before freeze them
        // require(owned.transferFrom(msg.sender, lockedStorage, _value));
        address[] memory dest = [address(lockedStorage)];
        uint256[] memory amount = [uint256(_value)];
        require(flyDropMgr.flydrop(dest, amount));
        require(lockedStorage.increaseBalance(_target, _value));

        // freeze the account after transfering funds
        return freeze(_target, _name, _value, _frozenEndTime, _releasePeriod);
    }

    /**
     * @dev transfer an amount of tokens to an account, and then freeze the tokens
     *
     * @param _target the account address that will hold an amount of the tokens
     * @param _tk the erc20 token need to be transferred
     * @param _value the amount of the tokens which has been transferred
     */
    function releaseTokens(address _target, address _tk, uint256 _value) internal {
        require(lockedStorage.withdrawToken(_tk, _target, _value));
        require(lockedStorage.freezeTokens(_target, false, _value));
        require(lockedStorage.decreaseBalance(_target, _value));
    }

    /**
     * @dev release the token which are locked for once and will be total released at once 
     * after the end point of the lock period
     * @param _tk the erc20 token need to be transferred
     */
    function releaseAllOnceLock(address _tk) onlyOwner public returns (bool) {
        require(_tk != address(0));

        uint256 len = lockedStorage.size();
        uint256 i = 0;
        while (i < len) {
            address target = lockedStorage.addressByIndex(i);
            if (lockedStorage.lockedStageNum(target) == 1 
                && lockedStorage.endTimeOfStage(target, 0) == lockedStorage.releaseEndTimeOfStage(target, 0) 
                && lockedStorage.endTimeOfStage(target, 0) > 0 
                && now >= lockedStorage.endTimeOfStage(target, 0)) {
                uint256 releasedAmount = lockedStorage.amountOfStage(target, 0);
                    
                // remove current release period time record
                if (!lockedStorage.removeLockedTime(target, 0)) {
                    return false;
                }

                // remove the froze account
                if (!lockedStorage.removeAccount(target)) {
                    return false;
                }

                releaseTokens(target, _tk, releasedAmount);               
                ReleaseFunds(target, releasedAmount);
                len = len.sub(1);
            } else { 
                // no account has been removed
                i = i.add(1);
            }
        }
        
        return true;
    }

    /**
     * @dev release the locked tokens owned by an account, which only have only one locked time
     * and don't have release stage.
     *
     * @param _target the account address that hold an amount of locked tokens
     * @param _tk the erc20 token need to be transferred
     */
    function releaseAccount(address _target, address _tk) onlyOwner public returns (bool) {
        require(_tk != address(0));

        if (!lockedStorage.isExisted(_target)) {
            return false;
        }

        if (lockedStorage.lockedStageNum(target) == 1 
            && lockedStorage.endTimeOfStage(target, 0) == lockedStorage.releaseEndTimeOfStage(target, 0) 
            && lockedStorage.endTimeOfStage(target, 0) > 0 
            && now >= lockedStorage.endTimeOfStage(target, 0)) {
            uint256 releasedAmount = lockedStorage.amountOfStage(target, 0);
                    
            // remove current release period time record
            if (!lockedStorage.removeLockedTime(target, 0)) {
                return false;
            }

            // remove the froze account
            if (!lockedStorage.removeAccount(target)) {
                return false;
            }

            releaseTokens(target, _tk, releasedAmount);               
            ReleaseFunds(target, releasedAmount);
        }

        // if the account are not locked for once, we will do nothing here
        return true; 
    }    

    /**
     * @dev release the locked tokens owned by an account with several stages
     * this need the contract get approval from the account by call approve() in the token contract
     *
     * @param _target the account address that hold an amount of locked tokens
     * @param _tk the erc20 token need to be transferred
     */
    function releaseWithStage(address _target, address _tk) onlyOwner public returns (bool) {
        require(_tk != address(0));
        
        if (!lockedStorage.isExisted(_target)) {
            return false;
        }

        uint256 timeRecLen = lockedStorage.lockedStagesNum(_target);
        bool released = false;
        uint256 nowTime = now;
        for (uint256 j = 0; j < timeRecLen; released = false) {
            // iterate every time records to caculate how many tokens need to be released.
            uint256 endTime = lockedStorage.endTimeOfStage(_target, j);
            uint256 releasedEndTime = lockedStorage.releaseEndTimeOfStage(_target, j);
            uint256 amount = lockedStorage.amountOfStage(_target, j);   
            uint256 remain = lockedStorage.remainLockedOf(_target, j);       
            if (nowTime > endTime && endTime > 0 && releasedEndTime > endTime) {              
                uint256 lastReleased = amount.sub(remain);
                uint256 value = (amount * nowTime.sub(endTime) / releasedEndTime.sub(endTime)).sub(lastReleased);
                
                if (value > remain) {
                    value = remain;
                }                 
                lockedStorage.decreaseRemainLockedOf(_target, j, _value);
                ReleaseFunds(_target, value);

                preReleaseAmounts[_target] = preReleaseAmounts[_target].add(value);
                if (remain < 1e8) {
                    if (!lockedStorage.removeLockedTime(_target, j)) {
                        return false;
                    }
                    released = true;
                    timeRecLen = timeRecLen.sub(1);
                }
            } else if (nowTime >= endTime && endTime > 0 && releasedEndTime == endTime) {                        
                lockedStorage.decreaseRemainLockedOf(_target, j, remain);
                ReleaseFunds(_target, amount);
                preReleaseAmounts[_target] = preReleaseAmounts[_target].add(amount);
                if (!lockedStorage.removeLockedTime(_target, j)) {
                    return false;
                }
                released = true;
                timeRecLen = timeRecLen.sub(1);
            } 

            if (!released) {
                j = j.add(1);
            }
        }

        // we got some amount need to be released
        if (preReleaseAmounts[_target] > 0) {
            uint256 preReleasedAmount = preReleaseAmounts[frozenAddr];
                   
            // set the pre-release amount to 0 for next time
            preReleaseAmounts[frozenAddr] = 0;
            releaseTokens(_target, _tk, preReleasedAmount);
        }

        // if all the frozen amounts had been released, then unlock the account finally
        if (lockedStorage.lockedStagesNum(_target) == 0) {
            if (!lockedStorage.removeAccount(_target)) {
                return false;
            }                    
        }

        return true;
    }

    /**
     * @dev set the new endtime of the released time of an account
     *
     * @param _target the owner of some amount of tokens
     * @param _oldEndTime the original endtime for the lock period, unit is second
     * @param _oldDuration the original duration time for the released period, unit is second
     * @param _newEndTime the new endtime for the lock period
     */
    function setNewEndtime(address _target, uint256 _oldEndTime, uint256 _oldDuration, uint256 _newEndTime) onlyOwner public returns (bool) {
        require(_target != address(0));
        require(_oldEndTime > 0 && _newEndTime > 0);
        
        if (!lockedStorage.isExisted(_target)) {
            return false;
        }

        uint256 timeRecLen = lockedStorage.lockedStagesNum(_target);
        uint256 j = 0;
        while (j < timeRecLen) {
            uint256 endTime = lockedStorage.endTimeOfStage(_target, j);
            uint256 releasedEndTime = lockedStorage.releaseEndTimeOfStage(_target, j);
            if (_oldEndTime == endTime && _oldDuration == releasedEndTime.sub(endTime)) {
                return lockedStorage.changeEndTime(_target, j, _newEndTime);
            }

            j = j.add(1);
        }

        return false;
    }

    /**
     * @dev set the new released period length of an account
     *
     * @param _target the owner of some amount of tokens
     * @param _origEndTime the original endtime for the lock period
     * @param _origDuration the original duration time for the released period, unit is second
     * @param _duration the new releasing period
     */
    function setNewReleasePeriod(address _target, uint256 _origEndTime, uint256 _origDuration, uint256 _newDuration) onlyOwner public returns (bool) {
        require(_target != address(0));
        require(_origEndTime > 0);
        
        if (!lockedStorage.isExisted(_target)) {
            return false;
        }

        uint256 timeRecLen = lockedStorage.lockedStagesNum(_target);
        uint256 j = 0;
        while (j < timeRecLen) {
            uint256 endTime = lockedStorage.endTimeOfStage(_target, j);
            uint256 releasedEndTime = lockedStorage.releaseEndTimeOfStage(_target, j);
            if (_origEndTime == endTime && _origDuration == releasedEndTime.sub(endTime)) {
                return lockedStorage.setNewReleaseEndTime(_target, j, _origEndTime.add(_newDuration));
            }

            j = j.add(1);
        }

        return false;
    }

    /**
     * @dev get the locked stages of an account
     *
     * @param _target the owner of some amount of tokens
     */
    function getLockedStages(address _target) public view returns (uint) {
        require(_target != address(0));

        return lockedStorage.lockedStagesNum(_target);
    }

    /**
     * @dev get the endtime of the locked stages of an account
     *
     * @param _target the owner of some amount of tokens
     * @param _num the stage number of the releasing period
     */
    function getEndTimeOfStage(address _target, uint _num) public view returns (uint256) {
        require(_target != address(0));        

        return lockedStorage.endTimeOfStage(_target, _num);
    }

    /**
     * @dev get the remain unrleased tokens of the locked stages of an account
     *
     * @param _target the owner of some amount of tokens
     * @param _num the stage number of the releasing period
     */
    function getRemainOfStage(address _target, uint _num) public view returns (uint256) {
        require(_target != address(0));
        
        return lockedStorage.remainOfStage(_target, _num);
    }

    /**
     * @dev get the remain releasing period of an account
     *
     * @param _target the owner of some amount of tokens
     * @param _num the stage number of the releasing period
     */
    function getRemainReleaseTimeOfStage(address _target, uint _num) public view returns (uint256) {
        require(_target != address(0));
       
        uint256 nowTime = now; 
        uint256 releaseEndTime = lockedStorage.releaseEndTimeOfStage(_target, _num);  

        if (releaseEndTime == 0 || releaseEndTime < nowTime) {
            return 0;
        }
        
        uint256 endTime = lockedStorage.endTimeOfStage(_target, _num);
        if (releaseEndTime == endTime || nowTime <= endTime ) {
            return (releaseEndTime.sub(endTime));
        }  

        return (releaseEndTime.sub(nowTime)); 
    }

    /**
     * @dev release the locked tokens owned by a number of accounts
     *
     * @param _targets the accounts list that hold an amount of locked tokens 
     * @param _tk the erc20 token need to be transferred
     */
    function releaseMultiAccounts(address[] _targets, address _tk) onlyOwner public returns (bool) {
        require(_targets.length != 0);

        bool res = false;
        uint256 i = 0;
        while (i < _targets.length) {
            res = releaseAccount(_targets[i], _tk) || res;
            i = i.add(1);
        }

        return res;
    }

    /**
     * @dev release the locked tokens owned by an account
     *
     * @param _targets the account addresses list that hold amounts of locked tokens
     * @param _tk the erc20 token need to be transferred
     */
    function releaseMultiWithStage(address[] _targets, address _tk) onlyOwner public returns (bool) {
        require(_targets.length != 0);
        
        bool res = false;
        uint256 i = 0;
        while (i < _targets.length) {
            res = releaseWithStage(_targets[i], _tk) || res; // as long as there is one true transaction, then the result will be true
            i = i.add(1);
        }

        return res;
    }

     /**
     * @dev freeze multiple of the accounts
     *
     * @param _targets the owners of some amount of tokens
     * @param _names the user names of the _targets
     * @param _values the amounts of the tokens
     * @param _frozenEndTimes the list of the end time of the lock period, unit is second
     * @param _releasePeriods the list of the locking period, unit is second
     */
    function freezeMulti(address[] _targets, string[] names, uint256[] _values, uint256[] _frozenEndTimes, uint256[] _releasePeriods) onlyOwner public returns (bool) {
        require(_targets.length != 0);
        require(_names.length != 0);
        require(_values.length != 0);
        require(_frozenEndTimes.length != 0);
        require(_releasePeriods.length != 0);
        require(_targets.length == names.length && names.length == _values.length && _values.length == _frozenEndTimes.length && _frozenEndTimes.length == _releasePeriods.length);

        bool res = true;
        for (uint256 i = 0; i < _targets.length; i = i.add(1)) {
            // as long as one transaction failed, then the result will be failure
            res = freeze(_targets[i], names[i], _values[i], _frozenEndTimes[i], _releasePeriods[i]) && res; 
        }

        return res;
    }

    /**
     * @dev transfer a list of amounts of tokens to a list of accounts, and then freeze the tokens
     *
     * @param _targets the account addresses that will hold a list of amounts of the tokens
     * @param _names the user names of the _targets
     * @param _tk the erc20 token need to be transferred
     * @param _values the amounts of the tokens which have been transferred
     * @param _frozenEndTimes the end time list of the locked periods, unit is second
     * @param _releasePeriods the list of locking periods, unit is second
     */
    function transferAndFreezeMulti(address[] _targets, strings[] _names, address _tk, uint256[] _values, uint256[] _frozenEndTimes, uint256[] _releasePeriods) onlyOwner public returns (bool) {
        require(_targets.length != 0);
        require(_names.length != 0);
        require(_values.length != 0);
        require(_frozenEndTimes.length != 0);
        require(_releasePeriods.length != 0);
        require(_targets.length == names.length && names.length == _values.length && _values.length == _frozenEndTimes.length && _frozenEndTimes.length == _releasePeriods.length);

        bool res = true;
        for (uint256 i = 0; i < _targets.length; i = i.add(1)) {
            // as long as one transaction failed, then the result will be failure
            res = transferAndFreeze(_targets[i], names[i], _tk, _values[i], _frozenEndTimes[i], _releasePeriods[i]) && res; 
        }

        return res;
    }
}
