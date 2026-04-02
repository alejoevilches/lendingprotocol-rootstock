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
        address lender;
    }

    struct Bid{
        uint256 id;
        uint256 loanId;
        uint256 interest;
    }

    error BidLoan_LoanNotInBiddingStatus();
    error StartBiddingProcess_InvalidStateOfLoan();
    error InvalidLoanId();
    error BidLoan_InvalidInterestRate();
    error CloseLoan_InvalidStateOfLoan();
    error CloseLoan_LoanHasNoBids();
    error PayLoan_NotEnoughRBTC();
    error PayLoan_ErrorRefundingRBTC();
    error PayLoan_ErrorPayingLoan();

    uint256 private constant MAX_INTEREST_BASIS_POINT=10000;

    /// @notice Counter for tracking the total number of loans created
    uint256 public loanCounter;
    /// @notice Counter for tracking the total number of bids created
    uint256 public bidCounter;

    mapping(uint256=>Loan) private idToLoan;
    mapping(uint256=>Bid) private idToBid;
    mapping(uint256=>uint256[]) private loanIdToBidId;
    mapping(uint256=>uint256) private loanIdToWinningBidId;

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

    /// @notice Starts the bidding process for a loan request
    /// @param loanId The ID of the loan to start bidding on
    function startBiddingProcess(uint256 loanId) external{
        if(loanId == loanCounter + 1) revert InvalidLoanId();
        if(idToLoan[loanId].status != LendingState.REQUESTED) revert StartBiddingProcess_InvalidStateOfLoan();
        idToLoan[loanId].status = LendingState.BIDDING;
    }

    /// @notice Places a bid on a loan request
    /// @param loanId The ID of the loan to bid on
    /// @param interest The interest rate for the bid in basis points
    function bidLoan(uint256 loanId, uint256 interest) external{
        if(loanId >= loanCounter + 1) revert InvalidLoanId();
        if(idToLoan[loanId].status != LendingState.BIDDING) revert BidLoan_LoanNotInBiddingStatus();
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

    /// @notice Closes the bidding process for a loan and selects the best bid
    /// @param loanId The ID of the loan to close
    function closeLoan(uint256 loanId) external{
        if(loanId >= loanCounter + 1) revert InvalidLoanId();
        if(idToLoan[loanId].status != LendingState.BIDDING) revert CloseLoan_InvalidStateOfLoan();

        uint256[] storage bidIds = loanIdToBidId[loanId];
        if(bidIds.length == 0) revert CloseLoan_LoanHasNoBids();
        uint256 bestBidId = bidIds[0];
        for(uint256 i = 1; i < bidIds.length; ++i){
            uint256 currentBidId = bidIds[i];

            if(idToBid[currentBidId].interest < idToBid[bestBidId].interest){
                bestBidId = currentBidId;
            }
        }
        loanIdToWinningBidId[loanId] = bestBidId;
        idToLoan[loanId].status = LendingState.CLOSED;
    }
}

function payLoan(uint256 loanId) external payable{
    if(loanId >= loanCounter + 1) revert InvalidLoanId();
    Loan memory selectedLoan = idToLoan[loanId];
    Bid memory winnerBid = idToBid[loanIdToWinningBidId[loanId]];
    uint256 totalAmount = selectedLoan.amount + (selectedLoan.amount * winnerBid.interest / MAX_INTEREST_BASIS_POINT);
    if(msg.value < totalAmount) revert PayLoan_NotEnoughRBTC();
    if(msg.value > totalAmount) {
        uint256 difference = msg.value - totalAmount;
        (bool success, ) = payable(msg.sender).call{value: difference};
        if(!success) revert PayLoan_ErrorRefundingRBTC();
    }
    (bool success, ) = payable(selectedLoan.lender).call{value: totalAmount};
    idToLoan[loanId].status = LendingState.PAYED;
    if(!success) revert PayLoan_ErrorPayingLoan();
}
