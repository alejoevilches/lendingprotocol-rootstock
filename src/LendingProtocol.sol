// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title LendingProtocol
/// @author Alejo Vilches
/// @notice A lending protocol contract for managing loans and bids. Final project for the Rootstock Rootcamp.
contract LendingProtocol{
    enum LendingState{
        REQUESTED,
        BIDDING,
        CLOSED,
        PAYED,
        DEFAULTED
    }

    struct Loan{
        uint256 id;
        address owner;
        LendingState status;
        uint256 amount;
        uint256 startDate;
        uint256 dueDate;
    }

    struct Bid{
        uint256 id;
        uint256 loanId;
        uint256 interest;
    }

    error BidLoan_LoanNotInRequestedStatus();
    error BidLoan_InvalidLoanId();
    error BidLoan_InvalidInterestRate();

    uint256 private constant MAX_INTEREST_BASIS_POINT=10000;

    /// @notice Counter for tracking the total number of loans created
    uint256 public loanCounter;
    /// @notice Counter for tracking the total number of bids created
    uint256 public bidCounter;

    mapping(uint256=>Loan) private idToLoan;
    mapping(uint256=>Bid) private idToBid;
    mapping(uint256=>uint256[]) private loanIdToBidId;

    /// @notice Creates a new loan request
    /// @param amount The loan amount requested
    function createLoan(uint256 amount) external{
        Loan memory payload = Loan({
            id: loanCounter,
            owner: msg.sender,
            amount: amount,
            status: LendingState.REQUESTED,
            startDate: 0,
            dueDate: 0
        });
        idToLoan[loanCounter] = payload;
        ++loanCounter;
    }

    /// @notice Places a bid on a loan request
    /// @param loanId The ID of the loan to bid on
    /// @param interest The interest rate for the bid in basis points
    function bidLoan(uint256 loanId, uint256 interest) external{
        if(loanId > loanCounter - 1) revert BidLoan_InvalidLoanId();
        if(idToLoan[loanId].status != LendingState.REQUESTED) revert BidLoan_LoanNotInRequestedStatus();
        if(interest == 0 || interest > MAX_INTEREST_BASIS_POINT) revert BidLoan_InvalidInterestRate();
        Bid memory payload = Bid({
            id: bidCounter,
            loanId: loanId,
            interest: interest
        });
        idToBid[bidCounter] = payload;
        loanIdToBidId[loanId].push(bidCounter);
        ++bidCounter;
    }

    function closeLoan(uint256 loanId) external{

    }
}