// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LendingProtocol{
    enum LendingState{
        REQUESTED,
        BIDDING,
        CLOSED,
        PAYED,
        DEFAULTED
    };

    struct Loan{
        uint256 id,
        address owner,
        LendingState status,
        uint256 amount,
        uint256 startDate,
        uint256 dueDate
    }

    struct Bid{
        uint256 id,
        uint256 loanId,
        uint256 interest,
    }

    error BidLoan_LoanNotInBiddingStatus;

    Loan[] private loansCollection;
    uint256 loanCounter;
    uint256 bidCounter;

    mapping(uint256=>Loan) idToLoan;
    mappint(uint256=>Bid) idToBid;

    function createLoan(uint256 amount){
        Loan payload = Loan({
            id: loanCounter,
            address: msg.sender,
            amount,
            status: LendingState.REQUESTED
        });
        loansCollection.push(payload);
        idToLoan[loanCounter] = payload;
        loanCounter++;
    }

    function bidLoan(uint256 loanId, uint256 interest){

        Bid payload = Bid({
            id: bidCounter,
            loanID,
            interest
        });
        idToBid[bidCounter] = payload;
        bidCounter++;
    }
}