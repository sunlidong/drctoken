pragma solidity ^0.4.17;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';

interface itoken {
    // mapping (address => bool) public frozenAccount;
    function freezeAccount(address _target, bool _freeze) external;
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
    function balanceOf(address _owner) external view returns (uint256 balance);
    function transferOwnership(address newOwner) external;
}

contract OwnerContract is Ownable {
    itoken public owned;
    
    /**
     * @dev bind a contract as its owner
     *
     * @param _contract the contract address that will be binded by this Owner Contract
     */
    function setContract(address _contract) public onlyOwner {
        require(_contract != address(0));
        owned = itoken(_contract);
    }

    /**
     * @dev change the owner of the contract from this contract to another 
     *
     * @param _newOwner the new contract/account address that will be the new owner
     */
    function changeContractOwner(address _newOwner) public onlyOwner returns(bool) {
        require(_newOwner != address(0));
        owned.transferOwnership(_newOwner);
        owned = itoken(address(0));
        
        return true;
    }
}

contract ReleaseToken is OwnerContract {
    using SafeMath for uint256;

    // record lock time period and related token amount
    struct TimeRec {
        uint256 amount;
        uint256 remain;
        uint256 endTime;
        uint256 duration;
    }

    address[] public frozenAccounts;
    mapping (address => TimeRec[]) frozenTimes;

    event ReleaseFunds(address _target, uint256 _amount);

    /**
     * @dev get total remain locked tokens of an account
     *
     * @param _account the owner of some amount of tokens
     */
    function getRemainLockedOf(address _account) public view returns (uint256) {
        require(_account != address(0));

        uint256 totalRemain = 0;
        uint256 len = frozenAccounts.length;
        uint256 i = 0;
        while (i < len) {
            address frozenAddr = frozenAccounts[i];
            if (frozenAddr == _account) {
                uint256 timeRecLen = frozenTimes[frozenAddr].length;
                uint256 j = 0;
                while (j < timeRecLen) {
                    TimeRec storage timePair = frozenTimes[frozenAddr][j];
                    totalRemain = totalRemain.add(timePair.remain);

                    j = j.add(1);
                }
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
        uint256 len = frozenAccounts.length;
        uint256 i = 0;
        while (i < len) {
            address frozenAddr = frozenAccounts[i];
            uint256 timeRecLen = frozenTimes[frozenAddr].length;
            uint256 j = 0;
            while (j < timeRecLen) {
                TimeRec storage timePair = frozenTimes[frozenAddr][j];
                if (now >= timePair.endTime) {
                    return true;
                }

                j = j.add(1);
            }

            i = i.add(1);
        }

        return false;
    }

    /**
     * @dev freeze the amount of tokens of an account
     *
     * @param _target the owner of some amount of tokens
     * @param _value the amount of the tokens
     * @param _frozenEndTime the end time of the lock period, unit is second
     * @param _releasePeriod the locking period, unit is second
     */
    function freeze(address _target, uint256 _value, uint256 _frozenEndTime, uint256 _releasePeriod) onlyOwner public returns (bool) {
        //require(_tokenAddr != address(0));
        require(_target != address(0));
        require(_value > 0);
        require(_frozenEndTime > 0 && _releasePeriod >= 0);

        uint256 len = frozenAccounts.length;
        uint256 i = 0;
        while (i < len) {
            if (frozenAccounts[i] == _target) {
                break;
            }
            i = i.add(1);
        }

        if (i >= len) {
            frozenAccounts.push(_target);
            frozenTimes[_target].push(TimeRec(_value, _value, _frozenEndTime, _releasePeriod));
        } else {
            uint256 timeArrayLen = frozenTimes[_target].length;
            uint256 j = 0;
            while (j < timeArrayLen) {
                TimeRec storage lastTime = frozenTimes[_target][j];
                if (lastTime.amount == 0 && lastTime.remain == 0 && lastTime.endTime == 0 && lastTime.duration == 0) {
                    lastTime.amount = _value;
                    lastTime.remain = _value;
                    lastTime.endTime = _frozenEndTime;
                    lastTime.duration = _releasePeriod; 
                }

                j = j.add(1);
            }
            
            frozenTimes[_target].push(TimeRec(_value, _value, _frozenEndTime, _releasePeriod));
        }

        // frozenTimes[_target] = _frozenEndTime;
        owned.freezeAccount(_target, true);
        
        return true;
    }

    /**
     * @dev transfer an amount of tokens to an account, and then freeze the tokens
     *
     * @param _tokenOwner the owner of the tokens that need to transfer to an account
     * @param _target the account address that will hold an amount of the tokens
     * @param _value the amount of the tokens which has been transferred
     * @param _frozenEndTime the end time of the lock period, unit is second
     * @param _releasePeriod the locking period, unit is second
     */
    function transferAndFreeze(address _tokenOwner, address _target, uint256 _value, uint256 _frozenEndTime, uint256 _releasePeriod) onlyOwner public returns (bool) {
        require(_tokenOwner != address(0));
        require(_target != address(0));
        require(_value > 0);
        require(_frozenEndTime > 0 && _releasePeriod >= 0);

        if (!freeze(_target, _value, _frozenEndTime, _releasePeriod)) {
            return false;
        }

        return (owned.transferFrom(_tokenOwner, _target, _value));
    }

    /**
     * release the token which are locked for once and will be total released at once 
     * after the end point of the lock period
     */
    function release() onlyOwner public returns (bool) {
        //require(_tokenAddr != address(0));

        uint256 len = frozenAccounts.length;
        uint256 i = 0;
        while (i < len) {
            address destAddr = frozenAccounts[i];
            if (frozenTimes[destAddr].length == 1 && 0 == frozenTimes[destAddr][0].duration && frozenTimes[destAddr][0].endTime > 0 && now >= frozenTimes[destAddr][0].endTime) {
                owned.freezeAccount(destAddr, false);
                frozenTimes[destAddr][0].endTime = 0;
                frozenTimes[destAddr][0].duration = 0;
                ReleaseFunds(destAddr, frozenTimes[destAddr][0].amount);
                frozenTimes[destAddr][0].amount = 0;
                frozenTimes[destAddr][0].remain = 0;
            }

            i = i.add(1);
        }
        
        return true;
    }

    /**
     * @dev release the locked tokens owned by an account
     *
     * @param _target the account address that hold an amount of locked tokens
     */
    function releaseAccount(address _target) onlyOwner public returns (bool) {
        //require(_tokenAddr != address(0));
        require(_target != address(0));

        uint256 len = frozenAccounts.length;
        uint256 i = 0;
        while (i < len) {
            address destAddr = frozenAccounts[i];
            if (destAddr == _target) {
                if (frozenTimes[destAddr].length == 1 && 0 == frozenTimes[destAddr][0].duration && frozenTimes[destAddr][0].endTime > 0 && now >= frozenTimes[destAddr][0].endTime) {
                    owned.freezeAccount(destAddr, false);
                    frozenTimes[destAddr][0].endTime = 0;
                    frozenTimes[destAddr][0].duration = 0;
                    ReleaseFunds(destAddr, frozenTimes[destAddr][0].amount);
                    frozenTimes[destAddr][0].amount = 0;
                    frozenTimes[destAddr][0].remain = 0;

                    return true;
                } else {
                    return false;
                }
            }

            i = i.add(1);
        }
        
        return false;
    }

    /**
     * @dev release the locked tokens owned by a number of accounts
     *
     * @param _targets the accounts list that hold an amount of locked tokens 
     */
    function releaseMultiAccounts(address[] _targets) onlyOwner public returns (bool) {
        //require(_tokenAddr != address(0));
        require(_targets.length != 0);

        uint256 i = 0;
        while (i < _targets.length) {
            if (!releaseAccount(_targets[i])) {
                return false;
            }

            i = i.add(1);
        }

        return true;
    }

    /**
     * @dev release the locked tokens owned by an account
     *
     * @param _target the account address that hold an amount of locked tokens
     * @param _dest the secondary address that will hold the released tokens
     */
    function releaseWithAmount(address _target, address _dest) onlyOwner public returns (bool) {
        //require(_tokenAddr != address(0));
        require(_target != address(0));
        require(_dest != address(0));
        // require(_value > 0);

        uint256 len = frozenAccounts.length;
        uint256 i = 0;
        while (i < len) {
            // firstly find the target address
            address frozenAddr = frozenAccounts[i];
            if (frozenAddr == _target) {
                uint256 timeRecLen = frozenTimes[frozenAddr].length;
                uint256 releasedNum = timeRecLen;
                uint256 j = 0;
                while (j < timeRecLen) {
                    // iterate every time records to caculate how many tokens need to be released.
                    TimeRec storage timePair = frozenTimes[frozenAddr][j];
                    uint256 nowTime = now;
                    if (nowTime > timePair.endTime && timePair.endTime > 0 && timePair.duration > 0) {                        
                        uint256 value = timePair.amount * (nowTime - timePair.endTime) / timePair.duration;
                        if (value > timePair.remain) {
                            value = timePair.remain;
                        } 

                        owned.freezeAccount(frozenAddr, false);
                        if (!owned.transferFrom(_target, _dest, value)) {
                            return false;
                        }
                        owned.freezeAccount(frozenAddr, true);
                        ReleaseFunds(frozenAddr, value);
                        timePair.endTime = nowTime;        
                        timePair.remain = timePair.remain.sub(value);
                        if (timePair.remain < 1e8) {
                            timePair.remain = 0;
                            timePair.amount = 0;
                            timePair.endTime = 0;
                            timePair.duration = 0;

                            releasedNum = releasedNum.sub(1);
                        }
                    } else if (nowTime >= timePair.endTime && timePair.endTime > 0 && timePair.duration == 0) {
                        owned.freezeAccount(frozenAddr, false);
                        if (!owned.transferFrom(_target, _dest, timePair.amount)) {
                            return false;
                        }

                        owned.freezeAccount(frozenAddr, true);
                        ReleaseFunds(frozenAddr, timePair.amount);
                        timePair.endTime = 0;
                        timePair.amount = 0;
                        timePair.remain = 0;

                        releasedNum = releasedNum.sub(1);
                    } else if (timePair.amount == 0 && timePair.remain == 0 && timePair.endTime == 0 && timePair.duration == 0) {
                        releasedNum = releasedNum.sub(1);
                    }

                    j = j.add(1);
                }

                // if all the frozen amounts had been released, then unlock the account finally
                if (releasedNum == 0) {
                    owned.freezeAccount(frozenAddr, false);
                }

                return true;
            }          

            i = i.add(1);
        }
        
        return false;
    }

    /**
     * @dev release the locked tokens owned by an account
     *
     * @param _targets the account addresses list that hold amounts of locked tokens
     * @param _dests the secondary addresses list that will hold the released tokens for each target account
     */
    function releaseMultiWithAmount(address[] _targets, address[] _dests) onlyOwner public returns (bool) {
        //require(_tokenAddr != address(0));
        require(_targets.length != 0);
        require(_dests.length != 0);
        assert(_targets.length == _dests.length);

        uint256 i = 0;
        while (i < _targets.length) {
            if (!releaseWithAmount(_targets[i], _dests[i])) {
                return false;
            }

            i = i.add(1);
        }

        return true;
    }
}